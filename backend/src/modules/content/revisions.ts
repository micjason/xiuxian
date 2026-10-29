import { sql } from "drizzle-orm";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";

/**
 * 旧表单覆盖保护（乐观并发）。
 * - 版本号 revision = 这一行库里内容（含 updated_at）的 md5。用整行而不是只用 updated_at：
 *   有的表没有 updated_at（弹窗类型），有的保存路径不一定更新 updated_at，整行哈希都能覆盖到。
 * - 后台打开页面时先取版本号（GET /admin/draft/revisions?kind=…），再读数据；保存时带 If-Match: <revision>。
 * - 服务器发现版本号对不上 → 409 STALE_REVISION，附现在的版本号、最后保存时间和人；后台弹窗让用户选
 *   重新读取 / 查看差异 / 仍然覆盖（= 带上新版本号再发一次）。
 * - 不带 If-Match 的请求照旧放行（脚本、测试、旧页面），后台网页的保存全部会带。
 * - 保存成功的响应头 X-Revision 是新版本号，页面接着改再存不会误报冲突。
 */
export type RevisionKind = "stage" | "globals" | "item" | "skill" | "skillCategory" | "realm" | "chapter" | "gearSet" | "puppet" | "popupType";

const TABLES: Record<RevisionKind, { table: string; key: string; numeric?: boolean }> = {
  stage: { table: "content_stages", key: "slug" },
  globals: { table: "content_globals", key: "id", numeric: true },
  item: { table: "content_items", key: "slug" },
  skill: { table: "content_skills", key: "slug" },
  skillCategory: { table: "content_skill_categories", key: "slug" },
  realm: { table: "content_realms", key: "sort_order", numeric: true },
  chapter: { table: "content_chapters", key: "slug" },
  gearSet: { table: "content_gear_sets", key: "slug" },
  puppet: { table: "content_trial_puppets", key: "slug" },
  popupType: { table: "popup_types", key: "slug" },
};

type Guard = { kind: RevisionKind; key: (request: FastifyRequest) => string | number; after?: (request: FastifyRequest) => string | number };
const id = (name: string) => (request: FastifyRequest) => String((request.params as Record<string, string>)[name] ?? "");
const GLOBALS: Guard = { kind: "globals", key: () => 1 };

/** 受保护的保存接口（路径去掉 /api/v1 前缀后匹配）。 */
export const GUARDED: Record<string, Guard> = {
  "PUT /admin/draft/stages/:id": { kind: "stage", key: id("id") },
  "PUT /admin/draft/config-overview": GLOBALS,
  "PUT /admin/draft/tuning": GLOBALS,
  "PUT /admin/draft/rules": GLOBALS,
  "PUT /admin/draft/enhance": GLOBALS,
  "PUT /admin/draft/dongfu": GLOBALS,
  "PUT /admin/draft/boss-rules": GLOBALS,
  "PUT /admin/draft/gear-params": GLOBALS,
  "PUT /admin/draft/gear-qualities": GLOBALS,
  "PUT /admin/draft/gear/:id": { kind: "item", key: id("id") },
  "PUT /admin/draft/gear/manual/:id": { kind: "item", key: id("id") },
  "PUT /admin/draft/items/:id": { kind: "item", key: id("id") },
  "PUT /admin/draft/gear-sets/:id": { kind: "gearSet", key: id("id") },
  "PUT /admin/draft/skills/:id": { kind: "skill", key: id("id") },
  "PUT /admin/draft/skill-categories/:id": { kind: "skillCategory", key: id("id") },
  "PUT /admin/draft/realms/:code": {
    kind: "realm",
    key: (request) => Number((request.params as { code: string }).code),
    // 改了境界编号时，新版本号按新编号取
    after: (request) => Number((request.body as { code?: unknown } | null)?.code ?? (request.params as { code: string }).code),
  },
  "PUT /admin/draft/chapters/:id": { kind: "chapter", key: id("id") },
  "PUT /admin/draft/puppets/:id": { kind: "puppet", key: id("id") },
  "PUT /admin/popup-types/:slug": { kind: "popupType", key: id("slug") },
};

