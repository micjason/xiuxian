/**
 * 后台进度模拟（最勤奋玩家）：读 live ContentSnapshot，事件跳进游戏日，
 * 战斗判定复用 simulateBossFight + combatStats（与线上挑战同一套）。
 */
import { simulateBossFight, toCombatSkills, type CombatSkill } from "../combat/battle.js";
import { qualityRow, slotName } from "../content/catalog.js";
import { enhanceCap, enhancedStat, essenceCost, readEnhanceRules } from "../content/enhance.js";
import { readGameRules } from "../content/rules.js";
import { stageAccessList, type StageAccess } from "../content/stage-order.js";
import { stageRecommendedPower } from "../content/stage-power.js";
import type { ContentSnapshot } from "../content/validate.js";
import { battleConfigOf, combatStats, openSkillSlotsFor } from "../loop/actions.js";
import { settleTicks } from "../progress/settle.js";
import { AppError } from "../../shared/errors.js";

export const ONLINE_HOURS = 16;
export const IDLE_HOURS = 8;
export const STUCK_FAIL_DAYS = 10;
export const DEFAULT_WALL_BUDGET_MS = 8_000;

export type OverviewRow = {
  day: number;
  realmId: string;
  realmName: string;
  stageLabel: string;
  power: number;
  gearTier: string;
  skillTier: string;
  status: "ok" | "stuck";
};

export type StuckInfo = {
  bossId: string;
  bossName: string;
  day: number;
  playerPower: number;
  requiredPower: number;
  powerGap: number;
  redLights: Array<"power" | "gear" | "skill" | "stage">;
  hint: string;
};

export type TimelineKind =
  | "start"
  | "boss_win"
  | "boss_lose"
  | "idle"
  | "loot"
  | "equip"
  | "enhance"
  | "breakthrough"
  | "dongfu"
  | "other";

export type TimelineEvent = {
  day: number;
  hour: number;
  text: string;
  kind: TimelineKind;
};

export type ProgressionSimResult = {
  overview: OverviewRow[];
  stuck: StuckInfo | null;
  timeline: TimelineEvent[];
  meta: { targetRealmId: string; elapsedMs: number; truncated: boolean };
};

type GearPiece = {
  id: string;
  slug: string;
  slot: string;
  quality: string;
  enhanceLevel: number;
  equipped: boolean;
  requiredRealmOrder: number;
};

type LearnedSkill = { skillSlug: string; level: number; runningSlot: string | null };

type StageProg = { stageSlug: string; firstClearedAt: Date | null };

type SimState = {
  day: number;
  hour: number;
  realmSlug: string;
  cultivation: number;
  essence: number;
  spiritStones: number;
  wood: number;
  gear: GearPiece[];
  skills: LearnedSkill[];
  stages: StageProg[];
  failDays: number;
  failBossSlug: string | null;
  nextGearId: number;
};

function realmName(world: ContentSnapshot, slug: string): string {
  return world.realms.find((row) => row.slug === slug)?.displayName ?? slug;
}

function realmOf(world: ContentSnapshot, slug: string) {
  const realm = world.realms.find((row) => row.slug === slug);
  if (!realm) {
    throw new AppError("NOT_FOUND", `境界 ${slug} 不存在`);
  }
  return realm;
}

/** 默认目标：大乘大境的第一层（majorName/displayName 含「大乘」，sortOrder 最小）。 */
export function resolveDefaultTargetRealmId(world: ContentSnapshot): string {
  const majors = world.realms
    .filter((row) => row.enabled !== false)
    .filter((row) => (row.majorName ?? "").includes("大乘") || (row.displayName ?? "").startsWith("大乘") || row.slug.startsWith("dacheng"))
    .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));
  if (majors[0]) {
    return majors[0].slug;
  }
  const last = [...world.realms].filter((row) => row.enabled !== false).sort((a, b) => (b.sortOrder ?? 0) - (a.sortOrder ?? 0))[0];
  if (!last) {
    throw new AppError("INVALID_INPUT", "当前配置没有可用境界");
  }
  return last.slug;
}

function reachedTarget(world: ContentSnapshot, currentSlug: string, targetSlug: string): boolean {
  const current = realmOf(world, currentSlug);
  const target = realmOf(world, targetSlug);
  return (current.sortOrder ?? 0) >= (target.sortOrder ?? 0);
}

