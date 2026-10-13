import { eq } from "drizzle-orm";
import { withTransaction, type Tx } from "../../db/tx.js";
import {
  contentCurrent,
  contentRealms,
  contentVersions,
  idempotencyKeys,
  noticeDismissals,
  playerItems,
  playerNotices,
  playerSkills,
  playerStageProgress,
  playerStates,
  players,
  repairApplications,
} from "../../db/schema.js";
import { settleTicks } from "../progress/settle.js";
import { AppError } from "../../shared/errors.js";
import { getPublishedRealm } from "../content/service.js";
import { writeOperation, type Db } from "../operations/record.js";
import { rememberIncome, noticesForPlayer } from "../notices/service.js";
import { piecePower } from "./power.js";
import { explainPlayerPower } from "../loop/actions.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { readRules } from "../content/rules.js";
import { breakthrough, settleCultivation } from "./progress-rules.js";

async function lockedPlayer(db: Tx, playerId: string) {
  const [state] = await db
    .select()
    .from(playerStates)
    .where(eq(playerStates.playerId, playerId))
    .for("update")
    .limit(1);
  const [player] = await db.select().from(players).where(eq(players.id, playerId)).limit(1);
  if (!state || !player) {
    throw new Error("player missing");
  }
  return { state, player };
}

export async function openProgress(db: Db, playerId: string, now: Date, versionCode = 0) {
  const realmPreview = await db.select({ realmSlug: playerStates.realmSlug, username: players.username, cultivation: playerStates.cultivation }).from(playerStates).innerJoin(players, eq(players.id, playerStates.playerId)).where(eq(playerStates.playerId, playerId)).limit(1);
  const preview = realmPreview[0];
  if (!preview) {
    throw new Error("player missing");
  }
  const realmOutside = await getPublishedRealm(db, preview.realmSlug);
  if (!realmOutside) {
    await writeOperation(db, {
      at: now,
      actorType: "player",
      actorId: playerId,
      actorName: preview.username,
      action: "settle",
      result: "failure",
      reason: "missing_release",
      summary: { cultivation: preview.cultivation, realmSlug: preview.realmSlug },
    });
    throw new Error("published config missing");
  }
  return withTransaction(db, async (tx) => openProgressLocked(tx, playerId, now, versionCode));
}

async function openProgressLocked(db: Tx, playerId: string, now: Date, versionCode: number) {
  const { state, player } = await lockedPlayer(db, playerId);
  const previousSettledAt = state.lastSettledAt;
  const realm = await getPublishedRealm(db, state.realmSlug);
  if (!realm) {
    throw new Error("published config missing");
  }
  const elapsedSeconds = Math.floor((now.getTime() - previousSettledAt.getTime()) / 1000);
  const settled = settleCultivation({
    cultivation: state.cultivation,
    elapsedSeconds,
    gainPerSecond: realm.gainPerSecond,
    offlineCapSeconds: realm.offlineCapSeconds,
  });
  await db
    .update(playerStates)
    .set({ cultivation: settled.cultivation, lastSettledAt: now })
    .where(eq(playerStates.playerId, playerId));
  await writeOperation(db, {
    at: now,
    actorType: "player",
    actorId: playerId,
    actorName: player.username,
    action: "settle",
    result: "success",
    summary: {
      before: state.cultivation,
      after: settled.cultivation,
      countedSeconds: settled.countedSeconds,
      gainPerSecond: realm.gainPerSecond,
      realmSlug: state.realmSlug,
    },
  });
  await rememberIncome(db, playerId, {
    countedSeconds: settled.countedSeconds,
    gained: settled.gained,
    hitCap: elapsedSeconds > settled.countedSeconds,
    offlineCapSeconds: realm.offlineCapSeconds,
    previousSettledAt,
  });
  const next = realm.nextSlug ? await getPublishedRealm(db, realm.nextSlug) : null;
  const notices = await noticesForPlayer(db, playerId, versionCode);
  const rules = await readRules(db);
  const weights = {
    attack: rules.attackWeight,
    defense: rules.defenseWeight,
    hp: rules.hpWeight,
    speed: rules.speedWeight,
  };
  if (weights.attack == null || weights.defense == null || weights.hp == null || weights.speed == null) {
    throw new AppError("INVALID_INPUT", "请先在后台填写：攻击权重、防御权重、气血权重、速度权重");
  }
  const powerWeights = {
    attack: weights.attack,
    defense: weights.defense,
    hp: weights.hp,
    speed: weights.speed,
  };
  return {
    realmSlug: state.realmSlug,
    realmName: realm.displayName,
    cultivation: settled.cultivation,
    gained: settled.gained,
    gainPerSecond: realm.gainPerSecond,
    offlineCapSeconds: realm.offlineCapSeconds,
    breakthroughCost: realm.breakthroughCost,
    nextRealmName: next?.displayName ?? "",
    canBreakthrough: next !== null && settled.cultivation >= realm.breakthroughCost,
    power: piecePower(realm, powerWeights),
    notices,
  };
}

