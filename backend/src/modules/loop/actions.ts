import { and, eq, sql } from "drizzle-orm";
import { withTransaction, type Tx } from "../../db/tx.js";
import {
  idempotencyKeys,
  playerItems,
  playerSkills,
  playerStageProgress,
  playerStates,
  players,
} from "../../db/schema.js";
import { simulateBossFight, type UltConfig } from "../combat/battle.js";
import { computePower, ratePower, resolveBreakthrough, skillLayerFactor, sumReachedRealmStats } from "../combat/stats.js";
import { ensureSkillBook } from "../content/ops-content.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { rollDropTable } from "../content/roll-drops.js";
import { bookOverflowCultivation, rollSchemeReward } from "../content/scheme-drops.js";
import { decomposeEnhanceExp, enhanceCap, enhanceCost, enhancedStat, pendingBreakNode, qualityRule, readEnhanceRules } from "../content/enhance.js";
import type { ContentSnapshot } from "../content/validate.js";
import { settleTicks } from "../progress/settle.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { readGameRules } from "../content/rules.js";
import { addEnhanceExp, grantItem } from "./bag.js";
import { applySetBonus, setBonusOf } from "../content/set-bonus.js";
import { maxSkillSlots, nextSkillSlotRule, openSkillSlots } from "../content/skill-slots.js";
import { announcementNoticesForPlayer, noticesForPlayer } from "../notices/service.js";
import { bossDailyUsed, grantBossRewards, usesRewardModel } from "./boss-rewards.js";
import { acknowledgeOfflineReport, pendingOfflineReport, recordOfflineReport } from "./offline.js";
import { EMPTY_WAVES, cycleFor, farmableStages, resolveFarmStage, settleWaves, waveRandomInt, wavesCompletedIn, type WaveSettlement } from "./waves.js";
import { bossRulesFor, globalBossRules, nextStageOf, orderedStages, stageAccessList, stageTier, type StageAccess } from "../content/stage-order.js";
import { stageRecommendedPower } from "../content/stage-power.js";

type World = ContentSnapshot & { version: number };
type RandomInt = (min: number, max: number) => number;

async function lockedState(tx: Tx, playerId: string) {
  const [state] = await tx.select().from(playerStates).where(eq(playerStates.playerId, playerId)).for("update").limit(1);
  const [player] = await tx.select().from(players).where(eq(players.id, playerId)).limit(1);
  if (!state || !player) {
    throw new AppError("NOT_FOUND");
  }
  return { state, player };
}

function realmOf(world: World, slug: string) {
  const realm = world.realms.find((row) => row.slug === slug);
  if (!realm) {
    throw new AppError("NOT_FOUND", `境界编号 ${slug} 不存在，请删掉这个测试账号后重新注册`);
  }
  return realm;
}

async function loadPieces(tx: Tx, playerId: string) {
  const items = await tx.select().from(playerItems).where(eq(playerItems.playerId, playerId));
  const skills = await tx.select().from(playerSkills).where(eq(playerSkills.playerId, playerId));
  const stages = await tx.select().from(playerStageProgress).where(eq(playerStageProgress.playerId, playerId));
  return { items, skills, stages };
}

/** 这个境界开放的功法栏位数（配置概览「功法栏位」，按境界开放）。 */
export function openSkillSlotsFor(world: ContentSnapshot, realmSlug: string): number {
  const order = world.realms.find((row) => row.slug === realmSlug)?.sortOrder ?? 0;
  return openSkillSlots(world.globals.artSlotRules, order);
}

/**
 * 运转中的功法里，算属性 / 战力的那几门：最多「开放栏位数」门。
 * 按栏位号 run_1、run_2… 排，旧数据里别的栏位名（例如 heart）排在后面；后台把栏位调少以后，多出来的不生效。
 */
export function countedSkills<T extends { skillSlug: string; runningSlot: string | null }>(world: ContentSnapshot, realmSlug: string, skills: T[]): T[] {
  const index = (slot: string | null) => Number(slot?.match(/^run_(\d+)$/)?.[1] ?? Number.MAX_SAFE_INTEGER);
  return skills
    .filter((skill) => skill.runningSlot)
    .sort((left, right) => index(left.runningSlot) - index(right.runningSlot) || left.skillSlug.localeCompare(right.skillSlug))
    .slice(0, openSkillSlotsFor(world, realmSlug));
}

function statsOf(world: World, realmSlug: string, items: { itemSlug: string; equippedSlot: string | null; enhanceLevel: number }[], skills: { skillSlug: string; runningSlot: string | null; level: number }[]) {
  return combatStats(
    world,
    realmSlug,
    items.filter((item) => item.equippedSlot).map((item) => ({ slug: item.itemSlug, enhanceLevel: item.enhanceLevel })),
    countedSkills(world, realmSlug, skills).map((skill) => ({ slug: skill.skillSlug, level: skill.level })),
  );
}

function skillLayers(skillSlugs: (string | { slug: string; level: number })[]) {
  return skillSlugs.map((entry) => {
    if (typeof entry === "string") {
      return { slug: entry, level: 1 };
    }
    if (!Number.isInteger(entry.level) || entry.level < 1) {
      throw new AppError("INVALID_INPUT", "功法层数不正确");
    }
    return entry;
  });
}

/** 装备按强化等级放大后的四项属性；0 级不读强化规则。 */
function enhancedGear(
  world: ContentSnapshot,
  definition: { attack?: number; defense?: number; hp?: number; speed?: number; quality?: string } | undefined,
  level: number,
) {
  const base = { attack: definition?.attack ?? 0, defense: definition?.defense ?? 0, hp: definition?.hp ?? 0, speed: definition?.speed ?? 0 };
  if (!definition || level <= 0) {
    return base;
  }
  const rules = readEnhanceRules(world);
  return {
    attack: enhancedStat(base.attack, level, rules, definition.quality),
    defense: enhancedStat(base.defense, level, rules, definition.quality),
    hp: enhancedStat(base.hp, level, rules, definition.quality),
    speed: enhancedStat(base.speed, level, rules, definition.quality),
  };
}

export function combatStats(world: ContentSnapshot, realmSlug: string, itemSlugs: (string | { slug: string; enhanceLevel: number })[], skillSlugs: (string | { slug: string; level: number })[]) {
  const realm = world.realms.find((row) => row.slug === realmSlug);
  if (!realm) {
    throw new AppError("NOT_FOUND", `境界编号 ${realmSlug} 不存在，请删掉这个测试账号后重新注册`);
  }
  if (realm.sortOrder == null) {
    throw new AppError("INVALID_INPUT", "境界没有编号");
  }
  const reached = sumReachedRealmStats(
    world.realms
      .filter((row) => row.sortOrder != null)
      .map((row) => ({
        sortOrder: row.sortOrder as number,
        attack: row.baseAttack ?? 0,
        defense: row.baseDefense ?? 0,
        hp: row.baseHp ?? 0,
        speed: row.baseSpeed ?? 0,
      })),
    realm.sortOrder,
  );
  let gearAttack = 0;
  let gearDefense = 0;
  let gearHp = 0;
  let gearSpeed = 0;
  let bonusBp = 0;
  for (const entry of itemSlugs) {
    const itemSlug = typeof entry === "string" ? entry : entry.slug;
    const level = typeof entry === "string" ? 0 : entry.enhanceLevel;
    const definition = world.items.find((row) => row.slug === itemSlug);
    const grown = enhancedGear(world, definition, level);
    gearAttack += grown.attack;
    gearDefense += grown.defense;
    gearHp += grown.hp;
    gearSpeed += grown.speed;
  }
  let attackPercent = 0;
  let defensePercent = 0;
  let hpPercent = 0;
  for (const entry of skillLayers(skillSlugs)) {
    const definition = world.skills.find((row) => row.slug === entry.slug);
    const factor = skillLayerFactor(entry.level, world.globals.tuning);
    attackPercent += ((definition?.attack ?? 0) / 10000) * factor;
    defensePercent += ((definition?.defense ?? 0) / 10000) * factor;
    hpPercent += ((definition?.hp ?? 0) / 10000) * factor;
    bonusBp += (definition?.cultivateBonusBp ?? 0) * factor;
  }
  // 套装加成（批次②）：按角色总属性（境界 + 功法 + 装备）算百分比，再加固定值。
  const setBonus = setBonusOf(world, itemSlugs.map((entry) => (typeof entry === "string" ? entry : entry.slug)));
  const { attack, defense, hp, speed } = applySetBonus(
    {
      attack: reached.attack * (1 + attackPercent) + gearAttack,
      defense: reached.defense * (1 + defensePercent) + gearDefense,
      hp: reached.hp * (1 + hpPercent) + gearHp,
      speed: reached.speed + gearSpeed,
    },
    setBonus,
  );
  if (realm.baseInterval == null || realm.baseInterval <= 0) {
    throw new AppError("INVALID_INPUT", `境界「${realm.displayName ?? realm.slug}」还没有基础出手间隔`);
  }
  const rules = readGameRules(world);
  const combat = computePower({
    attack,
    defense,
    hp,
    speed,
    baseInterval: realm.baseInterval,
    minInterval: rules.minInterval,
    speedBase: rules.speedBase,
    weights: rules.powerWeights,
  });
  return { attack, defense, hp, speed, interval: combat.interval, power: combat.power, bonusBp, sets: setBonus.sets };
}

