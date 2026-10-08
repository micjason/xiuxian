import type { FastifyInstance } from "fastify";
import { contentRealms } from "../../db/schema.js";
import type { Db } from "../operations/record.js";
import { AppError } from "../../shared/errors.js";
import {
  deleteDraftItem,
  deleteDraftRealm,
  deleteDraftSkill,
  readDraftGlobals,
  saveDraftDropTable,
  saveDraftGlobals,
  saveDraftItem,
  saveDraftSkill,
  saveDraftStage,
} from "./draft-service.js";
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
    return deleteDraftRealm(deps.db, params.slug);
  });

  app.get("/admin/draft/globals", async () => readDraftGlobals(deps.db));
  app.put("/admin/draft/globals", async (request) =>
    saveDraftGlobals(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.post("/admin/draft/items", async (request) =>
    saveDraftItem(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.delete("/admin/draft/items/:slug", async (request) => deleteDraftItem(deps.db, (request.params as { slug: string }).slug));
  app.post("/admin/draft/skills", async (request) =>
    saveDraftSkill(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.delete("/admin/draft/skills/:slug", async (request) =>
    deleteDraftSkill(deps.db, (request.params as { slug: string }).slug),
  );
  app.post("/admin/draft/drop-tables", async (request) =>
    saveDraftDropTable(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.post("/admin/draft/stages", async (request) =>
    saveDraftStage(deps.db, request.body as never, request.actor?.actorId ?? null),
  );

  app.post("/admin/draft/publish", async (request) => {
    const body = (request.body ?? {}) as { note?: string };
    return publishSnapshot(deps.db, body.note ?? "", request.actor?.actorId ?? null, deps.now());
  });
}