export async function syncFromSnapshot(db: Db, playerId: string, now: Date) {
  const [current] = await db.select().from(contentCurrent).where(eq(contentCurrent.id, 1)).limit(1);
  if (!current) {
    throw new AppError("CONTENT_NOT_PUBLISHED");
  }
  const [version] = await db.select().from(contentVersions).where(eq(contentVersions.version, current.version)).limit(1);
  if (!version) {
    throw new AppError("CONTENT_NOT_PUBLISHED");
  }
  const snapshot = version.snapshot as {
    realms: { slug: string; tickSeconds: number; gainPerTick: number }[];
    globals: { offlineCapSeconds: number };
  };
  return withTransaction(db, async (tx) => {
    const { state } = await lockedPlayer(tx, playerId);
    const realm = snapshot.realms.find((row) => row.slug === state.realmSlug);
    if (!realm) {
      throw new AppError("CONTENT_NOT_PUBLISHED");
    }
    if (snapshot.globals.offlineCapSeconds == null || snapshot.globals.offlineCapSeconds <= 0) {
      throw new AppError("INVALID_INPUT", "请先在后台填写离线上限");
    }
    const settled = settleTicks({
      cultivation: state.cultivation,
      lastSettledAt: state.lastSettledAt,
      now,
      tickSeconds: realm.tickSeconds,
      gainPerTick: realm.gainPerTick,
      bonusBp: 0,
      offlineCapSeconds: snapshot.globals.offlineCapSeconds,
    });
    await tx
      .update(playerStates)
      .set({ cultivation: settled.cultivation, lastSettledAt: settled.lastSettledAt })
      .where(eq(playerStates.playerId, playerId));
    return { cultivation: settled.cultivation, contentVersion: current.version, countedSeconds: settled.countedSeconds };
  });
}

export async function listPlayers(db: Db) {
  const world = await loadCurrentWorld(db);
  const [rows, itemRows, skillRows] = await Promise.all([
    db
      .select({
        playerId: players.id,
        username: players.username,
        cultivation: playerStates.cultivation,
        realmSlug: playerStates.realmSlug,
        lastSettledAt: playerStates.lastSettledAt,
      })
      .from(players)
      .innerJoin(playerStates, eq(playerStates.playerId, players.id)),
    db.select().from(playerItems),
    db.select().from(playerSkills),
  ]);
  return rows.map((row) => {
    const realmName = world?.realms.find((realm) => realm.slug === row.realmSlug)?.displayName || "境界不存在";
    const breakdown = world
      ? explainPlayerPower(
          world,
          row.realmSlug,
          itemRows.filter((item) => item.playerId === row.playerId),
          skillRows.filter((skill) => skill.playerId === row.playerId),
        )
      : { power: null, error: "还没有境界", attack: 0, defense: 0, hp: 0, speed: 0, weights: null, lines: [], steps: [] };
    return {
      username: row.username,
      realmName,
      cultivation: row.cultivation,
      lastSettledAt: row.lastSettledAt,
      power: breakdown.power,
      powerError: breakdown.error,
      breakdown,
    };
  });
}