export type PowerSourceLine = {
  group: "境界" | "物品" | "功法" | "套装";
  name: string;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  counted: boolean;
  note: string;
};

export type PowerBreakdown = {
  power: number | null;
  error: string | null;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  weights: { attack: number; defense: number; hp: number; speed: number } | null;
  lines: PowerSourceLine[];
  steps: string[];
};

function showNumber(value: number): string {
  return String(Math.round(value * 10000) / 10000);
}

function statOf(value: number | null | undefined): number {
  return value ?? 0;
}

export function explainPlayerPower(
  world: ContentSnapshot,
  realmSlug: string,
  items: { itemSlug: string; equippedSlot: string | null; quantity: number; enhanceLevel?: number }[],
  skills: { skillSlug: string; runningSlot: string | null; level: number }[],
): PowerBreakdown {
  const empty = { attack: 0, defense: 0, hp: 0, speed: 0, weights: null, lines: [] as PowerSourceLine[], steps: [] as string[] };
  const realm = world.realms.find((row) => row.slug === realmSlug);
  if (!realm || realm.sortOrder == null) {
    return { ...empty, power: null, error: "境界不存在" };
  }
  const lines: PowerSourceLine[] = [];
  for (const row of world.realms.filter((item) => item.sortOrder != null && item.sortOrder <= (realm.sortOrder as number)).sort((left, right) => (left.sortOrder ?? 0) - (right.sortOrder ?? 0))) {
    lines.push({
      group: "境界",
      name: row.displayName || "名称缺失",
      attack: statOf(row.baseAttack),
      defense: statOf(row.baseDefense),
      hp: statOf(row.baseHp),
      speed: statOf(row.baseSpeed),
      counted: true,
      note: "到达过的境界都计入",
    });
  }
  for (const item of items) {
    const definition = world.items.find((row) => row.slug === item.itemSlug);
    const name = definition?.displayName || (definition ? "名称缺失" : "已删除");
    const quantity = item.quantity > 1 ? ` × ${item.quantity}` : "";
    const equipped = Boolean(item.equippedSlot);
    const level = item.enhanceLevel ?? 0;
    const grown = equipped ? enhancedGear(world, definition, level) : { attack: 0, defense: 0, hp: 0, speed: 0 };
    lines.push({
      group: "物品",
      name: `${name}${level > 0 ? ` +${level}` : ""}${quantity}`,
      attack: grown.attack,
      defense: grown.defense,
      hp: grown.hp,
      speed: grown.speed,
      counted: equipped,
      note: !definition ? "后台里已经没有这件" : equipped ? (level > 0 ? `已穿上，强化 +${level}` : "已穿上") : "在背包，不算战力",
    });
  }
  const reached = sumReachedRealmStats(
    world.realms
      .filter((item) => item.sortOrder != null && item.sortOrder <= (realm.sortOrder as number))
      .map((item) => ({
        sortOrder: item.sortOrder as number,
        attack: statOf(item.baseAttack),
        defense: statOf(item.baseDefense),
        hp: statOf(item.baseHp),
        speed: statOf(item.baseSpeed),
      })),
    realm.sortOrder as number,
  );
  const counted = new Set(countedSkills(world, realmSlug, skills).map((skill) => skill.skillSlug));
  for (const skill of skills) {
    const definition = world.skills.find((row) => row.slug === skill.skillSlug);
    const level = skill.level;
    const running = counted.has(skill.skillSlug);
    if (!Number.isInteger(level) || level < 1) {
      lines.push({
        group: "功法",
        name: definition?.displayName || "名称缺失",
        attack: 0,
        defense: 0,
        hp: 0,
        speed: 0,
        counted: false,
        note: "功法层数不正确",
      });
      continue;
    }
    const factor = skillLayerFactor(level, world.globals.tuning);
    lines.push({
      group: "功法",
      name: `${definition?.displayName || (definition ? "名称缺失" : "已删除")} · ${level}本`,
      attack: running ? reached.attack * (statOf(definition?.attack) / 10000) * factor : 0,
      defense: running ? reached.defense * (statOf(definition?.defense) / 10000) * factor : 0,
      hp: running ? reached.hp * (statOf(definition?.hp) / 10000) * factor : 0,
      speed: 0,
      counted: running,
      note: !definition ? "后台里已经没有这门功法" : running ? "境界基础 × 百分比 × 层数系数" : "没有运转，不算战力",
    });
  }
  const sumLines = () =>
    lines.filter((line) => line.counted).reduce(
      (sum, line) => ({
        attack: sum.attack + line.attack,
        defense: sum.defense + line.defense,
        hp: sum.hp + line.hp,
        speed: sum.speed + line.speed,
      }),
      { attack: 0, defense: 0, hp: 0, speed: 0 },
    );
  // 套装加成：百分比按上面的总属性算，加固定值；每个套装一行。
  const before = sumLines();
  const setBonus = setBonusOf(world, items.filter((item) => item.equippedSlot).map((item) => item.itemSlug));
  for (const active of setBonus.sets) {
    const set = (world.gearSets ?? []).find((row) => row.slug === active.setSlug);
    const one = setBonusOf({ items: world.items, gearSets: set ? [set] : [] }, items.filter((item) => item.equippedSlot).map((item) => item.itemSlug));
    const grown = applySetBonus(before, one);
    lines.push({
      group: "套装",
      name: `${active.displayName}（穿 ${active.worn} 件）`,
      attack: grown.attack - before.attack,
      defense: grown.defense - before.defense,
      hp: grown.hp - before.hp,
      speed: grown.speed - before.speed,
      counted: active.activePieces.length > 0,
      note: active.activePieces.length > 0 ? `${active.activePieces.map((pieces) => `${pieces} 件`).join("、")}加成生效` : "件数不够，加成没生效",
    });
  }
  const totals = sumLines();
  let weights: PowerBreakdown["weights"] = null;
  let error: string | null = null;
  try {
    weights = readGameRules(world).powerWeights;
  } catch (cause) {
    error = cause instanceof Error ? cause.message : "规则还没填";
  }
  if (!weights) {
    return { ...empty, ...totals, lines, power: null, error };
  }
  const attackPart = totals.attack * weights.attack;
  const defensePart = totals.defense * weights.defense;
  const hpPart = totals.hp * weights.hp;
  const speedPart = totals.speed * weights.speed;
  const raw = attackPart + defensePart + hpPart + speedPart;
  const power = ratePower(totals, weights);
  return {
    power,
    error: null,
    ...totals,
    weights,
    lines,
    steps: [
      `攻击 ${showNumber(totals.attack)} × 权重 ${showNumber(weights.attack)} = ${showNumber(attackPart)}`,
      `防御 ${showNumber(totals.defense)} × 权重 ${showNumber(weights.defense)} = ${showNumber(defensePart)}`,
      `气血 ${showNumber(totals.hp)} × 权重 ${showNumber(weights.hp)} = ${showNumber(hpPart)}`,
      `速度 ${showNumber(totals.speed)} × 权重 ${showNumber(weights.speed)} = ${showNumber(speedPart)}`,
      `${showNumber(attackPart)} + ${showNumber(defensePart)} + ${showNumber(hpPart)} + ${showNumber(speedPart)} = ${showNumber(raw)}，四舍五入后战力 ${power}`,
    ],
  };
}

export function battleConfigOf(world: ContentSnapshot) {
  const rules = readGameRules(world);
  return {
    timeLimitSeconds: rules.timeLimitSeconds,
    defenseConstant: rules.defenseConstant,
  };
}