function equippedEntries(state: SimState): { slug: string; enhanceLevel: number }[] {
  return state.gear.filter((g) => g.equipped).map((g) => ({ slug: g.slug, enhanceLevel: g.enhanceLevel }));
}

function runningSkills(state: SimState): { slug: string; level: number }[] {
  return state.skills.filter((s) => s.runningSlot).map((s) => ({ slug: s.skillSlug, level: s.level }));
}

function playerStats(world: ContentSnapshot, state: SimState) {
  return combatStats(world, state.realmSlug, equippedEntries(state), runningSkills(state));
}

/** 品质 key → 白/绿/蓝/紫/橙；未知 key 原样回退。 */
function qualityShortZh(quality: string): string {
  return qualityRow(quality)?.short ?? quality;
}

/** 装备档：白/蓝装 · 强化+2（多品质按品质表顺序）。 */
function gearTierLabel(state: Pick<SimState, "gear">): string {
  const worn = state.gear.filter((g) => g.equipped);
  if (worn.length === 0) return "无装";
  const avg = Math.floor(worn.reduce((sum, g) => sum + g.enhanceLevel, 0) / worn.length);
  const qualities = [...new Set(worn.map((g) => g.quality))]
    .map((q) => ({ key: q, short: qualityShortZh(q), order: qualityRow(q)?.sortOrder ?? 99 }))
    .sort((a, b) => a.order - b.order || a.short.localeCompare(b.short, "zh"));
  const qualityPart = `${qualities.map((q) => q.short).join("/")}装`;
  return `${qualityPart} · 强化+${avg}`;
}

/** 技能档：紫府金章 Lv1、青元诀 Lv1（displayName，不用 slug）。 */
function skillTierLabel(world: ContentSnapshot, state: Pick<SimState, "skills">): string {
  const run = state.skills.filter((s) => s.runningSlot);
  if (run.length === 0) return "无技能";
  return run
    .map((s) => {
      const name = world.skills.find((d) => d.slug === s.skillSlug)?.displayName ?? s.skillSlug;
      return `${name} Lv${s.level}`;
    })
    .join("、");
}

function stageLabelOf(world: ContentSnapshot, state: SimState): string {
  const next = nextChallengeStage(world, state);
  if (next) {
    const boss = next.bosses?.[0]?.name ?? next.bossName ?? next.displayName ?? next.slug;
    let rec = 0;
    try {
      rec = stageRecommendedPower(world, next);
    } catch {
      /* keep 0 */
    }
    const power = playerStats(world, state).power;
    let recPart = "";
    if (rec > 0) {
      // 总览是「日末面对的下一关」，不是过关瞬间；战力明显低于推荐时标明，避免误读成已通关
      recPart = power < rec ? ` · 推荐战力 ${rec}（当前战力不足）` : ` · 推荐战力 ${rec}`;
    }
    return `${next.displayName ?? next.slug}/${boss}${recPart}`;
  }
  const cleared = state.stages.filter((s) => s.firstClearedAt).length;
  return cleared > 0 ? `已通 ${cleared} 关` : "开局";
}

function pushOverview(overview: OverviewRow[], world: ContentSnapshot, state: SimState, status: "ok" | "stuck") {
  const stats = playerStats(world, state);
  overview.push({
    day: state.day,
    realmId: state.realmSlug,
    realmName: realmName(world, state.realmSlug),
    stageLabel: stageLabelOf(world, state),
    power: stats.power,
    gearTier: gearTierLabel(state),
    skillTier: skillTierLabel(world, state),
    status,
  });
}

function emit(timeline: TimelineEvent[], state: SimState, kind: TimelineKind, text: string) {
  timeline.push({ day: state.day, hour: state.hour, text, kind });
}

function accessFor(world: ContentSnapshot, state: SimState): StageAccess[] {
  const realm = realmOf(world, state.realmSlug);
  return stageAccessList(world, realm.sortOrder ?? 0, state.stages);
}

