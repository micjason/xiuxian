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
import { computePower } from "../combat/stats.js";
import { breakthroughRate, resolveBreakthrough } from "../combat/stats.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { rollDropTable } from "../content/roll-drops.js";
import type { ContentSnapshot } from "../content/validate.js";
import { settleTicks } from "../progress/settle.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";

type World = ContentSnapshot & { version: number };
type RandomInt = (min: number, max: number) => number;

const weights = { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 };

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
    throw new AppError("CONTENT_NOT_PUBLISHED");
  }
  return realm;
}

function artSlotCount(world: World, sortOrder: number) {
  let slots = 1;
  for (const rule of world.globals.artSlotRules ?? []) {
    if (sortOrder >= rule.minRealmOrder) {
      slots = Math.max(slots, rule.slots);
    }
  }
  return slots;
}

async function loadPieces(tx: Tx, playerId: string) {
  const items = await tx.select().from(playerItems).where(eq(playerItems.playerId, playerId));
  const skills = await tx.select().from(playerSkills).where(eq(playerSkills.playerId, playerId));
  const stages = await tx.select().from(playerStageProgress).where(eq(playerStageProgress.playerId, playerId));
  return { items, skills, stages };
}

function statsOf(world: World, realmSlug: string, items: { itemSlug: string; equippedSlot: string | null }[], skills: { skillSlug: string; runningSlot: string | null }[]) {
  const realm = realmOf(world, realmSlug);
  let attack = realm.baseAttack ?? 0;
  let defense = realm.baseDefense ?? 0;
  let hp = realm.baseHp ?? 0;
  let speed = realm.baseSpeed ?? 0;
  let bonusBp = 0;
  for (const item of items) {
    if (!item.equippedSlot) {
      continue;
    }
    const definition = world.items.find((row) => row.slug === item.itemSlug);
    attack += definition?.attack ?? 0;
    defense += definition?.defense ?? 0;
    hp += definition?.hp ?? 0;
    speed += definition?.speed ?? 0;
  }
  for (const skill of skills) {
    if (!skill.runningSlot) {
      continue;
    }
    const definition = world.skills.find((row) => row.slug === skill.skillSlug);
    attack += definition?.attack ?? 0;
    defense += definition?.defense ?? 0;
    hp += definition?.hp ?? 0;
    speed += definition?.speed ?? 0;
    bonusBp += definition?.cultivateBonusBp ?? 0;
  }
  const combat = computePower({
    attack,
    defense,
    hp,
    speed,
    baseInterval: realm.baseInterval ?? 1.5,
    minInterval: world.globals.combat?.minInterval ?? 0.7,
    weights: world.globals.powerWeights ?? weights,
  });
  return { attack, defense, hp, speed, interval: combat.interval, power: combat.power, bonusBp };
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
    offlineCapSeconds: world.globals.offlineCapSeconds ?? 28800,
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
  const rateBp = next
    ? breakthroughRate({
        power: settled.stats.power,
        recommendedPower: realm.recommendedPower,
        baseRateBp: realm.baseRateBp,
        powerFactorBp: realm.powerFactorBp ?? 3000,
        minRateBp: realm.minRateBp,
        maxRateBp: realm.maxRateBp,
        failStreak: settled.state.breakthroughFailStreak,
        pityStepBp: realm.pityStepBp ?? 1000,
      })
    : 0;
  return {
    playerId,
    contentVersion: world.version,
    cultivation: settled.state.cultivation,
    spiritStones: settled.state.spiritStones,
    realmSlug: settled.state.realmSlug,
    realmName: realm.displayName ?? settled.state.realmSlug,
    power: settled.stats.power,
    cultivationRate: { bonusBp: settled.stats.bonusBp, gainPerTick: realm.gainPerTick },
    breakthrough: { rateBp, cost: realm.breakthroughCost, nextSlug: realm.nextRealmSlug },
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
  const rateBp = breakthroughRate({
    power: settled.stats.power,
    recommendedPower: realm.recommendedPower,
    baseRateBp: realm.baseRateBp,
    powerFactorBp: realm.powerFactorBp ?? 3000,
    minRateBp: realm.minRateBp,
    maxRateBp: realm.maxRateBp,
    failStreak: settled.state.breakthroughFailStreak,
    pityStepBp: realm.pityStepBp ?? 1000,
  });
  const roll = randomInt(0, 10000);
  const result = resolveBreakthrough({
    cultivation: settled.state.cultivation,
    cost: realm.breakthroughCost,
    rateBp,
    failLossBp: realm.failLossBp ?? 3000,
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
  const progress = settled.pieces.stages.find((row) => row.stageSlug === stageSlug);
  if (!progress) {
    throw new AppError("STAGE_LOCKED");
  }
  const realm = realmOf(world, settled.state.realmSlug);
  if ((realm.sortOrder ?? 0) < (stage.requiredRealmOrder ?? 0)) {
    throw new AppError("REALM_TOO_LOW");
  }
  const cooldown = world.globals.combat?.challengeCooldownSeconds ?? 3;
  if (settled.state.lastChallengeAt && now.getTime() - settled.state.lastChallengeAt.getTime() < cooldown * 1000) {
    throw new AppError("CHALLENGE_COOLDOWN");
  }
  const bagCapacity = world.globals.bagCapacity ?? 100;
  const used = settled.pieces.items.filter((row) => !row.equippedSlot).length;
  if (used >= bagCapacity) {
    throw new AppError("BAG_FULL");
  }
  const battle = simulateBattle(
    {
      attack: settled.stats.attack,
      defense: settled.stats.defense,
      hp: settled.stats.hp,
      interval: settled.stats.interval,
    },
    {
      attack: stage.bossAttack ?? 1,
      defense: stage.bossDefense ?? 0,
      hp: stage.bossHp,
      interval: stage.bossInterval,
    },
    {
      timeLimitSeconds: 60,
      playerDefenseFactor: world.globals.combat?.playerDefenseFactor ?? 0.4,
      bossDefenseFactor: world.globals.combat?.bossDefenseFactor ?? 0.5,
    },
  );
  const drops: { itemSlug: string; quantity: number }[] = [];
  if (battle.win) {
    const bossTable = world.dropTables.find((row) => row.slug === stage.bossDropTableSlug);
    drops.push(...rollDropTable(bossTable?.entries ?? [], randomInt));
    if (!progress.firstClearedAt) {
      const firstTable = world.dropTables.find((row) => row.slug === stage.firstClearDropTableSlug);
      drops.push(...rollDropTable(firstTable?.entries ?? [], randomInt));
    }
    for (const drop of drops) {
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
  if (!definition || definition.kind !== "equipment" || !definition.slot) {
    throw new AppError("NOT_EQUIPMENT");
  }
  const realm = realmOf(world, settled.state.realmSlug);
  if ((realm.sortOrder ?? 0) < (definition.requiredRealmOrder ?? 0)) {
    throw new AppError("REALM_TOO_LOW");
  }
  const wearing = settled.pieces.items.find((row) => row.equippedSlot === definition.slot && row.id !== item.id);
  if (wearing) {
    await tx.update(playerItems).set({ equippedSlot: null }).where(eq(playerItems.id, wearing.id));
  }
  await tx.update(playerItems).set({ equippedSlot: definition.slot }).where(eq(playerItems.id, item.id));
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
  if (settled.pieces.skills.some((row) => row.skillSlug === skill.slug)) {
    throw new AppError("ALREADY_LEARNED");
  }
  const realm = realmOf(world, settled.state.realmSlug);
  if ((realm.sortOrder ?? 0) < (skill.requiredRealmOrder ?? 0)) {
    throw new AppError("REALM_TOO_LOW");
  }
  for (const prerequisite of skill.prerequisiteSkillSlugs) {
    if (!settled.pieces.skills.some((row) => row.skillSlug === prerequisite)) {
      throw new AppError("PREREQUISITE_MISSING");
    }
  }
  if (item.quantity <= 1) {
    await tx.delete(playerItems).where(eq(playerItems.id, item.id));
  } else {
    await tx.update(playerItems).set({ quantity: item.quantity - 1 }).where(eq(playerItems.id, item.id));
  }
  await tx.insert(playerSkills).values({ playerId, skillSlug: skill.slug, learnedAt: now });
  const after = await settleLocked(tx, playerId, world, now);
  return { state: stateDto(world, playerId, after) };
}

export async function runSkill(tx: Tx, world: World, playerId: string, skillSlug: string, slot: string, now: Date) {
  const settled = await settleLocked(tx, playerId, world, now);
  const learned = settled.pieces.skills.find((row) => row.skillSlug === skillSlug);
  if (!learned) {
    throw new AppError("SKILL_NOT_LEARNED");
  }
  const skill = world.skills.find((row) => row.slug === skillSlug);
  const realm = realmOf(world, settled.state.realmSlug);
  const allowed = skill?.role === "heart" ? ["heart"] : ["art_1", "art_2"].slice(0, artSlotCount(world, realm.sortOrder ?? 0));
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
