import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { readSession } from "../auth/service.js";
import type { Db } from "../operations/record.js";
import { publish, saveItem, saveRealm, saveSkill, type ItemInput, type RealmInput, type SkillInput } from "./service.js";

async function requireAdmin(
  db: Db,
  request: FastifyRequest,
  reply: FastifyReply,
  now: Date,
) {
  const header = request.headers.authorization ?? "";
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
  const session = await readSession(db, token, now);
  if (!session || session.actorType !== "admin") {
    reply.code(403).send({ reason: "admin required" });
    return null;
  }
  return session;
}

export async function registerContentRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.put("/admin/content/realms/:slug", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    const body = request.body as Omit<RealmInput, "slug">;
    const params = request.params as { slug: string };
    await saveRealm(deps.db, session.actorId, { ...body, slug: params.slug });
    return { ok: true };
  });

  app.put("/admin/content/skills/:slug", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    const body = request.body as Omit<SkillInput, "slug">;
    const params = request.params as { slug: string };
    await saveSkill(deps.db, { ...body, slug: params.slug });
    return { ok: true };
  });

  app.put("/admin/content/items/:slug", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    const body = request.body as Omit<ItemInput, "slug">;
    const params = request.params as { slug: string };
    await saveItem(deps.db, { ...body, slug: params.slug });
    return { ok: true };
  });

  app.post("/admin/content/publish", async (request, reply) => {
    const session = await requireAdmin(deps.db, request, reply, deps.now());
    if (!session) {
      return;
    }
    return publish(deps.db, { id: session.actorId, name: session.actorName, actorType: "admin" }, deps.now());
  });
}