async function settleLocked(tx: Tx, playerId: string, world: World, now: Date, options: { autoChallenge?: boolean } = {}) {
  const { state } = await lockedState(tx, playerId);
  let pieces = await loadPieces(tx, playerId);
  const stats = statsOf(world, state.realmSlug, pieces.items, pieces.skills);
  const rules = readGameRules(world);
  const realm = realmOf(world, state.realmSlug);
  const settled = settleTicks({
    cultivation: state.cultivation,
    lastSettledAt: state.lastSettledAt,
    now,
    tickSeconds: realm.tickSeconds,
    gainPerTick: realm.gainPerTick,
    bonusBp: stats.bonusBp,
    offlineCapSeconds: rules.offlineCapSeconds,
    remainderBp: state.cultivationRemainderBp,
  });
  // 在线 / 离线：距离上次结算不超过 onlineGapSeconds 记为在线（前台心跳），在线才有普通怪击杀修为和装备掉落；
  // 超过就是一段离线（只有上面的挂机修为）。
  const gapSeconds = Math.max(0, (now.getTime() - state.lastSettledAt.getTime()) / 1000);
  const online = gapSeconds <= rules.onlineGapSeconds;
  const consumedSeconds = Math.max(0, (settled.lastSettledAt.getTime() - state.lastSettledAt.getTime()) / 1000);
  let waves: WaveSettlement = { ...EMPTY_WAVES, online };
  let access = realm.sortOrder == null ? [] : stageAccessList(world, realm.sortOrder, pieces.stages);
  const stage = resolveFarmStage(world, access, state.idleStageSlug);
  if (online && stage && consumedSeconds > 0) {
    waves = await settleWaves(tx, world, playerId, {
      rules,
      stage,
      stats,
      progress: state.waveProgress,
      deathsInRow: state.waveDeathsInRow,
      consumedSeconds,
      autoDecompose: state.autoDecompose,
      capacity: rules.bagCapacity + state.bagBonus,
      now,
    });
  } else if (online && stage) {
    waves = { ...EMPTY_WAVES, online, stageSlug: stage.slug, monsterName: stage.monsters?.[0]?.name ?? null, progress: state.waveProgress, deathsInRow: state.waveDeathsInRow };
  }
  const waveProgress = online ? (stage ? waves.progress : 0) : 0;
  const waveDeathsInRow = online ? (stage ? waves.deathsInRow : 0) : 0;
  const cultivation = settled.cultivation + waves.killCultivation;
  const [saved] = await tx
    .update(playerStates)
    .set({
      cultivation,
      lastSettledAt: settled.lastSettledAt,
      cultivationRemainderBp: settled.remainderBp,
      waveProgress,
      waveDeathsInRow,
      stateVersion: state.stateVersion + 1,
    })
    .where(eq(playerStates.playerId, playerId))
    .returning();
  // 离线弹窗：这一段离线 ≥ 弹窗最短时长就记一条（修为已经入账，没有领取步骤）。
  if (!online && gapSeconds >= rules.offlinePopupMinSeconds && settled.countedSeconds > 0) {
    await recordOfflineReport(tx, {
      playerId,
      startedAt: state.lastSettledAt,
      endedAt: now,
      seconds: Math.floor(gapSeconds),
      countedSeconds: settled.countedSeconds,
      hitCap: settled.hitCap,
      gained: settled.gained,
      baseGained: Math.floor(settled.countedSeconds / Math.max(1, realm.tickSeconds)) * realm.gainPerTick,
      realmSlug: state.realmSlug,
    });
  }
  const offlineReport = await pendingOfflineReport(tx, playerId);
  let kept = saved ?? { ...state, cultivation, lastSettledAt: settled.lastSettledAt, cultivationRemainderBp: settled.remainderBp, waveProgress, waveDeathsInRow };
  if (waves.drops.length > 0 || waves.kills > 0) {
    pieces = { ...pieces, items: (await loadPieces(tx, playerId)).items };
  }
  // 第四批 · 挂机刷首领：本关首领已击败时，这次结算里打完的波数累计到本关计数，攒够 N 波打一场（在线按实际推进的波数；
  // 离线不推进波次，按计入的时长 ÷ 一波的秒数折算）。先算好再自动挑战，这样刚被自动挑战打赢的首领，这次的波数不算。
  let idleWaves = 0;
  if (stage && consumedSeconds > 0) {
    if (online) {
      idleWaves = waves.wavesCompleted;
    } else if (stage.monsters?.[0]) {
      idleWaves = wavesCompletedIn(0, consumedSeconds, cycleFor(rules, stats, stage.monsters[0]));
    }
  }
  let idleBoss: IdleBossResult | null = null;
  if (stage && idleWaves > 0) {
    idleBoss = await settleIdleBosses(tx, world, playerId, { state: kept, stats, pieces, access }, stage, idleWaves, now);
    if (idleBoss) {
      const [fresh] = await tx.select().from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
      kept = fresh ?? kept;
    }
    pieces = await loadPieces(tx, playerId);
  }
  // 自动挑战（首领规则「允许自动挑战」）：挂机关卡的首领还没击败、战力 ≥ 推荐战力 × 比例时，结算里直接打一场。
  let autoChallenge: AutoChallengeResult | null = null;
  if (options.autoChallenge !== false && stage) {
    autoChallenge = await tryAutoChallenge(tx, world, playerId, { state: kept, stats, pieces, access }, stage, now);
    if (autoChallenge) {
      const [fresh] = await tx.select().from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
      kept = fresh ?? kept;
      pieces = await loadPieces(tx, playerId);
      access = realm.sortOrder == null ? [] : stageAccessList(world, realm.sortOrder, pieces.stages);
    }
  }
  return {
    state: kept,
    pieces,
    stats,
    settled,
    waves,
    stage,
    access,
    autoChallenge,
    idleBoss,
    gapSeconds,
    now,
    offlineReport,
  };
}

/** 大境界突破要先通关的首领关（没有门槛就是 null），客户端用它显示“先去挑战 XX”。 */
function gateOf(world: World, realm: { requiredStageSlug: string | null }, progress: { stageSlug: string; firstClearedAt: Date | null }[]) {
  if (!realm.requiredStageSlug) {
    return null;
  }
  const stage = world.stages.find((row) => row.slug === realm.requiredStageSlug);
  return {
    slug: realm.requiredStageSlug,
    name: stage?.displayName ?? realm.requiredStageSlug,
    bossName: stage?.bosses?.[0]?.name ?? stage?.bossName ?? "",
    cleared: progress.some((row) => row.stageSlug === realm.requiredStageSlug && row.firstClearedAt != null),
  };
}

function stateDto(world: World, playerId: string, settled: Awaited<ReturnType<typeof settleLocked>>) {
  const realm = realmOf(world, settled.state.realmSlug);
  const next = realm.nextRealmSlug ? world.realms.find((row) => row.slug === realm.nextRealmSlug) : undefined;
  const rateBp = next ? 10000 : 0;
  return {
    playerId,
    contentVersion: world.version,
    cultivation: settled.state.cultivation,
    spiritStones: settled.state.spiritStones,
    realmSlug: settled.state.realmSlug,
    realmName: realm.displayName ?? settled.state.realmSlug,
    power: settled.stats.power,
    attack: settled.stats.attack,
    defense: settled.stats.defense,
    hp: settled.stats.hp,
    speed: settled.stats.speed,
    interval: settled.stats.interval,
    cultivationRate: { bonusBp: settled.stats.bonusBp, gainPerTick: realm.gainPerTick },
    breakthrough: { rateBp, cost: realm.breakthroughCost, nextSlug: realm.nextRealmSlug, requiredStage: gateOf(world, realm, settled.pieces.stages), preview: breakthroughPreview(world, next, settled) },
    challengeCooldownSeconds: readGameRules(world).challengeCooldownSeconds,
    autoDecompose: settled.state.autoDecompose,
    enhanceExp: settled.state.enhanceExp,
    bagBonus: settled.state.bagBonus,
    bagCapacity: readGameRules(world).bagCapacity + settled.state.bagBonus,
    items: settled.pieces.items,
    skills: settled.pieces.skills,
    skillSlots: skillSlotsDto(world, settled.state.realmSlug),
    // 套装：穿着的每个套装几件、哪些档位已生效（游戏端装备弹窗用；数值定义在 /content/current 的 gearSets）
    activeSets: setBonusOf(world, settled.pieces.items.filter((item) => item.equippedSlot).map((item) => item.itemSlug)).sets,
    stages: settled.pieces.stages,
    stageAccess: settled.access.map((row) => accessDto(world, row)),
    wave: waveDto(world, settled),
    offlineReport: settled.offlineReport
      ? {
          id: settled.offlineReport.id,
          startedAt: settled.offlineReport.startedAt,
          endedAt: settled.offlineReport.endedAt,
          seconds: settled.offlineReport.seconds,
          countedSeconds: settled.offlineReport.countedSeconds,
          hitCap: settled.offlineReport.hitCap,
          offlineCapSeconds: readGameRules(world).offlineCapSeconds,
          gained: settled.offlineReport.gained,
          baseGained: settled.offlineReport.baseGained,
          bonusGained: settled.offlineReport.bonusGained,
          realmName: world.realms.find((row) => row.slug === settled.offlineReport?.realmSlug)?.displayName ?? settled.offlineReport.realmSlug,
        }
      : null,
    ult: ultOf(world, settled.state.realmSlug),
    bossDaily: bossDailyDto(world, settled),
    bossDailyTotal: bossDailyTotalDto(world, settled),
    lastSettle: {
      online: settled.waves.online,
      seconds: Math.floor(settled.gapSeconds),
      passiveGained: settled.settled.gained,
      kills: settled.waves.kills,
      deaths: settled.waves.deaths,
      killCultivation: settled.waves.killCultivation,
      drops: settled.waves.drops,
      bagFull: settled.waves.bagFull,
      autoChallenge: settled.autoChallenge,
      idleBoss: settled.idleBoss,
    },
  };
}