function nextChallengeStage(world: ContentSnapshot, state: SimState): ContentSnapshot["stages"][number] | null {
  const access = accessFor(world, state);
  for (const row of access) {
    if (!row.playable) continue;
    if (row.cleared) continue;
    const stage = world.stages.find((s) => s.slug === row.slug);
    if (!stage?.enabled) continue;
    if (stage.bosses && stage.bosses.length === 0) continue;
    const boss = stage.bosses?.[0];
    if (boss?.statsProblem) continue;
    const hp = boss ? boss.hp : stage.bossHp;
    const interval = boss ? boss.interval : stage.bossInterval;
    if (hp <= 0 || interval <= 0) continue;
    return stage;
  }
  return null;
}

function highestFarmStage(world: ContentSnapshot, state: SimState): ContentSnapshot["stages"][number] | null {
  const access = accessFor(world, state);
  let best: ContentSnapshot["stages"][number] | null = null;
  for (const row of access) {
    if (!row.playable) continue;
    const stage = world.stages.find((s) => s.slug === row.slug);
    if (!stage?.enabled) continue;
    if (!best || (stage.sortOrder ?? 0) >= (best.sortOrder ?? 0)) {
      best = stage;
    }
  }
  return best;
}

function itemPowerScore(world: ContentSnapshot, slug: string, enhanceLevel: number): number {
  const def = world.items.find((i) => i.slug === slug);
  if (!def) return 0;
  const rules = readEnhanceRules(world);
  const attack = enhanceLevel > 0 ? enhancedStat(def.attack ?? 0, enhanceLevel, rules, def.quality) : (def.attack ?? 0);
  const defense = enhanceLevel > 0 ? enhancedStat(def.defense ?? 0, enhanceLevel, rules, def.quality) : (def.defense ?? 0);
  const hp = enhanceLevel > 0 ? enhancedStat(def.hp ?? 0, enhanceLevel, rules, def.quality) : (def.hp ?? 0);
  const speed = enhanceLevel > 0 ? enhancedStat(def.speed ?? 0, enhanceLevel, rules, def.quality) : (def.speed ?? 0);
  const weights = readGameRules(world).powerWeights;
  return attack * weights.attack + defense * weights.defense + hp * weights.hp + speed * weights.speed;
}

function autoEquip(world: ContentSnapshot, state: SimState, timeline: TimelineEvent[]) {
  const realmOrder = realmOf(world, state.realmSlug).sortOrder ?? 0;
  const bySlot = new Map<string, GearPiece[]>();
  for (const piece of state.gear) {
    const def = world.items.find((i) => i.slug === piece.slug);
    if (!def || def.kind !== "equipment" || !def.slot) continue;
    if ((def.requiredRealmOrder ?? 0) > realmOrder) continue;
    const list = bySlot.get(def.slot) ?? [];
    list.push(piece);
    bySlot.set(def.slot, list);
  }
  for (const [, pieces] of bySlot) {
    pieces.sort((a, b) => itemPowerScore(world, b.slug, b.enhanceLevel) - itemPowerScore(world, a.slug, a.enhanceLevel));
    const best = pieces[0]!;
    const wasEquipped = best.equipped;
    for (const p of pieces) {
      p.equipped = false;
    }
    best.equipped = true;
    if (!wasEquipped) {
      const gearName = world.items.find((i) => i.slug === best.slug)?.displayName ?? best.slug;
      const slotZh = slotName(best.slot) || best.slot;
      emit(timeline, state, "equip", `穿戴 ${gearName}（${slotZh} · 强化+${best.enhanceLevel}），战力 ${playerStats(world, state).power}`);
    }
  }
}

function enhanceAll(world: ContentSnapshot, state: SimState, timeline: TimelineEvent[]) {
  let rules: ReturnType<typeof readEnhanceRules>;
  try {
    rules = readEnhanceRules(world);
  } catch {
    return;
  }
  let any = false;
  for (const piece of state.gear.filter((g) => g.equipped)) {
    const def = world.items.find((i) => i.slug === piece.slug);
    if (!def) continue;
    let cap: number;
    try {
      cap = enhanceCap(rules, def.quality);
    } catch {
      continue;
    }
    while (piece.enhanceLevel < cap) {
      let cost: number;
      try {
        cost = essenceCost(rules, def.quality, piece.enhanceLevel);
      } catch {
        break;
      }
      if (state.essence < cost) break;
      state.essence -= cost;
      piece.enhanceLevel += 1;
      any = true;
    }
  }
  if (any) {
    emit(timeline, state, "enhance", `强化到当前上限，精粹余 ${state.essence}，战力 ${playerStats(world, state).power}`);
  }
}

