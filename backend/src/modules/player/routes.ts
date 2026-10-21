import type { FastifyInstance } from "fastify";
import type { Db } from "../operations/record.js";
import { dismissNotice } from "../notices/service.js";
import { listPlayers, openProgress, resetPlayer } from "./service.js";
import { adminGrant, listGrants, searchGrantPlayers } from "./grant-admin.js";

export async function registerPlayerRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.addHook("onRoute", (route) => {
    if (route.url !== "/me" && !route.url.startsWith("/me/")) {
      return;
    }
    route.config = {
      ...route.config,
      rateLimit: {
        max: process.env.VITEST ? 1000 : 5,
        timeWindow: "1 second",
        keyGenerator: (request) => request.headers.authorization ?? request.ip,
      },
    };
  });

  app.get("/admin/players", async (request, reply) => {
    return listPlayers(deps.db);
  });

  // 装备补发（ADMIN_SPEC §14）
  app.get("/admin/grants/players", async (request) => searchGrantPlayers(deps.db, String((request.query as { q?: string }).q ?? "")));
  app.post("/admin/grants", async (request) => adminGrant(deps.db, (request.body ?? {}) as never, request.actor!));
  app.get("/admin/grants", async (request) => listGrants(deps.db, request.query as never));

  app.post("/admin/players/:username/reset", async (request) => {
    const params = request.params as { username: string };
    return resetPlayer(deps.db, params.username, deps.now());
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

}
