import type { FastifyInstance } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { tryBreakthrough } from "../player/service.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { advanceRealm, challengeStage, equipItem, readState, runSkill, stopSkill, unequipSlot, useItem, withIdempotency } from "./actions.js";

type RandomInt = (min: number, max: number) => number;

function idempotencyKey(header: string | string[] | undefined): string {
  const key = Array.isArray(header) ? header[0] : header;
  if (!key || key.length < 8) {
    throw new AppError("IDEMPOTENCY_KEY_REQUIRED");
  }
  return key;
}

export async function registerLoopRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date; randomInt: RandomInt },
): Promise<void> {
  app.get("/me/state", async (request) => readState(deps.db, request.actor!.actorId, deps.now()));

  app.post("/me/breakthrough", async (request) => {
    const world = await loadCurrentWorld(deps.db);
    if (!world) {
      return tryBreakthrough(deps.db, request.actor!.actorId, deps.now());
    }
    const playerId = request.actor!.actorId;
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "breakthrough", deps.now(), (tx, current) =>
      advanceRealm(tx, current, playerId, deps.now(), deps.randomInt),
    );
  });

  app.post("/me/stages/:slug/challenge", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { slug: string };
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "challenge", deps.now(), (tx, world) =>
      challengeStage(tx, world, playerId, params.slug, deps.now(), deps.randomInt),
    );
  });

  app.post("/me/items/:itemId/equip", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { itemId: string };
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "equip", deps.now(), (tx, world) =>
      equipItem(tx, world, playerId, params.itemId, deps.now()),
    );
  });

  app.post("/me/equipment/:slot/unequip", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { slot: string };
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "unequip", deps.now(), (tx, world) =>
      unequipSlot(tx, world, playerId, params.slot, deps.now()),
    );
  });

  app.post("/me/items/:itemId/use", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { itemId: string };
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "use", deps.now(), (tx, world) =>
      useItem(tx, world, playerId, params.itemId, deps.now()),
    );
  });

  app.post("/me/skills/:slug/run", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { slug: string };
    const body = request.body as { slot?: string };
    if (!body.slot) {
      throw new AppError("INVALID_INPUT");
    }
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "run", deps.now(), (tx, world) =>
      runSkill(tx, world, playerId, params.slug, body.slot!, deps.now()),
    );
  });

  app.post("/me/skills/:slug/stop", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { slug: string };
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "stop", deps.now(), (tx, world) =>
      stopSkill(tx, world, playerId, params.slug, deps.now()),
    );
  });
}
