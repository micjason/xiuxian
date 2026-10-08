import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { readSession } from "../auth/service.js";
import type { Db } from "../operations/record.js";
import { listAnnouncements, listPopupTypes, saveAnnouncement, savePopupType } from "./service.js";

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

export async function registerNoticeRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.get("/admin/popup-types", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    return listPopupTypes(deps.db);
  });

  app.put("/admin/popup-types/:slug", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    const params = request.params as { slug: string };
    const body = request.body as { priority: number; enabled: boolean };
    try {
      await savePopupType(deps.db, params.slug, { priority: Number(body.priority), enabled: Boolean(body.enabled) });
    } catch (cause) {
      return reply.code(400).send({ reason: cause instanceof Error ? cause.message : "invalid" });
    }
    return { ok: true };
  });

  app.get("/admin/announcements", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    return listAnnouncements(deps.db);
  });

  app.post("/admin/announcements", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    const body = request.body as { id?: string; title: string; body: string; enabled: boolean };
    try {
      await saveAnnouncement(deps.db, body, deps.now());
    } catch (cause) {
      return reply.code(400).send({ reason: cause instanceof Error ? cause.message : "invalid" });
    }
    return { ok: true };
  });
}