/** 历练页用：每关能不能进、为什么不能进（解锁条件两项分别满足没有）、首领档次。 */
function accessDto(world: World, access: StageAccess) {
  const stage = world.stages.find((row) => row.slug === access.slug);
  return {
    ...access,
    tier: stage ? stageTier(world, stage) : null,
    chapterSlug: stage?.chapterSlug ?? null,
  };
}

/** 突破后的样子（沿用现在穿的装备和运转的功法）：属性、战力、每秒修为、大招、新开放的关卡。突破流程界面用它显示“突破后”。 */
/** 功法栏位：现在开放几个、最多几个、下一个在哪个境界开。 */
function skillSlotsDto(world: World, realmSlug: string) {
  const order = world.realms.find((row) => row.slug === realmSlug)?.sortOrder ?? 0;
  const next = nextSkillSlotRule(world.globals.artSlotRules, order);
  return {
    open: openSkillSlots(world.globals.artSlotRules, order),
    max: maxSkillSlots(world.globals.artSlotRules),
    next: next ? { slots: next.slots, realmOrder: next.minRealmOrder, realmName: world.realms.find((row) => row.sortOrder === next.minRealmOrder)?.displayName ?? "" } : null,
  };
}

function breakthroughPreview(world: World, next: World["realms"][number] | undefined, settled: Awaited<ReturnType<typeof settleLocked>>) {
  if (!next || next.sortOrder == null) {
    return null;
  }
  const after = statsOf(world, next.slug, settled.pieces.items, settled.pieces.skills);
  return {
    realmName: next.displayName ?? next.slug,
    attack: after.attack,
    defense: after.defense,
    hp: after.hp,
    speed: after.speed,
    interval: after.interval,
    power: after.power,
    gainPerTick: next.gainPerTick,
    tickSeconds: next.tickSeconds,
    ult: ultOf(world, next.slug),
    newStages: world.stages
      .filter((stage) => stage.requiredRealmOrder === next.sortOrder)
      .map((stage) => ({ slug: stage.slug, name: stage.displayName ?? stage.slug })),
  };
}

/** 每个已首通、重打给奖励（首领规则）且配了重复挑战奖励的首领：今天已经领了几次、一共几次。 */
/**
 * 第三批的「每关每日次数」格式（老客户端 0.17.0 还在读）：第四批起每关都显示同一个全局次数。
 * 新客户端读 bossDailyTotal。
 */
function bossDailyDto(world: World, settled: Awaited<ReturnType<typeof settleLocked>>) {
  const total = bossDailyTotalDto(world, settled);
  return settled.pieces.stages.flatMap((row) => {
    const stage = world.stages.find((candidate) => candidate.slug === row.stageSlug);
    const boss = stage?.bosses?.[0];
    if (!stage || !row.firstClearedAt || !boss?.repeat || !bossRulesFor(world, stage).repeatRewards || total.limit <= 0) {
      return [];
    }
    return [{ stageSlug: row.stageSlug, used: total.used, limit: total.limit }];
  });
}

/** 第四批：每日首领挑战总次数（所有首领合计）：今天已用 / 总数；挂机刷首领每关进度（已击败的关）。 */
function bossDailyTotalDto(world: World, settled: Awaited<ReturnType<typeof settleLocked>>) {
  const rules = readGameRules(world);
  const global = globalBossRules(world);
  return {
    used: bossDailyUsed(settled.state, rules, settled.now),
    limit: global.dailyChallengeTotal,
    idleWaves: settled.pieces.stages
      .filter((row) => row.firstClearedAt)
      .flatMap((row) => {
        const stage = world.stages.find((candidate) => candidate.slug === row.stageSlug);
        if (!stage?.bosses?.[0]) return [];
        const bossRules = bossRulesFor(world, stage);
        return bossRules.idleSpawn ? [{ stageSlug: row.stageSlug, waves: row.idleWaves, every: bossRules.idleSpawnWaves, countsDaily: bossRules.idleSpawnCountsDaily }] : [];
      }),
  };
}

/** 普通怪波次的当前状态：在哪个关卡刷、一波多久、进行到哪、可以切到哪些关卡。 */
function waveDto(world: World, settled: Awaited<ReturnType<typeof settleLocked>>) {
  const rules = readGameRules(world);
  const monster = settled.stage?.monsters?.[0];
  const cycle = monster ? cycleFor(rules, settled.stats, monster) : null;
  return {
    available: Boolean(settled.stage && monster),
    stageSlug: settled.stage?.slug ?? null,
    stageName: settled.stage?.displayName ?? null,
    monster: monster ? { name: monster.name, artKey: monster.artKey ?? null, hp: monster.hp, attack: monster.attack, defense: monster.defense, interval: monster.interval, killCultivation: monster.killCultivation } : null,
    waveSize: rules.waveSize,
    cycleSeconds: cycle ? Math.round(cycle.cycleSeconds * 1000) / 1000 : null,
    killsPerWave: cycle?.kills ?? 0,
    deathsPerWave: cycle?.deaths ?? 0,
    progress: Math.round(settled.state.waveProgress * 1000) / 1000,
    deathsInRow: settled.state.waveDeathsInRow,
    onlineGapSeconds: rules.onlineGapSeconds,
    chosenStageSlug: settled.state.idleStageSlug,
    selectable: farmableStages(world, settled.access).map((stage) => ({ slug: stage.slug, name: stage.displayName ?? stage.slug, monsterName: stage.monsters?.[0]?.name ?? "" })),
  };
}

async function worldOrThrow(db: Db | Tx) {
  const world = await loadCurrentWorld(db);
  if (!world) {
    throw new AppError("CONTENT_NOT_PUBLISHED");
  }
  return world;
}

export async function withIdempotency<T>(
  db: Db,
  playerId: string,
  key: string | undefined,
  endpoint: string,
  now: Date,
  fn: (tx: Tx, world: World) => Promise<T>,
): Promise<T> {
  if (!key) {
    throw new AppError("IDEMPOTENCY_KEY_REQUIRED");
  }
  return withTransaction(db, async (tx) => {
    const [existing] = await tx
      .select()
      .from(idempotencyKeys)
      .where(and(eq(idempotencyKeys.playerId, playerId), eq(idempotencyKeys.key, key)))
      .limit(1);
    if (existing) {
      return existing.response as T;
    }
    const world = await worldOrThrow(tx);
    const response = await fn(tx, world);
    await tx.insert(idempotencyKeys).values({ playerId, key, endpoint, response, createdAt: now });
    return response;
  });
}

async function addCultivation(tx: Tx, playerId: string, amount: number) {
  await tx
    .update(playerStates)
    .set({ cultivation: sql`${playerStates.cultivation} + ${amount}` })
    .where(eq(playerStates.playerId, playerId));
}

export async function initializeProgress(tx: Tx, playerId: string, now: Date) {
  const world = await loadCurrentWorld(tx);
  if (!world) {
    return;
  }
  const first = orderedStages(world)[0];
  if (first) {
    await tx.insert(playerStageProgress).values({ playerId, stageSlug: first.slug, unlockedAt: now }).onConflictDoNothing();
  }
  for (const starter of world.globals.starterItems ?? []) {
    await grantItem(tx, world, playerId, starter.itemSlug, starter.quantity, "starter", now, { autoDecompose: false, capacity: Number.MAX_SAFE_INTEGER, overflow: true });
  }
}

/**
 * GET /me（旧接口，保留）：走和 /me/state 一样的结算（整数万分比 + 余数携带 + 离线上限），只是返回旧的字段形状 + 公告弹窗。
 * 返回 null 表示当前没有新内容（还没有境界），调用方退回旧的发布内容路径。
 */
export async function openProgressWorld(db: Db, playerId: string, now: Date, versionCode: number) {
  const world = await loadCurrentWorld(db);
  if (!world) {
    return null;
  }
  return withTransaction(db, async (tx) => {
    const settled = await settleLocked(tx, playerId, world, now);
    const realm = realmOf(world, settled.state.realmSlug);
    const next = realm.nextRealmSlug ? world.realms.find((row) => row.slug === realm.nextRealmSlug) : undefined;
    const offlineCapSeconds = readGameRules(world).offlineCapSeconds;
    return {
      realmSlug: settled.state.realmSlug,
      realmName: realm.displayName ?? settled.state.realmSlug,
      cultivation: settled.state.cultivation,
      gained: settled.settled.gained,
      gainPerSecond: realm.tickSeconds > 0 ? (realm.gainPerTick * (10000 + Math.round(settled.stats.bonusBp))) / 10000 / realm.tickSeconds : 0,
      offlineCapSeconds,
      breakthroughCost: realm.breakthroughCost,
      nextRealmName: next?.displayName ?? "",
      canBreakthrough: next !== undefined && settled.state.cultivation >= realm.breakthroughCost,
      power: settled.stats.power,
      notices: await noticesForPlayer(tx, playerId, versionCode),
    };
  });
}

