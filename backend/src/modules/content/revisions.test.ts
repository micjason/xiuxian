import { describe, expect, it } from "vitest";
import { buildApp } from "../../app.js";
import { testAdmin } from "../../test/admin.js";
import { withDb } from "../../test/db.js";
import { applyPrototypeV12 } from "./prototype-v12.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

async function boot(db: TestDb) {
  await applyPrototypeV12(db);
  await testAdmin(db, "rev_admin");
  const app = await buildApp(db, () => new Date("2026-10-21T12:00:00.000Z"));
  const login = await app.inject({ method: "POST", url: "/admin/auth/login", payload: { username: "rev_admin", password: "admin-secret" } });
  const admin = { authorization: `Bearer ${login.json().token as string}` };
  const revisions = async (kind: string) => (await app.inject({ method: "GET", url: `/admin/draft/revisions?kind=${kind}`, headers: admin })).json().revisions as Record<string, string>;
  return { app, admin, revisions };
}

function stageBody(row: Record<string, unknown>, patch: Record<string, unknown> = {}) {
  const { displayName, realmCode, chapterSlug, sortOrder, recommendedPower, bosses, monsters, monsterDrop, designatedDrops } = row;
  return { displayName, realmCode, chapterSlug, sortOrder, recommendedPower, bosses, monsters, monsterDrop, designatedDrops, ...patch };
}

describe("旧表单覆盖保护（If-Match / 409 STALE_REVISION）", { timeout: 30_000 }, () => {
  it("stage: second stale save gets 409 with latest revision; resending with that revision (仍然覆盖) succeeds", async () => {
    await withDb(async (db) => {
      const { app, admin, revisions } = await boot(db);
      const opened = (await revisions("stage")).zhuji_2!;
      expect(opened).toMatch(/^[0-9a-f]{32}$/);
      const row = ((await app.inject({ method: "GET", url: "/admin/draft/stages", headers: admin })).json() as Record<string, unknown>[]).find((stage) => stage.id === "zhuji_2")!;

      // A 窗口保存（带打开时的版本号）→ 成功，响应头给出新版本号
      const first = await app.inject({ method: "PUT", url: "/admin/draft/stages/zhuji_2", headers: { ...admin, "if-match": opened }, payload: stageBody(row, { displayName: "幽冥古道·二A" }) });
      expect(first.statusCode).toBe(200);
      const afterFirst = first.headers["x-revision"] as string;
      expect(afterFirst).toMatch(/^[0-9a-f]{32}$/);
      expect(afterFirst).not.toBe(opened);
      expect((await revisions("stage")).zhuji_2).toBe(afterFirst);

      // B 窗口还拿着旧版本号 → 409，不写库
      const stale = await app.inject({ method: "PUT", url: "/admin/draft/stages/zhuji_2", headers: { ...admin, "if-match": opened }, payload: stageBody(row, { displayName: "幽冥古道·二B" }) });
      expect(stale.statusCode).toBe(409);
      const error = stale.json().error;
      expect(error.code).toBe("STALE_REVISION");
      expect(error.details).toMatchObject({ kind: "stage", id: "zhuji_2", revision: afterFirst, updatedBy: "rev_admin" });
      expect(error.details.updatedAt).toBeTruthy();
      const list = (await app.inject({ method: "GET", url: "/admin/draft/stages", headers: admin })).json() as { id: string; displayName: string }[];
      expect(list.find((stage) => stage.id === "zhuji_2")!.displayName).toBe("幽冥古道·二A");

      // 仍然覆盖 = 带 409 给的最新版本号再发一次
      const forced = await app.inject({ method: "PUT", url: "/admin/draft/stages/zhuji_2", headers: { ...admin, "if-match": error.details.revision }, payload: stageBody(row, { displayName: "幽冥古道·二B" }) });
      expect(forced.statusCode).toBe(200);
      const list2 = (await app.inject({ method: "GET", url: "/admin/draft/stages", headers: admin })).json() as { id: string; displayName: string }[];
      expect(list2.find((stage) => stage.id === "zhuji_2")!.displayName).toBe("幽冥古道·二B");

      // 同一个窗口接着改：用上次响应头里的新版本号，不会误报
      const again = await app.inject({ method: "PUT", url: "/admin/draft/stages/zhuji_2", headers: { ...admin, "if-match": forced.headers["x-revision"] as string }, payload: stageBody(row, { displayName: "幽冥古道·二C" }) });
      expect(again.statusCode).toBe(200);
    });
  });

  it("globals: one page saving makes another page's stale save 409; no If-Match stays allowed (compat); /api/v1 prefix guarded too", async () => {
    await withDb(async (db) => {
      const { app, admin, revisions } = await boot(db);
      const opened = (await revisions("globals"))["1"]!;
      const bossRules = (await app.inject({ method: "GET", url: "/admin/draft/boss-rules", headers: admin })).json();
      const saved = await app.inject({ method: "PUT", url: "/admin/draft/tuning", headers: { ...admin, "if-match": opened }, payload: { bookOverflowSeconds: 1234 } });
      expect(saved.statusCode).toBe(200);
      const stale = await app.inject({ method: "PUT", url: "/api/v1/admin/draft/boss-rules", headers: { ...admin, "if-match": `"${opened}"` }, payload: bossRules.rules ?? {} });
      expect(stale.statusCode).toBe(409);
      expect(stale.json().error.details).toMatchObject({ kind: "globals", id: "1", revision: saved.headers["x-revision"] });
      // 不带 If-Match：照旧保存（脚本、旧页面）
      const legacy = await app.inject({ method: "PUT", url: "/admin/draft/tuning", headers: admin, payload: { bookOverflowSeconds: 1500 } });
      expect(legacy.statusCode).toBe(200);
    });
  });

  it("chapter / realm: stale save is rejected; revisions endpoint validates kind and needs admin", async () => {
    await withDb(async (db) => {
      const { app, admin, revisions } = await boot(db);
      const chapterRev = (await revisions("chapter")).heifeng!;
      const ok = await app.inject({ method: "PUT", url: "/admin/draft/chapters/heifeng", headers: { ...admin, "if-match": chapterRev }, payload: { displayName: "黑风岭改" } });
      expect(ok.statusCode).toBe(200);
      const stale = await app.inject({ method: "PUT", url: "/admin/draft/chapters/heifeng", headers: { ...admin, "if-match": chapterRev }, payload: { displayName: "黑风岭再改" } });
      expect(stale.statusCode).toBe(409);
      const realmRevs = await revisions("realm");
      expect(Object.keys(realmRevs).length).toBeGreaterThan(0);
      const bad = await app.inject({ method: "GET", url: "/admin/draft/revisions?kind=nope", headers: admin });
      expect(bad.statusCode).toBe(400);
      const anonymous = await app.inject({ method: "GET", url: "/admin/draft/revisions?kind=stage" });
      expect(anonymous.statusCode).toBe(401);
      const anonymousPut = await app.inject({ method: "PUT", url: "/admin/draft/chapters/heifeng", headers: { "if-match": chapterRev }, payload: { displayName: "x" } });
      expect(anonymousPut.statusCode).toBe(401);
    });
  });
});
