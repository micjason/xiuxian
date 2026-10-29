import type { FastifyInstance } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { withIdempotency } from "../loop/actions.js";
import { allocateServants, claimAlchemy, claimGarden, plantSeed, startAlchemy, upgradeFacility } from "./actions.js";

function idempotencyKey(header: string | string[] | undefined): string {
  const key = Array.isArray(header) ? header[0] : header;
  if (!key || key.length < 8) {
    throw new AppError("IDEMPOTENCY_KEY_REQUIRED");
  }
  return key;
}

export async function registerDongfuRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.post("/me/dongfu/garden/plant", async (request) => {
    const playerId = request.actor!.actorId;
    const body = (request.body ?? {}) as { slot?: unknown; seedSlug?: unknown };
    if (!Number.isInteger(body.slot) || typeof body.seedSlug !== "string" || !body.seedSlug) {
      throw new AppError("INVALID_INPUT", "请选择地块和种子");
    }
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "dongfu-plant", deps.now(), (tx, world) =>
      plantSeed(tx, world, playerId, { slot: body.slot as number, seedSlug: body.seedSlug as string }, deps.now()),
    );
  });

  app.post("/me/dongfu/garden/claim", async (request) => {
    const playerId = request.actor!.actorId;
    const body = (request.body ?? {}) as { slot?: unknown };
    if (body.slot !== undefined && !Number.isInteger(body.slot)) {
      throw new AppError("INVALID_INPUT", "地块编号不正确");
    }
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "dongfu-garden-claim", deps.now(), (tx, world) =>
      claimGarden(tx, world, playerId, { slot: body.slot as number | undefined }, deps.now()),
    );
  });

  app.post("/me/dongfu/alchemy/start", async (request) => {
    const playerId = request.actor!.actorId;
    const body = (request.body ?? {}) as { recipeSlug?: unknown };
    if (typeof body.recipeSlug !== "string" || !body.recipeSlug) {
      throw new AppError("INVALID_INPUT", "请选择配方");
    }
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "dongfu-alchemy-start", deps.now(), (tx, world) =>
      startAlchemy(tx, world, playerId, { recipeSlug: body.recipeSlug as string }, deps.now()),
    );
  });

  app.post("/me/dongfu/allocate", async (request) => {
    const playerId = request.actor!.actorId;
    const body = (request.body ?? {}) as { garden?: unknown; alchemy?: unknown };
    if (!Number.isInteger(body.garden) || !Number.isInteger(body.alchemy)) {
      throw new AppError("INVALID_INPUT", "请填写药园和炼丹的灵仆数量");
    }
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "dongfu-allocate", deps.now(), (tx, world) =>
      allocateServants(tx, world, playerId, { garden: body.garden as number, alchemy: body.alchemy as number }, deps.now()),
    );
  });

  app.post("/me/dongfu/upgrade", async (request) => {
    const playerId = request.actor!.actorId;
    const body = (request.body ?? {}) as { facility?: unknown };
    if (body.facility !== "garden" && body.facility !== "alchemy") {
      throw new AppError("INVALID_INPUT", "请选择要升级的药园或炼丹");
    }
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "dongfu-upgrade", deps.now(), (tx, world) =>
      upgradeFacility(tx, world, playerId, body.facility as "garden" | "alchemy", deps.now()),
    );
  });

  app.post("/me/dongfu/alchemy/claim", async (request) => {
    const playerId = request.actor!.actorId;
    const body = (request.body ?? {}) as { jobId?: unknown };
    if (body.jobId !== undefined && (typeof body.jobId !== "string" || !body.jobId)) {
      throw new AppError("INVALID_INPUT", "炼丹任务编号不正确");
    }
    return withIdempotency(deps.db, playerId, idempotencyKey(request.headers["idempotency-key"]), "dongfu-alchemy-claim", deps.now(), (tx, world) =>
      claimAlchemy(tx, world, playerId, { jobId: body.jobId as string | undefined }, deps.now()),
    );
  });
}
