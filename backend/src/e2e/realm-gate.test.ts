import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentRealms, contentStages, playerStageProgress, playerStates, players } from "../db/schema.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { loadDraftSnapshot } from "../modules/content/snapshot.js";
import { validateContent } from "../modules/content/validate.js";
import { testAdmin } from "../test/admin.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z");

async function boot(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
  await applyPrototypeV12(db);
  await testAdmin(db, "gate_admin");
  let clock = start;
  const app = await buildApp(db, () => clock, { randomInt: () => 0 });
  const login = await app.inject({ method: "POST", url: "/admin/auth/login", payload: { username: "gate_admin", password: "admin-secret" } });
  const admin = { authorization: `Bearer ${login.json().token as string}` };
  return { app, admin, setClock: (next: Date) => (clock = next) };
}

describe("realm table: major-breakthrough boss gate (admin API)", () => {
  it("GET /admin/draft/realms returns requiredStageId without ult fields; POST major creates 3 layers; single POST defaults tickSeconds to 1", async () => {
    await withDb(async (db) => {
      const { app, admin } = await boot(db);
      const list = (await app.inject({ method: "GET", url: "/admin/draft/realms", headers: admin })).json();
      expect(list).toHaveLength(9);
      expect(list[2]).toMatchObject({ code: 3, displayName: "炼气三层", requiredStageId: "lianqi_3" });
      expect(list[2].ultName).toBeUndefined();
      expect(list[8]).toMatchObject({ code: 9, requiredStageId: "" });
      const major = await app.inject({
        method: "POST",
        url: "/admin/draft/realms/major",
        headers: admin,
        payload: { majorName: "元婴" },
      });
      expect(major.statusCode).toBe(200);
      expect(major.json().codes).toEqual([10, 11, 12]);
      const created = await db.select().from(contentRealms).where(eq(contentRealms.majorName, "元婴"));
      expect(created).toHaveLength(3);
      expect(created.map((row) => row.displayName)).toEqual(["元婴一层", "元婴二层", "元婴三层"]);
      expect(created[0]).toMatchObject({ tickSeconds: 1, ultDamageMultBp: 0, baseInterval: 1.5 });
      // 预填：金丹一层 gain 9 ×3 = 27，速度 40+10=50（金丹累计速度增量见种子）
      expect(created[0]!.gainPerTick).toBe(27);
      await app.close();
    });
  });

  it("saves requiredStageId on a realm, keeps the slug, clears the gate, and wipes legacy ult fields", async () => {
    await withDb(async (db) => {
      const { app, admin } = await boot(db);
      const put = (code: number, payload: Record<string, unknown>) =>
        app.inject({ method: "PUT", url: `/admin/draft/realms/${code}`, headers: admin, payload: { displayName: "炼气二层", majorName: "炼气", ...payload } });
      await db.update(contentStages).set({ bosses: [], bossHp: 0 }).where(eq(contentStages.slug, "lianqi_2"));
      const bossless = await put(2, { requiredStageId: "lianqi_2" });
      expect(bossless.statusCode).toBe(400);
      expect(bossless.json().error.message).toContain("没有首领");
      const unknown = await put(2, { requiredStageId: "nope" });
      expect(unknown.statusCode).toBe(400);
      const tooHigh = await put(1, { requiredStageId: "lianqi_3" });
      expect(tooHigh.statusCode).toBe(400);
      expect(tooHigh.json().error.message).toContain("永远打不到");
      const good = await put(3, { displayName: "炼气三层", requiredStageId: "lianqi_3" });
      expect(good.statusCode).toBe(200);
      const [row] = await db.select().from(contentRealms).where(eq(contentRealms.slug, "lianqi_3"));
      expect(row).toMatchObject({ requiredStageSlug: "lianqi_3", ultDamageMultBp: 0, ultName: "", displayName: "炼气三层" });
      const cleared = await put(3, { displayName: "炼气三层", requiredStageId: "" });
      expect(cleared.statusCode).toBe(200);
      const [after] = await db.select().from(contentRealms).where(eq(contentRealms.slug, "lianqi_3"));
      expect(after?.requiredStageSlug).toBeNull();
      await app.close();
    });
  });

  it("validateContent: a gate stage must have a boss and be reachable; bossless stages are fine", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      expect(validateContent(await loadDraftSnapshot(db)).errors).toEqual([]); // 第三批：9 关都有首领（6 个精英 + 3 个章末）
      await db.update(contentStages).set({ bosses: [], bossHp: 0, bossName: "" }).where(eq(contentStages.slug, "lianqi_1"));
      await db.update(contentRealms).set({ requiredStageSlug: "lianqi_1" }).where(eq(contentRealms.slug, "lianqi_3"));
      let errors = validateContent(await loadDraftSnapshot(db)).errors;
      expect(errors.some((row) => row.field === "requiredStageSlug" && row.message.includes("没有首领"))).toBe(true);
      await db.update(contentRealms).set({ requiredStageSlug: "zhuji_3" }).where(eq(contentRealms.slug, "lianqi_3"));
      errors = validateContent(await loadDraftSnapshot(db)).errors;
      expect(errors.some((row) => row.message.includes("永远打不到"))).toBe(true);
    });
  });

  it("deleting a stage that a realm uses as its gate is refused", async () => {
    await withDb(async (db) => {
      const { app, admin } = await boot(db);
      const response = await app.inject({ method: "DELETE", url: "/admin/draft/stages/lianqi_3", headers: admin });
      expect(response.statusCode).toBe(400);
      expect(response.json().error.message).toContain("突破门槛");
      await app.close();
    });
  });

  it("the major breakthrough is blocked until the gate boss is cleared; minor layers are not gated", async () => {
    await withDb(async (db) => {
      const { app, setClock } = await boot(db);
      const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "gate_player", password: "correct-horse" } });
      const headers = { authorization: `Bearer ${registered.json().token as string}` };
      const [player] = await db.select().from(players).where(eq(players.usernameLower, "gate_player"));
      let n = 0;
      const post = (url: string, payload: Record<string, unknown> = {}) => app.inject({ method: "POST", url: `/api/v1${url}`, headers: { ...headers, "idempotency-key": `gate-key-${(n += 1)}-padding` }, payload });
      // 炼气一层 → 二层 → 三层：不需要通关
      await db.update(playerStates).set({ cultivation: 100000 }).where(eq(playerStates.playerId, player!.id));
      expect((await post("/me/breakthrough")).json().result.success).toBe(true);
      expect((await post("/me/breakthrough")).json().result.success).toBe(true);
      const state = (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json();
      expect(state.realmSlug).toBe("lianqi_3");
      expect(state.breakthrough.requiredStage).toMatchObject({ slug: "lianqi_3", name: "黑风岭·三", cleared: false });
      // 大境界突破：没通关黑风熊王就被拒绝
      const blocked = await post("/me/breakthrough");
      expect(blocked.statusCode).toBeGreaterThanOrEqual(400);
      expect(blocked.json().error.code).toBe("STAGE_REQUIRED");
      // 通关之后（直接记一条首通记录）可以突破，进入筑基一层
      await db.insert(playerStageProgress).values({ playerId: player!.id, stageSlug: "lianqi_3", unlockedAt: start, firstClearedAt: start, clearCount: 1 }).onConflictDoNothing();
      setClock(new Date(start.getTime() + 1000));
      const passed = await post("/me/breakthrough");
      expect(passed.json().result.success).toBe(true);
      expect(passed.json().state.realmSlug).toBe("zhuji_1");
      expect(passed.json().state.breakthrough.requiredStage).toBeNull();
      await app.close();
    });
  });
});