export async function ackOfflineReport(db: Db, playerId: string, reportId: string, now: Date) {
  return withTransaction(db, async (tx) => acknowledgeOfflineReport(tx, playerId, reportId, now));
}

export async function readState(db: Db, playerId: string, now: Date) {
  const world = await worldOrThrow(db);
  return withTransaction(db, async (tx) => ({
    ...stateDto(world, playerId, await settleLocked(tx, playerId, world, now)),
    notices: await announcementNoticesForPlayer(tx, playerId),
  }));
}

/** 选择在哪个关卡刷普通怪；null = 回到默认（境界够得着的最高关卡）。切换后当前波次重新开始。 */
export async function setIdleStage(tx: Tx, world: World, playerId: string, stageSlug: string | null, now: Date) {
  const settled = await settleLocked(tx, playerId, world, now);
  if (stageSlug !== null) {
    const allowed = farmableStages(world, settled.access);
    if (!allowed.some((stage) => stage.slug === stageSlug)) {
      throw new AppError("INVALID_INPUT", "这个关卡现在不能刷怪（还没解锁、境界不够，或者没有配置怪物）");
    }
  }
  if (stageSlug !== settled.state.idleStageSlug) {
    await tx.update(playerStates).set({ idleStageSlug: stageSlug, waveProgress: 0, waveDeathsInRow: 0 }).where(eq(playerStates.playerId, playerId));
  }
  return stateDto(world, playerId, await settleLocked(tx, playerId, world, now));
}

export async function advanceRealm(tx: Tx, world: World, playerId: string, now: Date, randomInt: RandomInt) {
  const settled = await settleLocked(tx, playerId, world, now);
  const realm = realmOf(world, settled.state.realmSlug);
  if (!realm.nextRealmSlug) {
    throw new AppError("REALM_MAX");
  }
  if (realm.requiredStageSlug) {
    const cleared = settled.pieces.stages.find((row) => row.stageSlug === realm.requiredStageSlug && row.firstClearedAt);
    if (!cleared) {
      throw new AppError("STAGE_REQUIRED");
    }
  }
  if (settled.state.cultivation < realm.breakthroughCost) {
    throw new AppError("NOT_ENOUGH_CULTIVATION");
  }
  const rateBp = 10000;
  const roll = 0;
  const result = resolveBreakthrough({
    cultivation: settled.state.cultivation,
    cost: realm.breakthroughCost,
    rateBp,
    failLossBp: 0,
    failStreak: settled.state.breakthroughFailStreak,
    roll,
  });
  await tx
    .update(playerStates)
    .set({
      cultivation: result.cultivation,
      realmSlug: result.success ? realm.nextRealmSlug : settled.state.realmSlug,
      breakthroughFailStreak: result.failStreak,
      // 突破成功：挂机关卡自动切到新境界对应的关卡（默认选择），当前波次重新开始。
      ...(result.success ? { idleStageSlug: null, waveProgress: 0, waveDeathsInRow: 0 } : {}),
    })
    .where(eq(playerStates.playerId, playerId));
  const after = await settleLocked(tx, playerId, world, now);
  return {
    result: { success: result.success, rateBp, roll, lostCultivation: result.lostCultivation },
    state: stateDto(world, playerId, after),
  };
}

/** 当前境界的大招配置（倍率 0 = 没有大招）。 */
export function ultOf(world: World, realmSlug: string): (UltConfig & { name: string }) | null {
  const realm = realmOf(world, realmSlug);
  if (!realm.ultDamageMultBp || realm.ultDamageMultBp <= 0) {
    return null;
  }
  return {
    name: realm.ultName ?? "",
    multBp: realm.ultDamageMultBp,
    cooldownSeconds: realm.ultCooldownSeconds ?? 0,
    firstCooldownSeconds: realm.ultFirstCooldownSeconds ?? 8,
    autoCastWindowSeconds: readGameRules(world).ultAutoCastWindowSeconds,
  };
}

/** 第四批：大招全自动释放（冷却好后过「自动释放等待」秒放出），不再接收客户端上报的点击时间；老客户端传的 ultTaps / ultWaits 忽略。 */
export type ChallengeOptions = Record<string, never>;

export async function challengeStage(tx: Tx, world: World, playerId: string, stageSlug: string, now: Date, randomInt: RandomInt, _options: ChallengeOptions = {}) {
  // 手动挑战前的结算不触发自动挑战（否则点「挑战」时可能先被自动打掉，这一场变成重打）
  const settled = await settleLocked(tx, playerId, world, now, { autoChallenge: false });
  const stage = world.stages.find((row) => row.slug === stageSlug);
  if (!stage) {
    throw new AppError("NOT_FOUND");
  }
  const realm = realmOf(world, settled.state.realmSlug);
  if (realm.sortOrder == null || stage.requiredRealmOrder == null) {
    throw new AppError("INVALID_INPUT", "关卡没有所属境界");
  }
  const access = settled.access.find((row) => row.slug === stageSlug);
  if (!access || !access.unlocked) {
    throw new AppError("STAGE_LOCKED", access?.needs.bossWin && !access.needs.bossWin.met ? `先击败「${access.needs.bossWin.bossName}」` : undefined);
  }
  if (!access.realmOk) {
    throw new AppError("REALM_TOO_LOW");
  }
  const rules = readGameRules(world);
  const cooldown = rules.challengeCooldownSeconds;
  if (cooldown > 0 && settled.state.lastChallengeAt && now.getTime() - settled.state.lastChallengeAt.getTime() < cooldown * 1000) {
    throw new AppError("CHALLENGE_COOLDOWN", `挑战冷却中，要间隔 ${cooldown} 秒`);
  }
  const fought = await fightStageBoss(tx, world, playerId, settled, stage, now, randomInt, { mode: "manual" });
  const after = await settleLocked(tx, playerId, world, now);
  return { ...fought, state: stateDto(world, playerId, after) };
}

type FightInput = Pick<Awaited<ReturnType<typeof settleLocked>>, "state" | "stats" | "pieces">;

/**
 * 打一场首领（手动挑战、自动挑战、挂机刷首领共用）：模拟战斗（大招自动释放）、发奖励、记进度、解锁下一关。调用方已经检查过能不能打。
 * 首领规则「允许重打」关掉时，已击败的首领不能手动再打（挂机刷首领只看「挂机刷首领」开关）。
 * mode = idle（挂机刷出来的）：不占挑战冷却，奖励按「挂机首领算每日次数」开关决定消不消耗每日次数。
 */
