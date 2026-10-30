import type { FastifyInstance } from "fastify";
import { AppError } from "../../shared/errors.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import type { Db } from "../operations/record.js";
import { runProgressionSimFromWorld } from "./progression.js";

export async function registerSimRoutes(app: FastifyInstance, deps: { db: Db }): Promise<void> {
  app.post("/admin/sim/progression", async (request) => {
    const body = (request.body ?? {}) as { targetRealmId?: unknown };
    const targetRealmId = typeof body.targetRealmId === "string" ? body.targetRealmId : undefined;
    if (body.targetRealmId !== undefined && targetRealmId === undefined) {
      throw new AppError("INVALID_INPUT", "targetRealmId 必须是字符串");
    }
    const world = await loadCurrentWorld(deps.db);
    return runProgressionSimFromWorld(world, { targetRealmId });
  });
}
