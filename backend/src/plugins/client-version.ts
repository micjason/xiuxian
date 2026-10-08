import type { FastifyInstance } from "fastify";
import { loadCurrentWorld } from "../modules/content/snapshot.js";
import type { Db } from "../modules/operations/record.js";
import { AppError } from "../shared/errors.js";

export function clientVersionPlugin(db: Db) {
  return async function registerClientVersion(app: FastifyInstance) {
    app.addHook("onRoute", (route) => {
      const url = route.url.split("?")[0] ?? route.url;
      if (!/(^|\/)me(\/|$)/.test(url)) {
        return;
      }
      const current = route.preHandler;
      const list = Array.isArray(current) ? current : current ? [current] : [];
      route.preHandler = [
        ...list,
        async (request) => {
          const header = request.headers["x-client-version"];
          const raw = Array.isArray(header) ? header[0] : header;
          const versionCode = raw == null || raw === "" ? 0 : Number(raw);
          const world = await loadCurrentWorld(db);
          const minimum = world?.globals.minClientVersionCode ?? 0;
          if (!Number.isFinite(versionCode) || versionCode < minimum) {
            throw new AppError("CLIENT_TOO_OLD");
          }
        },
      ];
    });
  };
}