async function fightStageBoss(tx: Tx, world: World, playerId: string, settled: FightInput, stage: World["stages"][number], now: Date, randomInt: RandomInt, fight: { mode: "manual" | "idle" }) {
  const stageSlug = stage.slug;
  const rules = readGameRules(world);
  let progress = settled.pieces.stages.find((row) => row.stageSlug === stageSlug);
  if (!progress) {
    await tx.insert(playerStageProgress).values({ playerId, stageSlug, unlockedAt: now }).onConflictDoNothing();
    progress = {
      playerId,
      stageSlug,
      unlockedAt: now,
      firstClearedAt: null,
      clearCount: 0,
      bestClearSeconds: null,
      dailyRewardCount: 0,
      dailyRewardDay: null,
      autoChallengeAt: null,
      idleWaves: 0,
    };
  }
  // 行囊满不再拒绝挑战：装备掉落满包时不掉落（客户端提示），首通固定奖励允许超出容量。
  const bagCapacity = rules.bagCapacity + settled.state.bagBonus;
  if (stage.bosses && stage.bosses.length === 0) {
    throw new AppError("INVALID_INPUT", "这个关卡还没有首领");
  }
  const boss = stage.bosses?.[0];
  if (boss?.statsProblem) {
    throw new AppError("INVALID_INPUT", boss.statsProblem);
  }
  const bossRules = bossRulesFor(world, stage);
  if (fight.mode === "manual" && progress.firstClearedAt && !bossRules.allowRepeat) {
    throw new AppError("BOSS_REPEAT_DISABLED");
  }
  const bossAttack = boss ? boss.attack : (stage.bossAttack ?? 1);
  const bossDefense = boss ? boss.defense : (stage.bossDefense ?? 0);
  const bossHp = boss ? boss.hp : stage.bossHp;
  const bossInterval = boss ? boss.interval : stage.bossInterval;
  if (bossHp <= 0 || bossInterval <= 0) {
    throw new AppError("INVALID_INPUT", "这个首领还没填气血或出手间隔");
  }
  const fighter = { attack: settled.stats.attack, defense: settled.stats.defense, hp: settled.stats.hp, interval: settled.stats.interval };
  const monsterSide = { attack: bossAttack, defense: bossDefense, hp: bossHp, interval: bossInterval };
  const ult = ultOf(world, settled.state.realmSlug);
  const battle = simulateBossFight(fighter, monsterSide, battleConfigOf(world), ult, []);
  const drops: { itemSlug: string; quantity: number; decomposed?: boolean; enhanceExp?: number; dropped?: boolean; freed?: { itemSlug: string; enhanceExp: number }[] }[] = [];
  let nextPity: Record<string, number> | undefined;
  let bagFullNotice = false;
  let rewardInfo: Awaited<ReturnType<typeof grantBossRewards>> | null = null;
  if (battle.win && boss && usesRewardModel(boss)) {
    rewardInfo = await grantBossRewards(tx, world, playerId, {
      stage,
      boss,
      progress,
      rules,
      bossRules,
      dailyTotal: globalBossRules(world).dailyChallengeTotal,
      mode: fight.mode,
      autoDecompose: settled.state.autoDecompose,
      capacity: bagCapacity,
      now,
      randomInt,
    });
    drops.push(...rewardInfo.drops);
    bagFullNotice = rewardInfo.bagFull;
  } else if (battle.win) {
    const reward = boss?.reward;
    if (reward) {
      const rolled = rollSchemeReward({
        major: reward.major,
        nextMajor: reward.nextMajor,
        stageIndex: reward.stageIndex,
        firstClear: !progress.firstClearedAt,
        pity: settled.state.dropPity,
        randomInt,
      });
      nextPity = rolled.pity;
      for (const row of rolled.grants) {
        drops.push({ itemSlug: row.slug, quantity: 1 });
      }
      // 方案首领的装备/功法书仍按方案掉落；后台掉落表里配置的材料（例如突破石）也一并掷骰。
      const rewardTable = world.dropTables.find((row) => row.slug === stage.bossDropTableSlug);
      drops.push(...rollDropTable(rewardTable?.entries ?? [], randomInt));
    } else {
      drops.push(
        ...rollDropTable(
          (boss?.drops ?? []).map((drop) => ({ itemSlug: drop.itemSlug, chanceBp: drop.chanceBp, minQty: 1, maxQty: 1 })),
          randomInt,
        ),
      );
      const bossTable = world.dropTables.find((row) => row.slug === stage.bossDropTableSlug);
      drops.push(...rollDropTable(bossTable?.entries ?? [], randomInt));
      if (!progress.firstClearedAt) {
        const firstTable = world.dropTables.find((row) => row.slug === stage.firstClearDropTableSlug);
        drops.push(...rollDropTable(firstTable?.entries ?? [], randomInt));
      }
    }
    for (const drop of drops) {
      const skill = world.skills.find((row) => row.slug === drop.itemSlug);
      if (skill) {
        const bookSlug = await ensureSkillBook(tx, { slug: skill.slug, displayName: skill.displayName ?? "名称缺失" }, null);
        await tx.insert(playerItems).values({
          playerId,
          itemSlug: bookSlug,
          isStack: false,
          quantity: 1,
          source: `drop:${stage.slug}`,
          acquiredAt: now,
        });
        drop.itemSlug = bookSlug;
        continue;
      }
      if (!world.items.some((item) => item.slug === drop.itemSlug)) {
        throw new AppError("INVALID_INPUT", "有一件掉落已经不在后台");
      }
      const granted = await grantItem(tx, world, playerId, drop.itemSlug, drop.quantity, `drop:${stage.slug}`, now, {
        autoDecompose: settled.state.autoDecompose,
        capacity: bagCapacity,
        // 首领首通奖励允许暂时超出行囊容量（设计表 2.6）。
        overflow: !progress.firstClearedAt,
      });
      if (granted.decomposed > 0) {
        drop.decomposed = true;
        drop.enhanceExp = granted.enhanceExp;
      }
      if (granted.freed.length > 0) {
        drop.freed = granted.freed;
        drop.enhanceExp = (drop.enhanceExp ?? 0) + granted.freed.reduce((sum, row) => sum + row.enhanceExp, 0);
      }
      if (granted.dropped > 0) {
        drop.dropped = true;
        bagFullNotice = true;
      }
    }
  }
  if (battle.win) {
    await tx
      .update(playerStageProgress)
      .set({
        firstClearedAt: progress.firstClearedAt ?? now,
        clearCount: progress.clearCount + 1,
        bestClearSeconds:
          progress.bestClearSeconds == null ? battle.durationSeconds : Math.min(progress.bestClearSeconds, battle.durationSeconds),
      })
      .where(and(eq(playerStageProgress.playerId, playerId), eq(playerStageProgress.stageSlug, stageSlug)));
    // 记一笔下一关已解锁（境界条件仍然在 stageAccessList 里另算）；规则不要求击败首领时下一关本来就开着，这里写不写都一样。
    const next = nextStageOf(world, stageSlug);
    if (next) {
      await tx.insert(playerStageProgress).values({ playerId, stageSlug: next.slug, unlockedAt: now }).onConflictDoNothing();
    }
  }
  if (fight.mode === "manual" || nextPity) {
    await tx
      .update(playerStates)
      .set({ ...(fight.mode === "manual" ? { lastChallengeAt: now } : {}), ...(nextPity ? { dropPity: nextPity } : {}) })
      .where(eq(playerStates.playerId, playerId));
  }
  return {
    battle,
    drops,
    bagFull: bagFullNotice,
    reward: rewardInfo
      ? {
          firstClear: rewardInfo.firstClear,
          cultivation: rewardInfo.cultivation,
          spiritStones: rewardInfo.spiritStones,
          rewarded: rewardInfo.rewarded,
          countedDaily: rewardInfo.countedDaily,
          dailyRewardCount: rewardInfo.dailyRewardCount,
          dailyRewardLimit: rewardInfo.dailyRewardLimit,
        }
      : null,
  };
}

export type AutoChallengeResult = {
  stageSlug: string;
  bossName: string;
  /** 只管画面（见 boss-rules.ts BossTier）。 */
  tier: "elite" | "chief";
  win: boolean;
  durationSeconds: number;
  drops: Awaited<ReturnType<typeof fightStageBoss>>["drops"];
  reward: Awaited<ReturnType<typeof fightStageBoss>>["reward"];
};

/**
 * 结算里的自动挑战（Chengpeng 定：在服务端结算里触发）。条件全部满足才打，一次结算最多打一场：
 * 挂机关卡能进、首领规则允许自动挑战、本关首领还没首通、战力 ≥ 推荐战力 × 自动挑战比例、
 * 挑战冷却已过、上一次自动挑战失败已过「重试间隔」。大招自动释放。首通不算每日首领挑战次数。
 * 推荐战力算不出来（配置有问题）就不自动打，手动挑战会把错误报出来。
 */
async function tryAutoChallenge(
  tx: Tx,
  world: World,
  playerId: string,
  settled: FightInput & { access: StageAccess[] },
  stage: World["stages"][number],
  now: Date,
): Promise<AutoChallengeResult | null> {
  const boss = stage.bosses?.[0];
  if (!boss || boss.statsProblem) {
    return null;
  }
  const access = settled.access.find((row) => row.slug === stage.slug);
  if (!access?.playable || access.cleared) {
    return null;
  }
  const bossRules = bossRulesFor(world, stage);
  if (!bossRules.autoChallenge) {
    return null;
  }
  let recommended: number;
  try {
    recommended = stageRecommendedPower(world, stage);
  } catch (cause) {
    if (cause instanceof AppError) {
      return null;
    }
    throw cause;
  }
  if (settled.stats.power < (recommended * bossRules.autoChallengePowerPct) / 100) {
    return null;
  }
  const rules = readGameRules(world);
  const cooldown = rules.challengeCooldownSeconds;
  if (cooldown > 0 && settled.state.lastChallengeAt && now.getTime() - settled.state.lastChallengeAt.getTime() < cooldown * 1000) {
    return null;
  }
  const progress = settled.pieces.stages.find((row) => row.stageSlug === stage.slug);
  if (progress?.autoChallengeAt && now.getTime() - progress.autoChallengeAt.getTime() < bossRules.autoChallengeRetrySeconds * 1000) {
    return null;
  }
  const fought = await fightStageBoss(tx, world, playerId, settled, stage, now, waveRandomInt, { mode: "manual" });
  if (!fought.battle.win) {
    await tx
      .update(playerStageProgress)
      .set({ autoChallengeAt: now })
      .where(and(eq(playerStageProgress.playerId, playerId), eq(playerStageProgress.stageSlug, stage.slug)));
  }
  return {
    stageSlug: stage.slug,
    bossName: boss.name,
    tier: stageTier(world, stage),
    win: fought.battle.win,
    durationSeconds: fought.battle.durationSeconds,
    drops: fought.drops,
    reward: fought.reward,
  };
}

