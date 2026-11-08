/** Durable combat journal. Uses the existing transactional idempotency table (no transient in-memory battle state).
 * A start saves the full server-computed timeline before the client plays it. Rewards are applied once at finish/recover.
 * Disconnect never loses the outcome; explicit retreat is the only action that converts it to a loss before settlement.
 */
import { randomUUID } from "node:crypto";
import { and, desc, eq, sql } from "drizzle-orm";
import { z } from "zod";
import type { FastifyInstance } from "fastify";
import { idempotencyKeys, playerStates } from "../../db/schema.js";
import { withTransaction, type Tx } from "../../db/tx.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import type { ContentSnapshot } from "../content/validate.js";
import { challengeStage, withIdempotency } from "../loop/actions.js";
import { battleFog } from "../fog/actions.js";
import { runtimeConfigOf } from "./runtime-config.js";
import { finishDecision, type FinishMode } from "./session-policy.js";
import type { BattleResult } from "./battle.js";

type World = ContentSnapshot & { version: number };
type Target = { source: "stage"; stageSlug: string } | { source: "fog"; mapId: string; objectId: string };
type Journal = { id: string; target: Target; startedAt: string; world: World | null; battle: BattleResult; playback: Record<string, unknown>; canSkip: boolean; result: Record<string, unknown> | null; acknowledged: boolean };
const endpoint = "combat-session";
const keyOf = (id: string) => `combat:${id}`;
async function lockPlayer(tx: Tx, playerId: string) {
  await tx.select({ playerId: playerStates.playerId }).from(playerStates).where(eq(playerStates.playerId, playerId)).for("update");
}
async function pendingJournal(tx: Tx, playerId: string) {
  const [row] = await tx.select().from(idempotencyKeys).where(and(eq(idempotencyKeys.playerId, playerId), eq(idempotencyKeys.endpoint, endpoint), sql`${idempotencyKeys.response}->>'acknowledged' = 'false'`)).orderBy(desc(idempotencyKeys.createdAt)).limit(1);
  return row?.response as Journal | undefined;
}
async function wonTarget(tx: Tx, playerId: string, target: Target): Promise<boolean> {
  const [row] = await tx.select({ key: idempotencyKeys.key }).from(idempotencyKeys).where(and(eq(idempotencyKeys.playerId, playerId), eq(idempotencyKeys.endpoint, endpoint), sql`${idempotencyKeys.response}->'target' = ${JSON.stringify(target)}::jsonb`, sql`${idempotencyKeys.response}->'result'->'battle'->>'win' = 'true'`)).limit(1);
  return Boolean(row);
}
function publicSession(j: Journal) {
  return { combatId: j.id, source: j.target.source, target: j.target, startedAt: j.startedAt, battle: j.battle, playback: { ...j.playback, canSkip: j.canSkip }, result: j.result };
}
async function save(tx: Tx, playerId: string, j: Journal) {
  await tx.update(idempotencyKeys).set({ response: j }).where(and(eq(idempotencyKeys.playerId, playerId), eq(idempotencyKeys.key, keyOf(j.id))));
}
export async function startCombat(tx: Tx, world: World, playerId: string, target: Target, now: Date, randomInt: (min: number, max: number) => number) {
  await lockPlayer(tx, playerId);
  const pending = await pendingJournal(tx, playerId);
  // A lost HTTP response or repeated tap returns the same authoritative battle, never a second reward roll.
  if (pending) return publicSession(pending);
  let battle: BattleResult;
  let playback: Record<string, unknown>;
  if (target.source === "stage") {
    const prepared = await challengeStage(tx, world, playerId, target.stageSlug, now, randomInt, { preview: true });
    battle = prepared.battle;
    playback = prepared.playback;
  } else {
    const prepared = await battleFog(tx, world, playerId, target.mapId, { objectId: target.objectId }, now, { preview: true });
    battle = { win: prepared.win, reason: prepared.reason, durationSeconds: prepared.durationSeconds, log: prepared.log };
    playback = prepared.playback;
  }
  const wonBefore = await wonTarget(tx, playerId, target);
  const j: Journal = { id: randomUUID(), target, world, battle, playback, startedAt: now.toISOString(), canSkip: runtimeConfigOf(world.globals.tuning?.battle).skipAfterWin && (Boolean(playback.canSkip) || wonBefore), result: null, acknowledged: false };
  await tx.insert(idempotencyKeys).values({ playerId, key: keyOf(j.id), endpoint, response: j, createdAt: now });
  return publicSession(j);
}
export async function finishCombat(tx: Tx, playerId: string, id: string, mode: FinishMode, now: Date, randomInt: (min: number, max: number) => number) {
  await lockPlayer(tx, playerId);
  const [row] = await tx.select().from(idempotencyKeys).where(and(eq(idempotencyKeys.playerId, playerId), eq(idempotencyKeys.key, keyOf(id)), eq(idempotencyKeys.endpoint, endpoint))).limit(1);
  if (!row) throw new AppError("NOT_FOUND");
  const j = row.response as Journal;
  if (!j.result) {
    const world = j.world;
    if (!world) throw new AppError("INVALID_INPUT", "战斗快照缺失");
    const battle = finishDecision(j.battle, mode, j.canSkip, (now.getTime() - Date.parse(j.startedAt)) / 1000, Math.max(...runtimeConfigOf(world.globals.tuning?.battle).speeds));
    if (j.target.source === "stage") {
      j.result = await challengeStage(tx, world, playerId, j.target.stageSlug, now, randomInt, { resolvedBattle: battle, resume: true });
    } else {
      const resolved = await battleFog(tx, world, playerId, j.target.mapId, { objectId: j.target.objectId }, now, { resolvedBattle: battle });
      j.result = { ...resolved, battle, drops: resolved.gained };
    }
    j.battle = battle;
    j.world = null; // the committed result no longer needs a full content snapshot
    await save(tx, playerId, j);
  }
  return publicSession(j);
}
export async function recoverCombat(tx: Tx, playerId: string, now: Date, randomInt: (min: number, max: number) => number) {
  await lockPlayer(tx, playerId);
  const pending = await pendingJournal(tx, playerId);
  return pending ? finishCombat(tx, playerId, pending.id, "recover", now, randomInt) : null;
}
const startSchema = z.discriminatedUnion("source", [z.object({ source: z.literal("stage"), stageSlug: z.string().min(1).max(128) }), z.object({ source: z.literal("fog"), mapId: z.string().min(1).max(128), objectId: z.string().min(1).max(128) })]);
export async function registerCombatSessionRoutes(app: FastifyInstance, deps: { db: Db; now: () => Date; randomInt: (min: number, max: number) => number }) {
  app.post("/me/combat/start", async request => {
    const target = startSchema.parse(request.body);
    const key = request.headers["idempotency-key"];
    if (typeof key !== "string" || key.length < 8) throw new AppError("IDEMPOTENCY_KEY_REQUIRED");
    return withIdempotency(deps.db, request.actor!.actorId, key, "combat-start", deps.now(), (tx, world) => startCombat(tx, world, request.actor!.actorId, target, deps.now(), deps.randomInt));
  });
  app.get("/me/combat/pending", async request => ({ session: await withTransaction(deps.db, tx => recoverCombat(tx, request.actor!.actorId, deps.now(), deps.randomInt)) }));
  app.post("/me/combat/:id/finish", async request => {
    const { mode } = z.object({ mode: z.enum(["complete", "skip", "retreat"]) }).parse(request.body);
    const id = z.uuid().parse((request.params as { id: string }).id);
    return withTransaction(deps.db, tx => finishCombat(tx, request.actor!.actorId, id, mode, deps.now(), deps.randomInt));
  });
  app.post("/me/combat/:id/ack", async request => {
    const id = z.uuid().parse((request.params as { id: string }).id);
    return withTransaction(deps.db, async tx => {
      await lockPlayer(tx, request.actor!.actorId);
      const [row] = await tx.select().from(idempotencyKeys).where(and(eq(idempotencyKeys.playerId, request.actor!.actorId), eq(idempotencyKeys.key, keyOf(id)), eq(idempotencyKeys.endpoint, endpoint))).limit(1);
      if (!row || !(row.response as Journal).result) throw new AppError("INVALID_INPUT", "战斗还未结算");
      const j = row.response as Journal; j.acknowledged = true; await save(tx, request.actor!.actorId, j);
      return { acknowledged: true };
    });
  });
}
