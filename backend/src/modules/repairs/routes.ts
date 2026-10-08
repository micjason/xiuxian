import type { FastifyInstance } from "fastify";
import type { Db } from "../operations/record.js";
import { applyRepair, previewRepair } from "./service.js";


export async function registerRepairRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.post("/admin/repairs/preview", async (request, reply) => {
    const body = request.body as { name?: string };
    if (!body.name) {
      return reply.code(400).send({ reason: "invalid" });
    }
    return previewRepair(deps.db, body.name);
  });

  app.post("/admin/repairs/apply", async (request, reply) => {
    const body = request.body as { previewId?: string };
    if (!body.previewId) {
      return reply.code(400).send({ reason: "invalid" });
    }
    return applyRepair(deps.db, { id: request.actor!.actorId, name: request.actor!.actorName }, body.previewId, deps.now());
  });
}