function autoSkills(world: ContentSnapshot, state: SimState) {
  const slots = openSkillSlotsFor(world, state.realmSlug);
  const owned = state.skills.slice();
  // 学习所有已启用且境界够的技能（勤奋玩家假设全学）
  for (const skill of world.skills) {
    if (skill.enabled === false) continue;
    if ((skill.requiredRealmOrder ?? 0) > (realmOf(world, state.realmSlug).sortOrder ?? 0)) continue;
    if (!owned.some((s) => s.skillSlug === skill.slug)) {
      owned.push({ skillSlug: skill.slug, level: 1, runningSlot: null });
    }
  }
  // 按战力贡献排序，填满运转栏
  const scored = owned
    .map((s) => {
      const def = world.skills.find((d) => d.slug === s.skillSlug);
      const score = (def?.attack ?? 0) + (def?.defense ?? 0) + (def?.hp ?? 0) + (def?.cultivateBonusBp ?? 0);
      return { s, score };
    })
    .sort((a, b) => b.score - a.score || a.s.skillSlug.localeCompare(b.s.skillSlug));
  for (const row of scored) {
    row.s.runningSlot = null;
  }
  scored.slice(0, slots).forEach((row, index) => {
    row.s.runningSlot = `run_${index + 1}`;
  });
  state.skills = scored.map((row) => row.s);
}

function tryBreakthrough(world: ContentSnapshot, state: SimState, timeline: TimelineEvent[], targetSlug: string): boolean {
  if (reachedTarget(world, state.realmSlug, targetSlug)) return false;
  const realm = realmOf(world, state.realmSlug);
  if (!realm.nextRealmSlug) return false;
  if (realm.requiredStageSlug) {
    const cleared = state.stages.some((s) => s.stageSlug === realm.requiredStageSlug && s.firstClearedAt);
    if (!cleared) return false;
  }
  if (state.cultivation < (realm.breakthroughCost ?? 0)) return false;
  // 与线上 advanceRealm 一致：当前突破率固定 100%
  state.cultivation -= realm.breakthroughCost ?? 0;
  state.realmSlug = realm.nextRealmSlug;
  autoSkills(world, state);
  emit(timeline, state, "breakthrough", `突破至 ${realmName(world, state.realmSlug)}，修为余 ${state.cultivation}，战力 ${playerStats(world, state).power}`);
  return true;
}

function grantLoot(
  world: ContentSnapshot,
  state: SimState,
  stage: ContentSnapshot["stages"][number],
  timeline: TimelineEvent[],
  firstClear: boolean,
) {
  const boss = stage.bosses?.[0];
  const drops: { itemSlug: string; quantity: number }[] = [];
  if (boss?.drops) {
    for (const drop of boss.drops) {
      if (drop.chanceBp >= 5000) drops.push({ itemSlug: drop.itemSlug, quantity: 1 });
    }
  }
  if (firstClear && boss && "firstClear" in boss && Array.isArray(boss.firstClear)) {
    for (const entry of boss.firstClear as { itemSlug?: string; quantity?: number; kind?: string; amount?: number }[]) {
      if (entry.itemSlug) drops.push({ itemSlug: entry.itemSlug, quantity: entry.quantity ?? 1 });
      if (entry.kind === "cultivation" && entry.amount) state.cultivation += entry.amount;
      if (entry.kind === "spirit_stones" && entry.amount) state.spiritStones += entry.amount;
    }
  }
  // 勤奋假设：首通额外精粹；装备走首通表 + 下面 farm（不再白送橙装）
  if (firstClear) {
    state.essence += 200;
    const realmOrder = stage.requiredRealmOrder ?? 0;
    const mid = world.items.filter(
      (i) =>
        i.kind === "equipment" &&
        i.slot &&
        (i.requiredRealmOrder ?? 0) <= realmOrder &&
        (i.requiredRealmOrder ?? 0) >= Math.max(0, realmOrder - 1) &&
        (i.quality === "green" || i.quality === "blue"),
    );
    for (const item of mid.slice(0, 2)) {
      drops.push({ itemSlug: item.slug, quantity: 1 });
    }
  } else {
    state.essence += 40;
  }

  const names: string[] = [];
  for (const drop of drops) {
    const def = world.items.find((i) => i.slug === drop.itemSlug);
    if (!def) continue;
    if (def.kind === "equipment" && def.slot) {
      state.gear.push({
        id: `g${state.nextGearId++}`,
        slug: def.slug,
        slot: def.slot,
        quality: def.quality ?? "white",
        enhanceLevel: 0,
        equipped: false,
        requiredRealmOrder: def.requiredRealmOrder ?? 0,
      });
      names.push(def.displayName ?? def.slug);
    } else if (def.slug === "refine_essence" || def.displayName?.includes("精粹")) {
      state.essence += drop.quantity;
      names.push(`${def.displayName ?? def.slug}×${drop.quantity}`);
    } else if (def.kind === "material") {
      state.essence += drop.quantity * 5;
      names.push(`${def.displayName ?? def.slug}×${drop.quantity}`);
    }
  }
  if (names.length > 0) {
    emit(timeline, state, "loot", `获得 ${names.join("、")}`);
  }
  autoEquip(world, state, timeline);
  enhanceAll(world, state, timeline);
}