export async function resetPlayer(db: Db, username: string, now: Date) {
  const [player] = await db.select().from(players).where(eq(players.username, username)).limit(1);
  if (!player) {
    throw new AppError("NOT_FOUND", "没有这个账号");
  }
  const realms = await db.select().from(contentRealms);
  if (realms.length === 0) {
    throw new AppError("CONTENT_NOT_PUBLISHED", "还没有境界，不能清空");
  }
  const start = realms.reduce((smallest, row) => (row.sortOrder < smallest.sortOrder ? row : smallest));
  await db.delete(idempotencyKeys).where(eq(idempotencyKeys.playerId, player.id));
  await db.delete(playerItems).where(eq(playerItems.playerId, player.id));
  await db.delete(playerSkills).where(eq(playerSkills.playerId, player.id));
  await db.delete(playerStageProgress).where(eq(playerStageProgress.playerId, player.id));
  await db.delete(noticeDismissals).where(eq(noticeDismissals.playerId, player.id));
  await db.delete(playerNotices).where(eq(playerNotices.playerId, player.id));
  await db.delete(repairApplications).where(eq(repairApplications.playerId, player.id));
  const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, player.id)).limit(1);
  if (!state) {
    await db.insert(playerStates).values({
      playerId: player.id,
      cultivation: 0,
      realmSlug: start.slug,
      lastSettledAt: now,
    });
    return { ok: true };
  }
  await db
    .update(playerStates)
    .set({
      cultivation: 0,
      spiritStones: 0,
      realmSlug: start.slug,
      lastSettledAt: now,
      breakthroughFailStreak: 0,
      idleStageSlug: null,
      lastChallengeAt: null,
    })
    .where(eq(playerStates.playerId, player.id));
  return { ok: true };
}

export async function tryBreakthrough(db: Db, playerId: string, now: Date) {
  return withTransaction(db, async (tx) => tryBreakthroughLocked(tx, playerId, now));
}

async function tryBreakthroughLocked(db: Tx, playerId: string, now: Date) {
  const { state, player } = await lockedPlayer(db, playerId);
  const realm = await getPublishedRealm(db, state.realmSlug);
  if (!realm) {
    await writeOperation(db, {
      at: now,
      actorType: "player",
      actorId: playerId,
      actorName: player.username,
      action: "breakthrough",
      result: "failure",
      reason: "missing_release",
      summary: { cultivation: state.cultivation },
    });
    return { ok: false as const, reason: "not_enough" as const };
  }
  const result = breakthrough({
    cultivation: state.cultivation,
    cost: realm.breakthroughCost,
    nextSlug: realm.nextSlug,
  });
  if (!result.ok) {
    await writeOperation(db, {
      at: now,
      actorType: "player",
      actorId: playerId,
      actorName: player.username,
      action: "breakthrough",
      result: "failure",
      reason: result.reason,
      summary: { cultivation: state.cultivation, realmSlug: state.realmSlug },
    });
    return result;
  }
  await db
    .update(playerStates)
    .set({ cultivation: result.cultivation, realmSlug: result.nextSlug })
    .where(eq(playerStates.playerId, playerId));
  await writeOperation(db, {
    at: now,
    actorType: "player",
    actorId: playerId,
    actorName: player.username,
    action: "breakthrough",
    result: "success",
    summary: {
      beforeRealm: state.realmSlug,
      afterRealm: result.nextSlug,
      beforeCultivation: state.cultivation,
      afterCultivation: result.cultivation,
      cost: realm.breakthroughCost,
    },
  });
  return { ok: true as const, realmSlug: result.nextSlug, cultivation: result.cultivation };
}
