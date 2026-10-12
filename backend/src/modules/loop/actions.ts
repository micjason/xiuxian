import { and, eq } from "drizzle-orm";
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
import { computePower, ratePower, resolveBreakthrough, sumReachedRealmStats } from "../combat/stats.js";
import { ensureSkillBook } from "../content/ops-content.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { rollDropTable } from "../content/roll-drops.js";
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

function artSlotCount(world: World, sortOrder: number) {
  const rules = world.globals.artSlotRules;
  if (!rules || rules.length === 0) {
    throw new AppError("INVALID_INPUT", "请先在后台填写功法栏");
  }
  let slots = 0;
  for (const rule of rules) {
    if (sortOrder >= rule.minRealmOrder) {
      slots = Math.max(slots, rule.slots);
    }
  }
  if (slots <= 0) {
    throw new AppError("INVALID_INPUT", "请先在后台填写功法栏");
  }
  return slots;
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
  let attack = reached.attack;
  let defense = reached.defense;
  let hp = reached.hp;
  let speed = reached.speed;
  let bonusBp = 0;
  for (const itemSlug of itemSlugs) {
    const definition = world.items.find((row) => row.slug === itemSlug);
    attack += definition?.attack ?? 0;
    defense += definition?.defense ?? 0;
    hp += definition?.hp ?? 0;
    speed += definition?.speed ?? 0;
  }
  for (const entry of skillLayers(skillSlugs)) {
    const definition = world.skills.find((row) => row.slug === entry.slug);
    const level = entry.level;
    attack += (definition?.attack ?? 0) * level;
    defense += (definition?.defense ?? 0) * level;
    hp += (definition?.hp ?? 0) * level;
    speed += (definition?.speed ?? 0) * level;
    bonusBp += (definition?.cultivateBonusBp ?? 0) * level;
  }
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
    lines.push({
      group: "功法",
      name: `${definition?.displayName || (definition ? "名称缺失" : "已删除")} · ${level}层`,
      attack: running ? statOf(definition?.attack) * level : 0,
      defense: running ? statOf(definition?.defense) * level : 0,
      hp: running ? statOf(definition?.hp) * level : 0,
      speed: running ? statOf(definition?.speed) * level : 0,
      counted: running,
      note: !definition ? "后台里已经没有这门功法" : running ? `${level}层，效果按层数相乘` : "没有运转，不算战力",
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
    playerDefenseFactor: rules.playerDefenseFactor,
    bossDefenseFactor: rules.bossDefenseFactor,
    playerDamageFloor: rules.playerDamageFloor,
    bossDamageFloor: rules.bossDamageFloor,
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

async function grant(tx: Tx, world: World, playerId: string, itemSlug: string, quantity: number, source: string, now: Date) {
  const definition = world.items.find((row) => row.slug === itemSlug);
  if (!definition || quantity <= 0) {
    return;
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
      return;
    }
    await tx.insert(playerItems).values({
      playerId,
      itemSlug,
      isStack: true,
      quantity,
      source,
      acquiredAt: now,
    });
    return;
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
  const drops: { itemSlug: string; quantity: number }[] = [];
  if (battle.win) {
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
      await grant(tx, world, playerId, drop.itemSlug, drop.quantity, `drop:${stage.slug}`, now);
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
  await tx.update(playerStates).set({ lastChallengeAt: now }).where(eq(playerStates.playerId, playerId));
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
  const realm = realmOf(world, settled.state.realmSlug);
  if ((realm.sortOrder ?? 0) < (definition.requiredRealmOrder ?? 0)) {
    throw new AppError("REALM_TOO_LOW");
  }
  if (!item.equippedSlot) {
    await tx.update(playerItems).set({ equippedSlot: item.id }).where(eq(playerItems.id, item.id));
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
  const level = existing ? existing.level + 1 : 1;
  if (!existing) {
    const realm = realmOf(world, settled.state.realmSlug);
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

export async function runSkill(tx: Tx, world: World, playerId: string, skillSlug: string, slot: string, now: Date) {
  const settled = await settleLocked(tx, playerId, world, now);
  const learned = settled.pieces.skills.find((row) => row.skillSlug === skillSlug);
  if (!learned) {
    throw new AppError("SKILL_NOT_LEARNED");
  }
  const skill = world.skills.find((row) => row.slug === skillSlug);
  if (!skill?.role) {
    throw new AppError("INVALID_INPUT", "这门功法还没有运转位置");
  }
  const realm = realmOf(world, settled.state.realmSlug);
  const allowed = skill.role === "heart" ? ["heart"] : ["art_1", "art_2"].slice(0, artSlotCount(world, realm.sortOrder ?? 0));
  if (!allowed.includes(slot)) {
    throw new AppError("SKILL_SLOT_INVALID");
  }
  const occupant = settled.pieces.skills.find((row) => row.runningSlot === slot && row.skillSlug !== skillSlug);
  if (occupant) {
    await tx
      .update(playerSkills)
      .set({ runningSlot: null })
      .where(and(eq(playerSkills.playerId, playerId), eq(playerSkills.skillSlug, occupant.skillSlug)));
  }
  await tx
    .update(playerSkills)
    .set({ runningSlot: slot })
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