/** 卡 Boss 时刷装：按本关境界掉绿/蓝（章末压力下偶发紫），逼近真实挂机掉落。 */
function farmGearBeforeRetry(
  world: ContentSnapshot,
  state: SimState,
  stage: ContentSnapshot["stages"][number],
  timeline: TimelineEvent[],
  intense: boolean,
) {
  const realmOrder = stage.requiredRealmOrder ?? realmOf(world, state.realmSlug).sortOrder ?? 0;
  const pool = world.items.filter(
    (i) => i.kind === "equipment" && i.slot && (i.requiredRealmOrder ?? 0) <= realmOrder && (i.requiredRealmOrder ?? 0) >= Math.max(0, realmOrder - 1),
  );
  if (pool.length === 0) return;
  const want = intense ? 2 : 1;
  const names: string[] = [];
  const qualityPick = (n: number): string => {
    // 压力越大越高品质：卡关多日后可刷到橙，逼近真实首领掉落
    if (intense && n % 4 === 0) return "orange";
    if (intense || n % 5 === 0) return "purple";
    if (n % 3 === 0) return "blue";
    return "green";
  };
  for (let i = 0; i < want; i += 1) {
    const q = qualityPick(state.day * 10 + state.hour + i + state.nextGearId);
    const slotted = pool.filter((p) => p.quality === q);
    const pick = (slotted.length > 0 ? slotted : pool.filter((p) => p.quality === "green" || p.quality === "blue" || p.quality === "white"))[state.nextGearId % Math.max(1, slotted.length || pool.length)];
    if (!pick || !pick.slot) continue;
    state.gear.push({
      id: `g${state.nextGearId++}`,
      slug: pick.slug,
      slot: pick.slot,
      quality: pick.quality ?? "white",
      enhanceLevel: 0,
      equipped: false,
      requiredRealmOrder: pick.requiredRealmOrder ?? 0,
    });
    names.push(pick.displayName ?? pick.slug);
  }
  if (names.length > 0) {
    emit(timeline, state, "loot", `刷装获得 ${names.join("、")}`);
  }
  state.essence += intense ? 60 : 25;
  autoEquip(world, state, timeline);
  enhanceAll(world, state, timeline);
}

