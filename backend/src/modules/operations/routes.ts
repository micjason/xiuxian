import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { readSession } from "../auth/service.js";
import { listOperations, type Db, type OperationAction } from "./record.js";

async function requireAdmin(db: Db, request: FastifyRequest, reply: FastifyReply, now: Date) {
  const header = request.headers.authorization ?? "";
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
  const session = await readSession(db, token, now);
  if (!session || session.actorType !== "admin") {
    reply.code(403).send({ reason: "admin required" });
    return null;
  }
  return session;
}

export async function registerOperationRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.get("/admin/operations", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
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
