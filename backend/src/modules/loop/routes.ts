import type { FastifyInstance } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { tryBreakthrough } from "../player/service.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { setWaveRandom } from "./waves.js";
import { advanceRealm, challengeStage, breakthroughItem, decomposeItem, enhanceItem, equipItem, readState, runSkill, setAutoDecompose, setIdleStage, stopSkill, unequipItem, unequipSlot, useItem, withIdempotency } from "./actions.js";

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
  setWaveRandom(deps.randomInt);
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
      challengeStage(tx, world, playerId, params.slug, deps.now(), deps.randomInt, {
        ultTaps: (request.body as { ultTaps?: unknown } | undefined)?.ultTaps,
        ultWaits: (request.body as { ultWaits?: unknown } | undefined)?.ultWaits,
      }),
    );
  });

  app.post("/me/items/:itemId/equip", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { itemId: string };
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "equip", deps.now(), (tx, world) =>
      equipItem(tx, world, playerId, params.itemId, deps.now()),
    );
  });

  app.post("/me/items/:itemId/unequip", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { itemId: string };
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "unequip-item", deps.now(), (tx, world) =>
      unequipItem(tx, world, playerId, params.itemId, deps.now()),
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

  app.post("/me/items/:itemId/decompose", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { itemId: string };
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "decompose", deps.now(), (tx, world) =>
      decomposeItem(tx, world, playerId, params.itemId, deps.now()),
    );
  });

  app.post("/me/items/:itemId/enhance", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { itemId: string };
    const body = (request.body ?? {}) as { toMax?: unknown };
    if (body.toMax !== undefined && typeof body.toMax !== "boolean") {
      throw new AppError("INVALID_INPUT", "toMax 要填 true 或 false");
    }
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "enhance", deps.now(), (tx, world) =>
      enhanceItem(tx, world, playerId, params.itemId, deps.now(), { toMax: body.toMax === true }),
    );
  });

  app.post("/me/items/:itemId/breakthrough", async (request) => {
    const playerId = request.actor!.actorId;
    const params = request.params as { itemId: string };
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "breakthrough", deps.now(), (tx, world) =>
      breakthroughItem(tx, world, playerId, params.itemId, deps.now()),
    );
  });

  app.post("/me/auto-decompose", async (request) => {
    const playerId = request.actor!.actorId;
    const body = request.body as { enabled?: boolean };
    if (typeof body.enabled !== "boolean") {
      throw new AppError("INVALID_INPUT", "请选择是否自动分解");
    }
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "auto-decompose", deps.now(), (tx, world) =>
      setAutoDecompose(tx, world, playerId, body.enabled === true, deps.now()),
    );
  });

  app.post("/me/idle-stage", async (request) => {
    const playerId = request.actor!.actorId;
    const body = (request.body ?? {}) as { stageSlug?: unknown };
    if (body.stageSlug !== null && typeof body.stageSlug !== "string") {
      throw new AppError("INVALID_INPUT", "请选择关卡");
    }
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "idle-stage", deps.now(), (tx, world) =>
      setIdleStage(tx, world, playerId, body.stageSlug as string | null, deps.now()),
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
