import type { FastifyInstance } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { listAnnouncements, listPopupTypes, saveAnnouncement, savePopupType } from "./service.js";


export async function registerNoticeRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.get("/admin/popup-types", async (request, reply) => {
    return listPopupTypes(deps.db);
  });

  app.put("/admin/popup-types/:slug", async (request, reply) => {
    const params = request.params as { slug: string };
    const body = request.body as { priority: number; enabled: boolean };
    try {
      await savePopupType(deps.db, params.slug, { priority: Number(body.priority), enabled: Boolean(body.enabled) });
    } catch (cause) {
      throw new AppError("INVALID_INPUT", cause instanceof Error ? cause.message : undefined);
    }
    return { ok: true };
  });

  app.get("/admin/announcements", async (request, reply) => {
    return listAnnouncements(deps.db);
  });

  app.post("/admin/announcements", async (request, reply) => {
    const body = request.body as { id?: string; title: string; body: string; enabled: boolean };
    try {
      await saveAnnouncement(deps.db, body, deps.now());
    } catch (cause) {
      throw new AppError("INVALID_INPUT", cause instanceof Error ? cause.message : undefined);
    }
    return { ok: true };
  });
}