export type IdleBossResult = {
  stageSlug: string;
  bossName: string;
  /** 只管画面（见 boss-rules.ts BossTier）。 */
  tier: "elite" | "chief";
  /** 这次结算算进来的波数、刷出几只首领、打赢 / 输了几只；超过「一次结算最多刷几只」没打的几只。 */
  waves: number;
  spawns: number;
  wins: number;
  losses: number;
  skipped: number;
  /** 有奖励的几只（重复奖励关着、或开关算次数且次数用完时没有奖励）、消耗了几次每日次数。 */
  rewarded: number;
  countedDaily: number;
  /** 本关计数（余下的波数）/ 每多少波刷一次。 */
  idleWaves: number;
  every: number;
  durationSeconds: number;
  drops: Awaited<ReturnType<typeof fightStageBoss>>["drops"];
  /** 行囊满，有装备没发（grantEquipment 返回 skipped: bag_full）——客户端显示「行囊已满」；没发的那几件在 drops 里 dropped: true。 */
  bagFull: boolean;
};

/**
 * 第四批 · 挂机刷首领（在线、离线共用，在结算里调用）：本关首领已击败、规则「挂机刷首领」开着时，
 * 把这次的 waves 波加到本关计数，每满 idleSpawnWaves 波刷出一只首领直接打（大招自动释放，不占挑战冷却），余数留到下次。
 * 一次结算最多打 idleSpawnMaxPerSettle 只（全局），多出来的不补（计数只留余数）。
 * 战斗是确定性的（同样的属性结果一样）：第一只输了，这次刷出来的都算输，不再重复模拟。
 * 奖励走首领重复奖励（装备来源 boss_repeat，requestId = 战斗报告 id，每赢一只 clear_count +1，所以每只单号不同、重放不重复发）。
 * 本关关掉「挂机刷首领」时不累计波数。
 */
async function settleIdleBosses(
  tx: Tx,
  world: World,
  playerId: string,
  settled: FightInput & { access: StageAccess[] },
  stage: World["stages"][number],
  waves: number,
  now: Date,
): Promise<IdleBossResult | null> {
  const boss = stage.bosses?.[0];
  if (!boss || boss.statsProblem || waves <= 0) {
    return null;
  }
  const access = settled.access.find((row) => row.slug === stage.slug);
  const progress = settled.pieces.stages.find((row) => row.stageSlug === stage.slug);
  if (!access?.playable || !access.cleared || !progress) {
    return null;
  }
  const bossRules = bossRulesFor(world, stage);
  if (!bossRules.idleSpawn) {
    return null;
  }
  const every = Math.max(1, bossRules.idleSpawnWaves);
  const total = progress.idleWaves + waves;
  const due = Math.floor(total / every);
  const remainder = total - due * every;
  const spawns = Math.min(due, globalBossRules(world).idleSpawnMaxPerSettle);
  await tx
    .update(playerStageProgress)
    .set({ idleWaves: remainder })
    .where(and(eq(playerStageProgress.playerId, playerId), eq(playerStageProgress.stageSlug, stage.slug)));
  const result: IdleBossResult = {
    stageSlug: stage.slug,
    bossName: boss.name,
    tier: stageTier(world, stage),
    waves,
    spawns,
    wins: 0,
    losses: 0,
    skipped: due - spawns,
    rewarded: 0,
    countedDaily: 0,
    idleWaves: remainder,
    every,
    durationSeconds: 0,
    drops: [],
    bagFull: false,
  };
  if (spawns === 0) {
    return null;
  }
  let pieces = settled.pieces;
  for (let index = 0; index < spawns; index += 1) {
    const fought = await fightStageBoss(tx, world, playerId, { ...settled, pieces }, stage, now, waveRandomInt, { mode: "idle" });
    result.durationSeconds = fought.battle.durationSeconds;
    if (!fought.battle.win) {
      result.losses = spawns - index;
      break;
    }
    result.wins += 1;
    result.drops.push(...fought.drops);
    if (fought.bagFull) result.bagFull = true;
    if (fought.reward?.rewarded) result.rewarded += 1;
    if (fought.reward?.countedDaily) result.countedDaily += 1;
    pieces = await loadPieces(tx, playerId);
  }
  return result;
}

export async function equipItem(tx: Tx, world: World, playerId: string, itemId: string, now: Date) {
  const settled = await settleLocked(tx, playerId, world, now);
  const item = settled.pieces.items.find((row) => row.id === itemId);
  if (!item) {
    throw new AppError("NOT_FOUND");
  }
  const definition = world.items.find((row) => row.slug === item.itemSlug);
  if (!definition || definition.kind !== "equipment") {
    throw new AppError("NOT_EQUIPMENT", "这不是武器，不能穿");
  }
  if (!definition.slot) {
    throw new AppError("INVALID_INPUT", "这件装备还没有部位");
  }
  const realm = realmOf(world, settled.state.realmSlug);
  if ((realm.sortOrder ?? 0) < (definition.requiredRealmOrder ?? 0)) {
    throw new AppError("REALM_TOO_LOW");
  }
  const sameSlot = settled.pieces.items.filter((row) => {
    if (row.id === item.id || !row.equippedSlot) {
      return false;
    }
    const worn = world.items.find((candidate) => candidate.slug === row.itemSlug);
    return worn?.slot === definition.slot || row.equippedSlot === definition.slot;
  });
  for (const worn of sameSlot) {
    await tx.update(playerItems).set({ equippedSlot: null }).where(eq(playerItems.id, worn.id));
  }
  if (item.equippedSlot !== definition.slot) {
    await tx.update(playerItems).set({ equippedSlot: definition.slot }).where(eq(playerItems.id, item.id));
  }
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after) };
}

export async function unequipItem(tx: Tx, world: World, playerId: string, itemId: string, now: Date) {
  const settled = await settleLocked(tx, playerId, world, now);
  const item = settled.pieces.items.find((row) => row.id === itemId);
  if (!item) {
    throw new AppError("NOT_FOUND");
  }
  if (!item.equippedSlot) {
    throw new AppError("INVALID_INPUT", "这件没有穿上");
  }
  await tx.update(playerItems).set({ equippedSlot: null }).where(eq(playerItems.id, item.id));
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after) };
}

export async function unequipSlot(tx: Tx, world: World, playerId: string, slot: string, now: Date) {
  await settleLocked(tx, playerId, world, now);
  await tx
    .update(playerItems)
    .set({ equippedSlot: null })
    .where(and(eq(playerItems.playerId, playerId), eq(playerItems.equippedSlot, slot)));
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after) };
}

export async function useItem(tx: Tx, world: World, playerId: string, itemId: string, now: Date) {
  const settled = await settleLocked(tx, playerId, world, now);
  const item = settled.pieces.items.find((row) => row.id === itemId);
  if (!item) {
    throw new AppError("NOT_FOUND");
  }
  const definition = world.items.find((row) => row.slug === item.itemSlug);
  if (!definition || definition.kind !== "skill_book" || !definition.skillSlug) {
    throw new AppError("NOT_SKILL_BOOK");
  }
  const skill = world.skills.find((row) => row.slug === definition.skillSlug);
  if (!skill) {
    throw new AppError("NOT_FOUND");
  }
  const existing = settled.pieces.skills.find((row) => row.skillSlug === skill.slug);
  const realm = realmOf(world, settled.state.realmSlug);
  if (existing && existing.level >= (world.globals.tuning?.skillMaxLayers ?? 7)) {
    const gained = bookOverflowCultivation(skill.rank, realm.gainPerTick, world.globals.tuning);
    await tx.delete(playerItems).where(eq(playerItems.id, item.id));
    await addCultivation(tx, playerId, gained);
    const after = await settleLocked(tx, playerId, world, now);
    return {
      state: stateDto(world, playerId, after),
      learned: { displayName: skill.displayName ?? "名称缺失", level: existing.level, convertedCultivation: gained },
    };
  }
  const level = existing ? existing.level + 1 : 1;
  if (!existing) {
    if ((realm.sortOrder ?? 0) < (skill.requiredRealmOrder ?? 0)) {
      throw new AppError("REALM_TOO_LOW");
    }
    for (const prerequisite of skill.prerequisiteSkillSlugs) {
      if (!settled.pieces.skills.some((row) => row.skillSlug === prerequisite)) {
        throw new AppError("PREREQUISITE_MISSING");
      }
    }
  }
  await tx.delete(playerItems).where(eq(playerItems.id, item.id));
  if (existing) {
    await tx
      .update(playerSkills)
      .set({ level })
      .where(and(eq(playerSkills.playerId, playerId), eq(playerSkills.skillSlug, skill.slug)));
  } else {
    await tx.insert(playerSkills).values({ playerId, skillSlug: skill.slug, learnedAt: now, level: 1 });
  }
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after), learned: { displayName: skill.displayName ?? "名称缺失", level } };
}

