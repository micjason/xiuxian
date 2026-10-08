import type { FastifyInstance } from "fastify";
import { listOperations, type Db, type OperationAction } from "./record.js";


export async function registerOperationRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.get("/admin/operations", async (request, reply) => {
    const query = request.query as { name?: string; from?: string; to?: string; action?: string };
    if (!query.from || !query.to) {
      return reply.code(400).send({ reason: "invalid" });
    }
    return listOperations(deps.db, {
      name: query.name || undefined,
      action: query.action ? (query.action as OperationAction) : undefined,
      from: new Date(query.from),
      to: new Date(query.to),
    });
  });
}