export function isRevisionKind(value: unknown): value is RevisionKind {
  return typeof value === "string" && value in TABLES;
}

function keyValue(kind: RevisionKind, key: string | number): string | number | null {
  if (!TABLES[kind].numeric) return String(key);
  const number = Number(key);
  return Number.isFinite(number) ? number : null;
}

/** 一行的版本号；行不存在返回 null。 */
export async function rowRevision(db: Db, kind: RevisionKind, key: string | number): Promise<{ revision: string; updatedAt: string | null; updatedBy: string | null } | null> {
  const { table, key: column } = TABLES[kind];
  const value = keyValue(kind, key);
  if (value === null) return null;
  const rows = (await db.execute(sql`
    select md5(t::text) as revision,
           (to_jsonb(t) ->> 'updated_at') as updated_at,
           (select a.username from admins a where a.id::text = (to_jsonb(t) ->> 'updated_by')) as updated_by
      from ${sql.identifier(table)} t
     where ${sql.identifier(column)} = ${value}
     limit 1`)) as unknown as { revision: string; updated_at: string | null; updated_by: string | null }[];
  const row = rows[0];
  return row ? { revision: row.revision, updatedAt: row.updated_at, updatedBy: row.updated_by } : null;
}

/** 一类内容的全部版本号：{ 主键: 版本号 } */
export async function listRevisions(db: Db, kind: RevisionKind): Promise<Record<string, string>> {
  const { table, key: column } = TABLES[kind];
  const rows = (await db.execute(sql`select ${sql.identifier(column)}::text as key, md5(t::text) as revision from ${sql.identifier(table)} t`)) as unknown as { key: string; revision: string }[];
  return Object.fromEntries(rows.map((row) => [row.key, row.revision]));
}

function guardOf(method: string, url: string): Guard | undefined {
  const path = url.startsWith("/api/v1/") ? url.slice("/api/v1".length) : url;
  return GUARDED[`${method} ${path}`];
}

function ifMatch(request: FastifyRequest): string | null {
  const raw = request.headers["if-match"];
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (!value) return null;
  return value.trim().replace(/^W\//, "").replace(/^"|"$/g, "") || null;
}

/** 在 authPlugin 之后调用：给受保护的保存接口加版本检查（在 requireAdmin 之后跑）和响应头 X-Revision。 */
export function registerRevisionGuards(app: FastifyInstance, db: Db): void {
  app.addHook("onRoute", (route) => {
    const methods = Array.isArray(route.method) ? route.method : [route.method];
    const guard = methods.map((method) => guardOf(String(method), route.url)).find(Boolean);
    if (!guard) return;
    const check = async (request: FastifyRequest): Promise<void> => {
      const expected = ifMatch(request);
      if (!expected) return;
      const current = await rowRevision(db, guard.kind, guard.key(request));
      if (!current || current.revision === expected) return;
      throw new AppError("STALE_REVISION", undefined, { kind: guard.kind, id: String(guard.key(request)), revision: current.revision, updatedAt: current.updatedAt, updatedBy: current.updatedBy });
    };
    const stamp = async (request: FastifyRequest, reply: FastifyReply, payload: unknown): Promise<unknown> => {
      if (reply.statusCode < 300) {
        const fresh = await rowRevision(db, guard.kind, (guard.after ?? guard.key)(request)).catch(() => null);
        if (fresh) reply.header("x-revision", fresh.revision);
      }
      return payload;
    };
    const pre = route.preHandler;
    route.preHandler = [...(Array.isArray(pre) ? pre : pre ? [pre] : []), check];
    const send = route.onSend;
    route.onSend = [...(Array.isArray(send) ? send : send ? [send] : []), stamp];
  });
}

export async function registerRevisionRoutes(app: FastifyInstance, deps: { db: Db }): Promise<void> {
  app.get("/admin/draft/revisions", async (request) => {
    const kind = (request.query as { kind?: unknown }).kind;
    if (!isRevisionKind(kind)) {
      throw new AppError("INVALID_INPUT", "kind 不正确");
    }
    return { kind, revisions: await listRevisions(deps.db, kind) };
  });
}
