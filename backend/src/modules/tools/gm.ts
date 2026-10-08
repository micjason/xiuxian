import type { FastifyInstance } from "fastify";
import type { Db } from "../operations/record.js";

export async function registerGmRoutes(app: FastifyInstance, _deps: { db: Db; now: () => Date }): Promise<void> {
  app.post("/admin/gm/players/:id/reset", async () => ({ ok: true }));
}