function fightBoss(
  world: ContentSnapshot,
  state: SimState,
  stage: ContentSnapshot["stages"][number],
  timeline: TimelineEvent[],
): boolean {
  const boss = stage.bosses?.[0];
  const fighterStats = playerStats(world, state);
  const fighter = { attack: fighterStats.attack, defense: fighterStats.defense, hp: fighterStats.hp, interval: fighterStats.interval };
  const monsterSide = {
    attack: boss ? boss.attack : (stage.bossAttack ?? 1),
    defense: boss ? boss.defense : (stage.bossDefense ?? 0),
    hp: boss ? boss.hp : stage.bossHp,
    interval: boss ? boss.interval : stage.bossInterval,
  };
  const learned = state.skills.map((s) => ({ skillSlug: s.skillSlug, level: s.level, runningSlot: s.runningSlot }));
  const skills: CombatSkill[] = toCombatSkills(learned, world.skills, openSkillSlotsFor(world, state.realmSlug));
  // 与线上一致：无手动大招（ultOf 恒 null），只带运转技能
  const battle = simulateBossFight(fighter, monsterSide, battleConfigOf(world), null, [], skills);
  const bossName = boss?.name ?? stage.bossName ?? stage.displayName ?? stage.slug;
  let recPower = 0;
  try {
    recPower = stageRecommendedPower(world, stage);
  } catch {
    /* keep 0 */
  }
  const recSuffix = recPower > 0 ? `，推荐战力 ${recPower}` : "";
  // 推荐战力语义：打赢所需战力 × 余量。完整战斗可能因技能/血厚权重等在远低于推荐时仍判胜；
  // 进度模拟按推荐门槛收束，避免「战力 4k 打过推荐 1 万」误导调参。
  if (battle.win && recPower > 0 && fighterStats.power < recPower) {
    emit(
      timeline,
      state,
      "boss_lose",
      `挑战 ${bossName} 失败（战力不足），战力 ${fighterStats.power}${recSuffix}`,
    );
    return false;
  }
  if (battle.win) {
    const first = !state.stages.some((s) => s.stageSlug === stage.slug && s.firstClearedAt);
    const existing = state.stages.find((s) => s.stageSlug === stage.slug);
    if (existing) {
      existing.firstClearedAt = existing.firstClearedAt ?? new Date(0);
    } else {
      state.stages.push({ stageSlug: stage.slug, firstClearedAt: new Date(0) });
    }
    emit(timeline, state, "boss_win", `击败 ${bossName}（${stage.displayName ?? stage.slug}），耗时 ${battle.durationSeconds.toFixed(1)}s，战力 ${fighterStats.power}${recSuffix}`);
    grantLoot(world, state, stage, timeline, first);
    state.failDays = 0;
    state.failBossSlug = null;
    return true;
  }
  emit(timeline, state, "boss_lose", `挑战 ${bossName} 失败（${battle.reason}），战力 ${fighterStats.power}${recSuffix}`);
  return false;
}

function settleOnlineCultivation(world: ContentSnapshot, state: SimState, hours: number) {
  const realm = realmOf(world, state.realmSlug);
  const stats = playerStats(world, state);
  const rules = readGameRules(world);
  const from = new Date(0);
  const to = new Date(hours * 3600 * 1000);
  const settled = settleTicks({
    cultivation: state.cultivation,
    lastSettledAt: from,
    now: to,
    tickSeconds: realm.tickSeconds,
    gainPerTick: realm.gainPerTick,
    bonusBp: stats.bonusBp,
    offlineCapSeconds: Math.max(rules.offlineCapSeconds, hours * 3600),
  });
  state.cultivation = settled.cultivation;
}

function settleIdle(world: ContentSnapshot, state: SimState, timeline: TimelineEvent[]) {
  const stage = highestFarmStage(world, state);
  settleOnlineCultivation(world, state, IDLE_HOURS);
  // 挂机材料：按关卡给精粹
  const essenceGain = stage ? 80 + (stage.sortOrder ?? 0) * 10 : 40;
  state.essence += essenceGain;
  if (stage) {
    emit(timeline, state, "idle", `挂机「${stage.displayName ?? stage.slug}」${IDLE_HOURS}h，修为 ${state.cultivation}，精粹+${essenceGain}`);
  } else {
    emit(timeline, state, "idle", `挂机修炼 ${IDLE_HOURS}h，修为 ${state.cultivation}`);
  }
  enhanceAll(world, state, timeline);
}

function settleDongfu(world: ContentSnapshot, state: SimState, timeline: TimelineEvent[]) {
  const cfg = world.globals.dongfu;
  if (!cfg) return;
  // 最优：灵仆全部分到产资源侧；本版按日定额折算灵木/灵石 → 精粹
  const servants = cfg.startingServants ?? 0;
  const wood = 10 + servants * 5;
  const stones = 20 + servants * 8;
  state.wood += wood;
  state.spiritStones += stones;
  state.essence += Math.floor(stones / 2) + Math.floor(wood / 2);
  emit(timeline, state, "dongfu", `洞府日结（灵仆${servants}最优分配）：灵木+${wood} 灵石+${stones}`);
}

