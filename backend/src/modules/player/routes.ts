import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { readSession } from "../auth/service.js";
import type { Db } from "../operations/record.js";
import { dismissNotice } from "../notices/service.js";
import { listPlayers, openProgress, tryBreakthrough } from "./service.js";

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

export async function registerPlayerRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.get("/admin/players", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    return listPlayers(deps.db);
  });

  app.get("/me", async (request, reply) => {
    const session = await requirePlayer(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    const query = request.query as { versionCode?: string };
    const parsed = Number(query.versionCode);
    const versionCode = Number.isFinite(parsed) ? parsed : 0;
    return openProgress(deps.db, session.actorId, deps.now(), versionCode);
  });

  app.post("/me/notices/:id/dismiss", async (request, reply) => {
    const session = await requirePlayer(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    const params = request.params as { id: string };
    await dismissNotice(deps.db, session.actorId, params.id, deps.now());
    return { ok: true };
  });

  app.post("/me/breakthrough", async (request, reply) => {
    const session = await requirePlayer(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    return tryBreakthrough(deps.db, session.actorId, deps.now());
  });
}