export async function decomposeItem(tx: Tx, world: World, playerId: string, itemId: string, now: Date) {
  const settled = await settleLocked(tx, playerId, world, now);
  const item = settled.pieces.items.find((row) => row.id === itemId);
  if (!item) {
    throw new AppError("NOT_FOUND");
  }
  if (item.equippedSlot) {
    throw new AppError("EQUIPPED_CANNOT_DECOMPOSE", `已穿戴的装备不能分解，请先脱下「${world.items.find((row) => row.slug === item.itemSlug)?.displayName ?? "这件装备"}」`);
  }
  const definition = world.items.find((row) => row.slug === item.itemSlug);
  if (!definition || definition.kind !== "equipment" || !definition.slot) {
    throw new AppError("NOT_EQUIPMENT", "这不是装备，不能分解");
  }
  const gained = decomposeEnhanceExp(readEnhanceRules(world), definition.quality, item.enhanceLevel) * item.quantity;
  await tx.delete(playerItems).where(eq(playerItems.id, item.id));
  await addEnhanceExp(tx, playerId, gained);
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after), gainedEnhanceExp: gained };
}

function materialLabel(world: World, itemSlug: string): string {
  return world.items.find((row) => row.slug === itemSlug)?.displayName ?? itemSlug;
}

function breakRequirementText(world: World, node: { level: number; materials: { itemSlug: string; count: number }[] }): string {
  return node.materials.map((row) => `${materialLabel(world, row.itemSlug)}×${row.count}`).join("、");
}

/**
 * 用强化经验给一件装备升级；一次升一级，toMax 为真时尽量升到上限、经验用完或遇到突破节点为止。
 * 强化不会失败。装备强化到突破节点后必须先突破（breakthroughItem）才能继续。
 */
export async function enhanceItem(tx: Tx, world: World, playerId: string, itemId: string, now: Date, options?: { toMax?: boolean }) {
  const settled = await settleLocked(tx, playerId, world, now);
  const item = settled.pieces.items.find((row) => row.id === itemId);
  if (!item) {
    throw new AppError("NOT_FOUND");
  }
  const definition = world.items.find((row) => row.slug === item.itemSlug);
  if (!definition || definition.kind !== "equipment" || !definition.slot) {
    throw new AppError("NOT_EQUIPMENT", "这不是装备，不能强化");
  }
  const rules = readEnhanceRules(world);
  const cap = enhanceCap(rules, definition.quality);
  if (item.enhanceLevel >= cap) {
    throw new AppError("INVALID_INPUT", `已强化到上限 +${cap}`);
  }
  let level = item.enhanceLevel;
  let pool = settled.state.enhanceExp;
  let spent = 0;
  let blockedBy: { level: number; materials: { itemSlug: string; count: number }[] } | null;
  do {
    blockedBy = pendingBreakNode(rules, definition.quality, level, item.breakLevel);
    if (blockedBy) {
      break;
    }
    const cost = enhanceCost(rules, definition.quality, level);
    if (pool < cost) {
      break;
    }
    pool -= cost;
    spent += cost;
    level += 1;
  } while (options?.toMax && level < cap);
  if (level < cap && !blockedBy) {
    blockedBy = pendingBreakNode(rules, definition.quality, level, item.breakLevel);
  }
  if (level === item.enhanceLevel) {
    if (blockedBy) {
      throw new AppError("BREAKTHROUGH_REQUIRED", `已到突破节点 +${blockedBy.level}，需要先突破：${breakRequirementText(world, blockedBy)}`, { node: blockedBy });
    }
    throw new AppError("INVALID_INPUT", `强化经验不足，下一级需要 ${enhanceCost(rules, definition.quality, level)}`);
  }
  await tx.update(playerItems).set({ enhanceLevel: level }).where(eq(playerItems.id, item.id));
  await tx.update(playerStates).set({ enhanceExp: pool }).where(eq(playerStates.playerId, playerId));
  const after = await settleLocked(tx, playerId, world, now);
  return {
    state: stateDto(world, playerId, after),
    enhanced: { itemId: item.id, fromLevel: item.enhanceLevel, toLevel: level, spentExp: spent, blockedByBreakthrough: blockedBy ? blockedBy.level : null },
  };
}

/**
 * 突破：装备强化到突破节点（等级正好等于节点等级且没突破过）后，交齐配置里的材料（从行囊里扣）才能继续强化。
 * 不会失败；材料不够时什么都不扣，直接报错并写明差多少。
 */
export async function breakthroughItem(tx: Tx, world: World, playerId: string, itemId: string, now: Date) {
  const settled = await settleLocked(tx, playerId, world, now);
  const item = settled.pieces.items.find((row) => row.id === itemId);
  if (!item) {
    throw new AppError("NOT_FOUND");
  }
  const definition = world.items.find((row) => row.slug === item.itemSlug);
  if (!definition || definition.kind !== "equipment" || !definition.slot) {
    throw new AppError("NOT_EQUIPMENT", "这不是装备，不能突破");
  }
  const rules = readEnhanceRules(world);
  qualityRule(rules, definition.quality);
  const node = pendingBreakNode(rules, definition.quality, item.enhanceLevel, item.breakLevel);
  if (!node) {
    throw new AppError("INVALID_INPUT", "这件装备现在不在突破节点上，不需要突破");
  }
  const stacks = settled.pieces.items.filter((row) => row.isStack);
  const shortages: { itemSlug: string; need: number; have: number }[] = [];
  for (const material of node.materials) {
    const have = stacks.filter((row) => row.itemSlug === material.itemSlug).reduce((sum, row) => sum + row.quantity, 0);
    if (have < material.count) {
      shortages.push({ itemSlug: material.itemSlug, need: material.count, have });
    }
  }
  if (shortages.length > 0) {
    const text = shortages.map((row) => `${materialLabel(world, row.itemSlug)} 还差 ${row.need - row.have}（需要 ${row.need}，有 ${row.have}）`).join("；");
    throw new AppError("BREAKTHROUGH_MATERIAL_SHORT", `突破材料不足：${text}`, { shortages });
  }
  for (const material of node.materials) {
    let left = material.count;
    for (const row of stacks.filter((stack) => stack.itemSlug === material.itemSlug)) {
      if (left <= 0) {
        break;
      }
      const take = Math.min(left, row.quantity);
      left -= take;
      if (row.quantity - take <= 0) {
        await tx.delete(playerItems).where(eq(playerItems.id, row.id));
      } else {
        await tx.update(playerItems).set({ quantity: row.quantity - take }).where(eq(playerItems.id, row.id));
      }
    }
  }
  await tx.update(playerItems).set({ breakLevel: node.level }).where(eq(playerItems.id, item.id));
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after), broken: { itemId: item.id, level: node.level, materials: node.materials } };
}

export async function setAutoDecompose(tx: Tx, world: World, playerId: string, enabled: boolean, now: Date) {
  await settleLocked(tx, playerId, world, now);
  await tx.update(playerStates).set({ autoDecompose: enabled }).where(eq(playerStates.playerId, playerId));
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after) };
}

export async function runSkill(tx: Tx, world: World, playerId: string, skillSlug: string, _slot: string, now: Date) {
  const settled = await settleLocked(tx, playerId, world, now);
  const learned = settled.pieces.skills.find((row) => row.skillSlug === skillSlug);
  if (!learned) {
    throw new AppError("SKILL_NOT_LEARNED");
  }
  const skill = world.skills.find((row) => row.slug === skillSlug);
  if (!skill) {
    throw new AppError("INVALID_INPUT", "这门功法已经不存在");
  }
  const open = openSkillSlotsFor(world, settled.state.realmSlug);
  const slots = Array.from({ length: open }, (_, index) => `run_${index + 1}`);
  const others = settled.pieces.skills.filter((row) => row.runningSlot && slots.includes(row.runningSlot) && row.skillSlug !== skillSlug);
  const used = new Set(others.map((row) => row.runningSlot));
  const free = learned.runningSlot && slots.includes(learned.runningSlot) ? learned.runningSlot : slots.find((slot) => !used.has(slot));
  if (!free) {
    const next = nextSkillSlotRule(world.globals.artSlotRules, realmOf(world, settled.state.realmSlug).sortOrder ?? 0);
    const nextName = next ? world.realms.find((row) => row.sortOrder === next.minRealmOrder)?.displayName : null;
    throw new AppError("SKILL_SLOT_INVALID", open === 0 ? "当前境界还没有开放功法栏位" : `最多同时运转 ${open} 门功法${nextName ? `（${nextName}开放第 ${next!.slots} 个栏位）` : ""}`);
  }
  await tx
    .update(playerSkills)
    .set({ runningSlot: free })
    .where(and(eq(playerSkills.playerId, playerId), eq(playerSkills.skillSlug, skillSlug)));
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after) };
}

export async function stopSkill(tx: Tx, world: World, playerId: string, skillSlug: string, now: Date) {
  const settled = await settleLocked(tx, playerId, world, now);
  if (!settled.pieces.skills.some((row) => row.skillSlug === skillSlug)) {
    throw new AppError("SKILL_NOT_LEARNED");
  }
  await tx
    .update(playerSkills)
    .set({ runningSlot: null })
    .where(and(eq(playerSkills.playerId, playerId), eq(playerSkills.skillSlug, skillSlug)));
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after) };
}
