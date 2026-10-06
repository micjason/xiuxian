import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { readSession } from "../auth/service.js";
import type { Db } from "../operations/record.js";
import { applyRepair, previewRepair } from "./service.js";

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

export async function registerRepairRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.post("/admin/repairs/preview", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    const body = request.body as { name?: string };
    if (!body.name) {
      return reply.code(400).send({ reason: "invalid" });
    }
    return previewRepair(deps.db, body.name);
  });

  app.post("/admin/repairs/apply", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    const body = request.body as { previewId?: string };
    if (!body.previewId) {
      return reply.code(400).send({ reason: "invalid" });
    }
    return applyRepair(deps.db, { id: session.actorId, name: session.actorName }, body.previewId, deps.now());
  });
}
