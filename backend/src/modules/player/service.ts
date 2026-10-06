import { eq } from "drizzle-orm";
import { playerStates, players } from "../../db/schema.js";
import { getPublishedRealm } from "../content/service.js";
import { writeOperation, type Db } from "../operations/record.js";
import { piecePower } from "./power.js";
import { breakthrough, settleCultivation } from "./progress-rules.js";

async function lockedPlayer(db: Db, playerId: string) {
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

export async function openProgress(db: Db, playerId: string, now: Date) {
  const { state, player } = await lockedPlayer(db, playerId);
  const realm = await getPublishedRealm(db, state.realmSlug);
  if (!realm) {
    await writeOperation(db, {
      at: now,
      actorType: "player",
      actorId: playerId,
      actorName: player.username,
      action: "settle",
      result: "failure",
      reason: "missing_release",
      summary: { cultivation: state.cultivation, realmSlug: state.realmSlug },
    });
    throw new Error("published config missing");
  }
  const elapsedSeconds = Math.floor((now.getTime() - state.lastSettledAt.getTime()) / 1000);
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
  return {
    realmSlug: state.realmSlug,
    realmName: realm.displayName,
    cultivation: settled.cultivation,
    gained: settled.gained,
    power: piecePower(realm),
  };
}

export async function tryBreakthrough(db: Db, playerId: string, now: Date) {
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
