import type { FastifyInstance } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { withIdempotency } from "../loop/actions.js";
import { battleFog, interactFog, moveFog, readFogState } from "./actions.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { withTransaction } from "../../db/tx.js";

function idempotencyKey(header: string | string[] | undefined): string {
  const key = Array.isArray(header) ? header[0] : header;
  if (!key || key.length < 8) throw new AppError("IDEMPOTENCY_KEY_REQUIRED");
  return key;
}

function xyBody(body: { x?: unknown; y?: unknown; r?: unknown; c?: unknown }): { x: number; y: number } {
  const x = body.x !== undefined ? body.x : body.c;
  const y = body.y !== undefined ? body.y : body.r;
  if (!Number.isInteger(x) || !Number.isInteger(y)) {
    throw new AppError("INVALID_INPUT", "请选择目标格子");
  }
  return { x: x as number, y: y as number };
}

export async function registerFogRoutes(app: FastifyInstance, deps: { db: Db; now: () => Date }): Promise<void> {
  app.get("/me/fog", async (request) => {
    const playerId = request.actor!.actorId;
    const world = await loadCurrentWorld(deps.db);
    if (!world) throw new AppError("CONTENT_NOT_PUBLISHED");
    return withTransaction(deps.db, async (tx) => readFogState(tx, world, playerId, undefined, deps.now()));
  });

  app.get("/me/fog/:mapId", async (request) => {
    const playerId = request.actor!.actorId;
    const mapId = (request.params as { mapId?: string }).mapId;
    const world = await loadCurrentWorld(deps.db);
    if (!world) throw new AppError("CONTENT_NOT_PUBLISHED");
    return withTransaction(deps.db, async (tx) => readFogState(tx, world, playerId, mapId, deps.now()));
  });

  app.post("/me/fog/:mapId/move", async (request) => {
    const playerId = request.actor!.actorId;
    const mapId = (request.params as { mapId: string }).mapId;
    const body = (request.body ?? {}) as { x?: unknown; y?: unknown; r?: unknown; c?: unknown };
    const pos = xyBody(body);
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "fog-move", deps.now(), (tx, world) =>
      moveFog(tx, world, playerId, mapId, pos, deps.now()),
    );
  });

  app.post("/me/fog/:mapId/interact", async (request) => {
    const playerId = request.actor!.actorId;
    const mapId = (request.params as { mapId: string }).mapId;
    const body = (request.body ?? {}) as { objectId?: unknown; optionId?: unknown };
    if (typeof body.objectId !== "string" || !body.objectId) throw new AppError("INVALID_INPUT", "请选择物件");
    const optionId = typeof body.optionId === "string" ? body.optionId : undefined;
    return withIdempotency(
      deps.db,
      playerId,
      idempotencyKey(request.headers["idempotency-key"]),
      "fog-interact",
      deps.now(),
      (tx, world) => interactFog(tx, world, playerId, mapId, { objectId: body.objectId as string, optionId }, deps.now()),
    );
  });

  app.post("/me/fog/:mapId/battle", async (request) => {
    const playerId = request.actor!.actorId;
    const mapId = (request.params as { mapId: string }).mapId;
    const body = (request.body ?? {}) as { objectId?: unknown };
    if (typeof body.objectId !== "string" || !body.objectId) throw new AppError("INVALID_INPUT", "请选择怪物");
    return withIdempotency(
      deps.db,
      playerId,
      idempotencyKey(request.headers["idempotency-key"]),
      "fog-battle",
      deps.now(),
      (tx, world) => battleFog(tx, world, playerId, mapId, { objectId: body.objectId as string }, deps.now()),
    );
  });
}
