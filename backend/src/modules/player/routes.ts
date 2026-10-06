import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { readSession } from "../auth/service.js";
import type { Db } from "../operations/record.js";
import { openProgress, tryBreakthrough } from "./service.js";

async function requirePlayer(db: Db, request: FastifyRequest, reply: FastifyReply, now: Date) {
  const header = request.headers.authorization ?? "";
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
  const session = await readSession(db, token, now);
  if (!session || session.actorType !== "player") {
    reply.code(401).send({ reason: "player required" });
    return null;
  }
  return session;
}

export async function registerPlayerRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.get("/me", async (request, reply) => {
    const session = await requirePlayer(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    return openProgress(deps.db, session.actorId, deps.now());
  });

  app.post("/me/breakthrough", async (request, reply) => {
    const session = await requirePlayer(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    return tryBreakthrough(deps.db, session.actorId, deps.now());
  });
}
