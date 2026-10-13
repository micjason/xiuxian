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
import { simulateBattle } from "../combat/battle.js";
import { computePower, ratePower, resolveBreakthrough, skillLayerFactor, sumReachedRealmStats } from "../combat/stats.js";
import { ensureSkillBook } from "../content/ops-content.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { rollDropTable } from "../content/roll-drops.js";
import { bookOverflowCultivation, decomposeCultivation, rollSchemeReward } from "../content/scheme-drops.js";
import type { ContentSnapshot } from "../content/validate.js";
import { settleTicks } from "../progress/settle.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { readGameRules } from "../content/rules.js";

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

function statsOf(world: World, realmSlug: string, items: { itemSlug: string; equippedSlot: string | null }[], skills: { skillSlug: string; runningSlot: string | null; level: number }[]) {
  return combatStats(
    world,
    realmSlug,
    items.filter((item) => item.equippedSlot).map((item) => item.itemSlug),
    skills.filter((skill) => skill.runningSlot).map((skill) => ({ slug: skill.skillSlug, level: skill.level })),
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

export function combatStats(world: ContentSnapshot, realmSlug: string, itemSlugs: string[], skillSlugs: (string | { slug: string; level: number })[]) {
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
  for (const itemSlug of itemSlugs) {
    const definition = world.items.find((row) => row.slug === itemSlug);
    gearAttack += definition?.attack ?? 0;
    gearDefense += definition?.defense ?? 0;
    gearHp += definition?.hp ?? 0;
    gearSpeed += definition?.speed ?? 0;
  }
  let attackPercent = 0;
  let defensePercent = 0;
  let hpPercent = 0;
  for (const entry of skillLayers(skillSlugs)) {
    const definition = world.skills.find((row) => row.slug === entry.slug);
    const factor = skillLayerFactor(entry.level);
    attackPercent += ((definition?.attack ?? 0) / 10000) * factor;
    defensePercent += ((definition?.defense ?? 0) / 10000) * factor;
    hpPercent += ((definition?.hp ?? 0) / 10000) * factor;
    bonusBp += (definition?.cultivateBonusBp ?? 0) * factor;
  }
  const attack = reached.attack * (1 + attackPercent) + gearAttack;
  const defense = reached.defense * (1 + defensePercent) + gearDefense;
  const hp = reached.hp * (1 + hpPercent) + gearHp;
  const speed = reached.speed + gearSpeed;
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
  return { attack, defense, hp, speed, interval: combat.interval, power: combat.power, bonusBp };
}

export type PowerSourceLine = {
  group: "境界" | "武器" | "功法";
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
  items: { itemSlug: string; equippedSlot: string | null; quantity: number }[],
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
    lines.push({
      group: "武器",
      name: `${name}${quantity}`,
      attack: equipped ? statOf(definition?.attack) : 0,
      defense: equipped ? statOf(definition?.defense) : 0,
      hp: equipped ? statOf(definition?.hp) : 0,
      speed: equipped ? statOf(definition?.speed) : 0,
      counted: equipped,
      note: !definition ? "后台里已经没有这件" : equipped ? "已穿上" : "在背包，不算战力",
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
  for (const skill of skills) {
    const definition = world.skills.find((row) => row.slug === skill.skillSlug);
    const level = skill.level;
    const running = Boolean(skill.runningSlot);
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
    const factor = skillLayerFactor(level);
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
  const totals = lines.filter((line) => line.counted).reduce(
    (sum, line) => ({
      attack: sum.attack + line.attack,
      defense: sum.defense + line.defense,
      hp: sum.hp + line.hp,
      speed: sum.speed + line.speed,
    }),
    { attack: 0, defense: 0, hp: 0, speed: 0 },
  );
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

async function settleLocked(tx: Tx, playerId: string, world: World, now: Date) {
  const { state } = await lockedState(tx, playerId);
  const pieces = await loadPieces(tx, playerId);
  const stats = statsOf(world, state.realmSlug, pieces.items, pieces.skills);
  const settled = settleTicks({
    cultivation: state.cultivation,
    lastSettledAt: state.lastSettledAt,
    now,
    tickSeconds: realmOf(world, state.realmSlug).tickSeconds,
    gainPerTick: realmOf(world, state.realmSlug).gainPerTick,
    bonusBp: stats.bonusBp,
    offlineCapSeconds: readGameRules(world).offlineCapSeconds,
  });
  const [saved] = await tx
    .update(playerStates)
    .set({
      cultivation: settled.cultivation,
      lastSettledAt: settled.lastSettledAt,
      stateVersion: state.stateVersion + 1,
    })
    .where(eq(playerStates.playerId, playerId))
    .returning();
  return { state: saved ?? { ...state, cultivation: settled.cultivation, lastSettledAt: settled.lastSettledAt }, pieces, stats, settled };
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
    cultivationRate: { bonusBp: settled.stats.bonusBp, gainPerTick: realm.gainPerTick },
    breakthrough: { rateBp, cost: realm.breakthroughCost, nextSlug: realm.nextRealmSlug },
    challengeCooldownSeconds: readGameRules(world).challengeCooldownSeconds,
    autoDecompose: settled.state.autoDecompose,
    items: settled.pieces.items,
    skills: settled.pieces.skills,
    stages: settled.pieces.stages,
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

function wornGear(world: World, items: { itemSlug: string; equippedSlot: string | null }[], slot: string) {
  const worn = items.find((row) => row.equippedSlot === slot);
  if (!worn) {
    return null;
  }
  return world.items.find((row) => row.slug === worn.itemSlug) ?? null;
}

async function grant(
  tx: Tx,
  world: World,
  playerId: string,
  itemSlug: string,
  quantity: number,
  source: string,
  now: Date,
  options?: {
    autoDecompose: boolean;
    worn: { itemSlug: string; equippedSlot: string | null }[];
    gainPerTick: number;
    weights: { attack: number; defense: number; hp: number; speed: number };
  },
): Promise<{ decomposed: boolean; cultivation: number }> {
  const definition = world.items.find((row) => row.slug === itemSlug);
  if (!definition || quantity <= 0) {
    return { decomposed: false, cultivation: 0 };
  }
  if (options?.autoDecompose && definition.kind === "equipment" && definition.slot) {
    const worn = wornGear(world, options.worn, definition.slot);
    if (worn) {
      const stats = (item: { attack?: number; defense?: number; hp?: number; speed?: number }) => ({
        attack: item.attack ?? 0,
        defense: item.defense ?? 0,
        hp: item.hp ?? 0,
        speed: item.speed ?? 0,
      });
      if (ratePower(stats(definition), options.weights) < ratePower(stats(worn), options.weights)) {
        const cultivation = decomposeCultivation(definition.quality ?? "", options.gainPerTick);
        await addCultivation(tx, playerId, cultivation * quantity);
        return { decomposed: true, cultivation: cultivation * quantity };
      }
    }
  }
  const stackable = definition.kind !== "equipment";
  if (stackable) {
    const [row] = await tx
      .select()
      .from(playerItems)
      .where(and(eq(playerItems.playerId, playerId), eq(playerItems.itemSlug, itemSlug), eq(playerItems.isStack, true)))
      .limit(1);
    if (row) {
      await tx.update(playerItems).set({ quantity: row.quantity + quantity }).where(eq(playerItems.id, row.id));
      return { decomposed: false, cultivation: 0 };
    }
    await tx.insert(playerItems).values({
      playerId,
      itemSlug,
      isStack: true,
      quantity,
      source,
      acquiredAt: now,
    });
    return { decomposed: false, cultivation: 0 };
  }
  for (let index = 0; index < quantity; index += 1) {
    await tx.insert(playerItems).values({
      playerId,
      itemSlug,
      isStack: false,
      quantity: 1,
      source,
      acquiredAt: now,
    });
  }
  return { decomposed: false, cultivation: 0 };
}

export async function initializeProgress(tx: Tx, playerId: string, now: Date) {
  const world = await loadCurrentWorld(tx);
  if (!world) {
    return;
  }
  const first = [...world.stages].filter((row) => row.enabled).sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0))[0];
  if (first) {
    await tx.insert(playerStageProgress).values({ playerId, stageSlug: first.slug, unlockedAt: now }).onConflictDoNothing();
  }
  for (const starter of world.globals.starterItems ?? []) {
    await grant(tx, world, playerId, starter.itemSlug, starter.quantity, "starter", now);
  }
}

export async function readState(db: Db, playerId: string, now: Date) {
  const world = await worldOrThrow(db);
  return withTransaction(db, async (tx) => stateDto(world, playerId, await settleLocked(tx, playerId, world, now)));
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
    failLossBp: realm.failLossBp ?? 0,
    failStreak: settled.state.breakthroughFailStreak,
    roll,
  });
  await tx
    .update(playerStates)
    .set({
      cultivation: result.cultivation,
      realmSlug: result.success ? realm.nextRealmSlug : settled.state.realmSlug,
      breakthroughFailStreak: result.failStreak,
    })
    .where(eq(playerStates.playerId, playerId));
  const after = await settleLocked(tx, playerId, world, now);
  return {
    result: { success: result.success, rateBp, roll, lostCultivation: result.lostCultivation },
    state: stateDto(world, playerId, after),
  };
}

export async function challengeStage(tx: Tx, world: World, playerId: string, stageSlug: string, now: Date, randomInt: RandomInt) {
  const settled = await settleLocked(tx, playerId, world, now);
  const stage = world.stages.find((row) => row.slug === stageSlug);
  if (!stage) {
    throw new AppError("NOT_FOUND");
  }
  const realm = realmOf(world, settled.state.realmSlug);
  if (realm.sortOrder == null || stage.requiredRealmOrder == null) {
    throw new AppError("INVALID_INPUT", "关卡没有所属境界");
  }
  if (realm.sortOrder < stage.requiredRealmOrder) {
    throw new AppError("REALM_TOO_LOW");
  }
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
    };
  }
  const rules = readGameRules(world);
  const cooldown = rules.challengeCooldownSeconds;
  if (cooldown > 0 && settled.state.lastChallengeAt && now.getTime() - settled.state.lastChallengeAt.getTime() < cooldown * 1000) {
    throw new AppError("CHALLENGE_COOLDOWN", `挑战冷却中，要间隔 ${cooldown} 秒`);
  }
  const bagCapacity = rules.bagCapacity;
  const used = settled.pieces.items.filter((row) => !row.equippedSlot).length;
  if (used >= bagCapacity) {
    throw new AppError("BAG_FULL");
  }
  if (stage.bosses && stage.bosses.length === 0) {
    throw new AppError("INVALID_INPUT", "这个关卡还没有首领");
  }
  const boss = stage.bosses?.[0];
  const bossAttack = boss ? boss.attack : (stage.bossAttack ?? 1);
  const bossDefense = boss ? boss.defense : (stage.bossDefense ?? 0);
  const bossHp = boss ? boss.hp : stage.bossHp;
  const bossInterval = boss ? boss.interval : stage.bossInterval;
  if (bossHp <= 0 || bossInterval <= 0) {
    throw new AppError("INVALID_INPUT", "这个首领还没填气血或出手间隔");
  }
  const battle = simulateBattle(
    {
      attack: settled.stats.attack,
      defense: settled.stats.defense,
      hp: settled.stats.hp,
      interval: settled.stats.interval,
    },
    {
      attack: bossAttack,
      defense: bossDefense,
      hp: bossHp,
      interval: bossInterval,
    },
    battleConfigOf(world),
  );
  const drops: { itemSlug: string; quantity: number; decomposed?: boolean; cultivation?: number }[] = [];
  let nextPity: Record<string, number> | undefined;
  if (battle.win) {
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
      const granted = await grant(tx, world, playerId, drop.itemSlug, drop.quantity, `drop:${stage.slug}`, now, {
        autoDecompose: settled.state.autoDecompose,
        worn: settled.pieces.items,
        gainPerTick: realm.gainPerTick,
        weights: rules.powerWeights,
      });
      if (granted.decomposed) {
        drop.decomposed = true;
        drop.cultivation = granted.cultivation;
      }
    }
    await tx
      .update(playerStageProgress)
      .set({
        firstClearedAt: progress.firstClearedAt ?? now,
        clearCount: progress.clearCount + 1,
        bestClearSeconds:
          progress.bestClearSeconds == null ? battle.durationSeconds : Math.min(progress.bestClearSeconds, battle.durationSeconds),
      })
      .where(and(eq(playerStageProgress.playerId, playerId), eq(playerStageProgress.stageSlug, stageSlug)));
    if (stage.nextStageSlug) {
      await tx
        .insert(playerStageProgress)
        .values({ playerId, stageSlug: stage.nextStageSlug, unlockedAt: now })
        .onConflictDoNothing();
    }
  }
  await tx
    .update(playerStates)
    .set(nextPity ? { lastChallengeAt: now, dropPity: nextPity } : { lastChallengeAt: now })
    .where(eq(playerStates.playerId, playerId));
  const after = await settleLocked(tx, playerId, world, now);
  return { battle, drops, state: stateDto(world, playerId, after) };
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
  if (existing && existing.level >= 7) {
    const gained = bookOverflowCultivation(skill.rank, realm.gainPerTick);
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
    throw new AppError("INVALID_INPUT", "先脱下来再分解");
  }
  const definition = world.items.find((row) => row.slug === item.itemSlug);
  if (!definition || definition.kind !== "equipment" || !definition.slot) {
    throw new AppError("NOT_EQUIPMENT", "这不是装备，不能分解");
  }
  const worn = wornGear(world, settled.pieces.items, definition.slot);
  if (!worn) {
    throw new AppError("INVALID_INPUT", "身上这个部位还是空的");
  }
  const rules = readGameRules(world);
  const stats = (row: { attack?: number; defense?: number; hp?: number; speed?: number }) => ({
    attack: row.attack ?? 0,
    defense: row.defense ?? 0,
    hp: row.hp ?? 0,
    speed: row.speed ?? 0,
  });
  if (ratePower(stats(definition), rules.powerWeights) >= ratePower(stats(worn), rules.powerWeights)) {
    throw new AppError("INVALID_INPUT", "这件不比身上的差");
  }
  const realm = realmOf(world, settled.state.realmSlug);
  const gained = decomposeCultivation(definition.quality ?? "", realm.gainPerTick) * item.quantity;
  await tx.delete(playerItems).where(eq(playerItems.id, item.id));
  await addCultivation(tx, playerId, gained);
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after), convertedCultivation: gained };
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
  const slots = ["run_1", "run_2", "run_3"];
  const others = settled.pieces.skills.filter((row) => row.runningSlot && row.skillSlug !== skillSlug);
  if (others.length >= slots.length) {
    throw new AppError("SKILL_SLOT_INVALID", "最多同时运转 3 门功法");
  }
  const used = new Set(others.map((row) => row.runningSlot));
  const free = learned.runningSlot && slots.includes(learned.runningSlot) ? learned.runningSlot : slots.find((slot) => !used.has(slot));
  if (!free) {
    throw new AppError("SKILL_SLOT_INVALID", "最多同时运转 3 门功法");
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
