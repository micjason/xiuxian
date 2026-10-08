import type { FastifyInstance } from "fastify";
import type { Db } from "../operations/record.js";
import { dismissNotice } from "../notices/service.js";
import { listPlayers, openProgress, tryBreakthrough } from "./service.js";



export async function registerPlayerRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.get("/admin/players", async (request, reply) => {
    return listPlayers(deps.db);
  });

  app.get("/me", async (request, reply) => {
    const query = request.query as { versionCode?: string };
    const parsed = Number(query.versionCode);
    const versionCode = Number.isFinite(parsed) ? parsed : 0;
    return openProgress(deps.db, request.actor!.actorId, deps.now(), versionCode);
  });

  app.post("/me/notices/:id/dismiss", async (request, reply) => {
    const params = request.params as { id: string };
    await dismissNotice(deps.db, request.actor!.actorId, params.id, deps.now());
    return { ok: true };
  });

  app.post("/me/breakthrough", async (request, reply) => {
    return tryBreakthrough(deps.db, request.actor!.actorId, deps.now());
  });
}
