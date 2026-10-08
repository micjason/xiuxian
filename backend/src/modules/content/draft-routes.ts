import type { FastifyInstance } from "fastify";
import { eq } from "drizzle-orm";
import { contentRealms } from "../../db/schema.js";
import type { Db } from "../operations/record.js";
import { AppError } from "../../shared/errors.js";
import { publishSnapshot } from "./snapshot.js";

const SLUG = /^[a-z][a-z0-9_]{1,47}$/;

export async function registerDraftRoutes(app: FastifyInstance, deps: { db: Db; now: () => Date }): Promise<void> {
  app.get("/admin/draft/realms", async () => deps.db.select().from(contentRealms));

  app.post("/admin/draft/realms", async (request) => {
    const body = request.body as {
      slug?: string;
      displayName?: string;
      sortOrder?: number;
    };
    if (!body.slug || !SLUG.test(body.slug) || !body.displayName) {
      throw new AppError("INVALID_INPUT", "境界编号或名称不正确");
    }
    await deps.db.insert(contentRealms).values({
      slug: body.slug,
      displayName: body.displayName,
      sortOrder: body.sortOrder ?? 0,
      nextRealmSlug: null,
    });
    return { ok: true };
  });

  app.delete("/admin/draft/realms/:slug", async (request) => {
    const params = request.params as { slug: string };
    const { contentKnownSlugs } = await import("../../db/schema.js");
    const [known] = await deps.db
      .select()
      .from(contentKnownSlugs)
      .where(eq(contentKnownSlugs.slug, params.slug))
      .limit(1);
    if (known) {
      throw new AppError("SLUG_PUBLISHED");
    }
    await deps.db.delete(contentRealms).where(eq(contentRealms.slug, params.slug));
    return { ok: true };
  });

  app.post("/admin/draft/publish", async (request) => {
    const body = (request.body ?? {}) as { note?: string };
    return publishSnapshot(deps.db, body.note ?? "", request.actor?.actorId ?? null, deps.now());
  });
}
