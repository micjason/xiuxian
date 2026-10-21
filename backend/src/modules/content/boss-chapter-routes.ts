/**
 * 第三批后台接口（首领规则、章节、立绘清单）。由 registerDraftRoutes 调用，路径都在 /admin 下（要管理员登录）。
 * - GET/POST/PUT/DELETE /admin/draft/chapters[/:id]
 * - GET/PUT /admin/draft/boss-rules
 * - POST /admin/draft/stages/:id/reset-boss-rule   body: { keys?: string[] }
 * - GET /admin/draft/art-keys
 */
import type { FastifyInstance } from "fastify";
import type { Db } from "../operations/record.js";
import { artKeyCatalog } from "./art-keys.js";
import { readBossRules, resetStageBossRule, saveBossRules } from "./boss-rules-admin.js";
import { createChapter, deleteChapter, listChapters, updateChapter } from "./chapters.js";

export async function registerBossChapterRoutes(app: FastifyInstance, deps: { db: Db }): Promise<void> {
  app.get("/admin/draft/chapters", async () => listChapters(deps.db));
  app.post("/admin/draft/chapters", async (request) => createChapter(deps.db, (request.body ?? {}) as never, request.actor?.actorId ?? null));
  app.put("/admin/draft/chapters/:id", async (request) =>
    updateChapter(deps.db, (request.params as { id: string }).id, (request.body ?? {}) as never, request.actor?.actorId ?? null),
  );
  app.delete("/admin/draft/chapters/:id", async (request) => deleteChapter(deps.db, (request.params as { id: string }).id));
  app.get("/admin/draft/boss-rules", async () => readBossRules(deps.db));
  app.put("/admin/draft/boss-rules", async (request) => saveBossRules(deps.db, (request.body ?? {}) as never, request.actor?.actorId ?? null));
  app.post("/admin/draft/stages/:id/reset-boss-rule", async (request) =>
    resetStageBossRule(deps.db, (request.params as { id: string }).id, (request.body as { keys?: unknown } | undefined)?.keys, request.actor?.actorId ?? null),
  );
  app.get("/admin/draft/art-keys", async () => artKeyCatalog());
}