function buildStuck(world: ContentSnapshot, state: SimState, stage: ContentSnapshot["stages"][number]): StuckInfo {
  const stats = playerStats(world, state);
  const required = stageRecommendedPower(world, stage);
  const boss = stage.bosses?.[0];
  const bossId = stage.slug;
  const bossName = boss?.name ?? stage.bossName ?? stage.displayName ?? stage.slug;
  const powerGap = Math.max(0, Math.round(required - stats.power));
  const redLights: StuckInfo["redLights"] = [];
  if (stats.power < required) redLights.push("power");
  const worn = state.gear.filter((g) => g.equipped);
  try {
    const rules = readEnhanceRules(world);
    for (const piece of worn) {
      const def = world.items.find((i) => i.slug === piece.slug);
      if (!def) continue;
      if (piece.enhanceLevel < enhanceCap(rules, def.quality)) {
        redLights.push("gear");
        break;
      }
    }
  } catch {
    if (worn.length === 0) redLights.push("gear");
  }
  const slots = openSkillSlotsFor(world, state.realmSlug);
  if (state.skills.filter((s) => s.runningSlot).length < slots) redLights.push("skill");
  const access = accessFor(world, state).find((a) => a.slug === stage.slug);
  if (access && !access.realmOk) redLights.push("stage");
  if (redLights.length === 0) redLights.push("power");
  const hint =
    redLights[0] === "power"
      ? "优先下调该 Boss 气血/攻防或提高本境装备/境界成长"
      : redLights[0] === "gear"
        ? "检查强化上限与精粹产出，或提高掉落装品质"
        : redLights[0] === "skill"
          ? "检查技能栏位与技能属性配置"
          : "检查关卡所需境界门槛";
  return {
    bossId,
    bossName,
    day: state.day,
    playerPower: stats.power,
    requiredPower: required,
    powerGap,
    redLights: [...new Set(redLights)],
    hint,
  };
}

function initialState(world: ContentSnapshot): SimState {
  const startSlug = world.globals.startingRealmSlug || world.realms.filter((r) => r.enabled !== false).sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))[0]?.slug;
  if (!startSlug) {
    throw new AppError("INVALID_INPUT", "当前配置没有起始境界");
  }
  const state: SimState = {
    day: 1,
    hour: 0,
    realmSlug: startSlug,
    cultivation: 0,
    essence: 0,
    spiritStones: 0,
    wood: 0,
    gear: [],
    skills: [],
    stages: [],
    failDays: 0,
    failBossSlug: null,
    nextGearId: 1,
  };
  for (const starter of world.globals.starterItems ?? []) {
    const def = world.items.find((i) => i.slug === starter.itemSlug);
    if (def?.kind === "equipment" && def.slot) {
      for (let i = 0; i < (starter.quantity ?? 1); i += 1) {
        state.gear.push({
          id: `g${state.nextGearId++}`,
          slug: def.slug,
          slot: def.slot,
          quality: def.quality ?? "white",
          enhanceLevel: 0,
          equipped: false,
          requiredRealmOrder: def.requiredRealmOrder ?? 0,
        });
      }
    } else if (def?.slug === "refine_essence") {
      state.essence += starter.quantity ?? 1;
    }
  }
  autoSkills(world, state);
  return state;
}

export function runProgressionSim(
  world: ContentSnapshot,
  options: { targetRealmId?: string; wallBudgetMs?: number } = {},
): ProgressionSimResult {
  const started = Date.now();
  const budget = options.wallBudgetMs ?? DEFAULT_WALL_BUDGET_MS;
  const targetRealmId = options.targetRealmId?.trim() || resolveDefaultTargetRealmId(world);
  if (!world.realms.some((r) => r.slug === targetRealmId)) {
    throw new AppError("INVALID_INPUT", `目标境界 ${targetRealmId} 不存在`);
  }

  const timeline: TimelineEvent[] = [];
  const overview: OverviewRow[] = [];
  const state = initialState(world);
  autoEquip(world, state, timeline);
  enhanceAll(world, state, timeline);
  emit(timeline, state, "start", `开局 ${realmName(world, state.realmSlug)}，战力 ${playerStats(world, state).power}，目标 ${realmName(world, targetRealmId)}`);
  pushOverview(overview, world, state, "ok");

  let stuck: StuckInfo | null = null;
  let truncated = false;

  // 事件跳进：按游戏日循环；日内优先打下一 Boss，再挂机/洞府
  while (!reachedTarget(world, state.realmSlug, targetRealmId)) {
    if (Date.now() - started > budget) {
      truncated = true;
      emit(timeline, state, "other", `模拟超时（>${budget}ms），返回部分结果`);
      break;
    }

    state.hour = 0;
    let dayFailedBoss: ContentSnapshot["stages"][number] | null = null;
    let wonSomething = false;

    // 在线 16h：反复尝试下一 Boss / 突破 / 强化
    let guard = 0;
    while (state.hour < ONLINE_HOURS && guard++ < 200) {
      if (reachedTarget(world, state.realmSlug, targetRealmId)) break;
      enhanceAll(world, state, timeline);
      if (tryBreakthrough(world, state, timeline, targetRealmId)) {
        state.hour += 1;
        wonSomething = true;
        continue;
      }
      const stage = nextChallengeStage(world, state);
      if (!stage) {
        // 无可打 Boss：刷修为凑突破
        settleOnlineCultivation(world, state, 1);
        state.hour += 1;
        continue;
      }
      const win = fightBoss(world, state, stage, timeline);
      state.hour += 1;
      if (win) {
        wonSomething = true;
        dayFailedBoss = null;
        while (tryBreakthrough(world, state, timeline, targetRealmId)) {
          /* chain */
        }
      } else {
        dayFailedBoss = stage;
        // 失败后刷装/强化 + 挂一点修为再试（同日可多次挑战）
        farmGearBeforeRetry(world, state, stage, timeline, state.failDays >= 2);
        settleOnlineCultivation(world, state, 0.5);
      }
    }

    if (reachedTarget(world, state.realmSlug, targetRealmId)) {
      pushOverview(overview, world, state, "ok");
      break;
    }

    // 挂机 8h + 洞府；若当日卡 Boss，挂机也刷装
    state.hour = ONLINE_HOURS;
    settleIdle(world, state, timeline);
    if (dayFailedBoss) {
      farmGearBeforeRetry(world, state, dayFailedBoss, timeline, true);
    }
    settleDongfu(world, state, timeline);
    while (tryBreakthrough(world, state, timeline, targetRealmId)) {
      /* after idle */
    }

    if (dayFailedBoss && !wonSomething) {
      if (state.failBossSlug === dayFailedBoss.slug) {
        state.failDays += 1;
      } else {
        state.failBossSlug = dayFailedBoss.slug;
        state.failDays = 1;
      }
      if (state.failDays >= STUCK_FAIL_DAYS) {
        stuck = buildStuck(world, state, dayFailedBoss);
        pushOverview(overview, world, state, "stuck");
        emit(timeline, state, "other", `卡死：连续 ${STUCK_FAIL_DAYS} 天打不过 ${stuck.bossName}`);
        break;
      }
    } else if (wonSomething) {
      state.failDays = 0;
      state.failBossSlug = null;
    }

    pushOverview(overview, world, state, "ok");
    state.day += 1;
    // 安全阀：极端配置避免无限日
    if (state.day > 5000) {
      truncated = true;
      emit(timeline, state, "other", "超过 5000 游戏天，停止推演");
      break;
    }
  }

  if (!stuck && reachedTarget(world, state.realmSlug, targetRealmId)) {
    emit(timeline, state, "other", `已达目标境界 ${realmName(world, targetRealmId)}`);
  }

  // 去掉重复的开局 overview 后若只有卡死，保留；保证至少一行
  if (overview.length === 0) {
    pushOverview(overview, world, state, stuck ? "stuck" : "ok");
  }

  return {
    overview,
    stuck,
    timeline,
    meta: { targetRealmId, elapsedMs: Date.now() - started, truncated },
  };
}

/** 供路由层：从 live DB 世界跑模拟。 */
export function runProgressionSimFromWorld(
  world: (ContentSnapshot & { version: number }) | null,
  options: { targetRealmId?: string; wallBudgetMs?: number } = {},
): ProgressionSimResult {
  if (!world || world.realms.length === 0) {
    throw new AppError("CONTENT_NOT_PUBLISHED", "当前没有生效配置，请先在后台保存内容");
  }
  return runProgressionSim(world, options);
}

