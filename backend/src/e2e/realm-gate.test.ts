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

describe("realm table: fixed 24 rows and major-breakthrough boss gate (admin API)", () => {
  it("lists the fixed 24 rows, upserts missing factory layers, and refuses create, delete, and import", async () => {
    await withDb(async (db) => {
      const { app, admin } = await boot(db);
      await db.insert(contentRealms).values({
        slug: "mortal",
        displayName: "凡人",
        sortOrder: 99,
        tickSeconds: 1,
        gainPerTick: 1,
        breakthroughCost: 0,
        baseAttack: 1,
        baseDefense: 1,
        baseHp: 1,
        baseSpeed: 0,
        baseInterval: 1.5,
      });
      const list = (await app.inject({ method: "GET", url: "/admin/draft/realms", headers: admin })).json();
      expect(list).toHaveLength(24);
      expect(list.some((row: { displayName: string }) => row.displayName === "凡人")).toBe(false);
      expect(list[0]).toMatchObject({ code: 1, displayName: "炼气一层", etaLabel: "约 30 分" });
      expect(list[0].ultName).toBeUndefined();
      expect(list[0].changed).toEqual(expect.arrayContaining(["breakthroughCost", "attack", "hp"]));
      expect(list[2]).toMatchObject({ code: 3, displayName: "炼气三层", requiredStageId: "lianqi_3", etaLabel: "约 4 小时" });
      expect(list[2].changed).not.toContain("requiredStageId");
      expect(list[9]).toMatchObject({
        code: 10,
        slug: "yuanying_1",
        displayName: "元婴一层",
        gainPerTick: 27,
        breakthroughCost: 466560,
        attack: 46,
        speed: 10,
        tuned: false,
        etaLabel: "约 5.5 天",
        stored: true,
      });
      expect(list[23]).toMatchObject({ code: 24, displayName: "大乘三层", showBreakthroughCost: false, showGate: true, etaLabel: "约 55 天", breakthroughCost: 0 });
      const created = await db.select().from(contentRealms).where(eq(contentRealms.slug, "yuanying_1"));
      expect(created[0]).toMatchObject({ tickSeconds: 1, gainPerTick: 27, nextRealmSlug: "yuanying_2", baseInterval: 1.5 });
      expect(created[0]).not.toHaveProperty("ultName");
      expect(created[0]).not.toHaveProperty("ultDamageMultBp");
      expect(created[0]).not.toHaveProperty("ultCooldownSeconds");
      expect(created[0]).not.toHaveProperty("ultFirstCooldownSeconds");
      const [lianqi1] = await db.select().from(contentRealms).where(eq(contentRealms.slug, "lianqi_1"));
      expect(lianqi1).toMatchObject({ nextRealmSlug: "lianqi_2", breakthroughCost: 60, gainPerTick: 1 });
      const [jindan3] = await db.select().from(contentRealms).where(eq(contentRealms.slug, "jindan_3"));
      expect(jindan3).toMatchObject({ nextRealmSlug: "yuanying_1", breakthroughCost: 0, gainPerTick: 9, requiredStageSlug: "jindan_3" });
      const stored = await db.select({ slug: contentRealms.slug, nextRealmSlug: contentRealms.nextRealmSlug }).from(contentRealms);
      const nextOf = new Map(stored.map((row) => [row.slug, row.nextRealmSlug]));
      const chain = ["lianqi_1", "lianqi_2", "lianqi_3", "zhuji_1", "zhuji_2", "zhuji_3", "jindan_1", "jindan_2", "jindan_3", "yuanying_1", "yuanying_2", "yuanying_3", "huashen_1", "huashen_2", "huashen_3", "lianxu_1", "lianxu_2", "lianxu_3", "heti_1", "heti_2", "heti_3", "dacheng_1", "dacheng_2", "dacheng_3"];
      for (let index = 0; index < chain.length; index += 1) {
        expect(nextOf.get(chain[index]!), `${chain[index]} next`).toBe(chain[index + 1] ?? null);
      }
      const world = await loadDraftSnapshot(db);
      const worldNext = new Map(world.realms.map((row) => [row.slug, row.nextRealmSlug]));
      for (let index = 0; index < chain.length; index += 1) {
        expect(worldNext.get(chain[index]!), `snapshot ${chain[index]} next`).toBe(chain[index + 1] ?? null);
      }
      expect(worldNext.get("mortal")).toBeNull();
      for (const [method, url] of [
        ["POST", "/admin/draft/realms/major"],
        ["POST", "/admin/draft/realms"],
        ["DELETE", "/admin/draft/realms/1"],
        ["GET", "/admin/draft/realms/major-preview"],
      ] as const) {
        const response = await app.inject({ method, url, headers: admin, payload: method === "GET" ? undefined : { majorName: "元婴", displayName: "新人" } });
        expect(response.statusCode, `${method} ${url}`).toBe(404);
      }
      const [still] = await db.select().from(contentRealms).where(eq(contentRealms.slug, "lianqi_1"));
      expect(still?.displayName).toBe("炼气一层");
      await app.close();
    });
  });

  it("PUT only accepts editable numbers, keeps the chain and the ETA, and rejects a breakthrough cost on 大乘三层", async () => {
    await withDb(async (db) => {
      const { app, admin } = await boot(db);
      const rename = await app.inject({
        method: "PUT",
        url: "/admin/draft/realms/5",
        headers: admin,
        payload: { displayName: "筑基改名", gainPerTick: 4 },
      });
      expect(rename.statusCode).toBe(400);
      expect(rename.json().error.message).toContain("displayName");
      const [before] = await db.select().from(contentRealms).where(eq(contentRealms.slug, "zhuji_2"));
      const saved = await app.inject({
        method: "PUT",
        url: "/admin/draft/realms/5",
        headers: admin,
        payload: { gainPerTick: 4 },
      });
      expect(saved.statusCode).toBe(200);
      const [after] = await db.select().from(contentRealms).where(eq(contentRealms.slug, "zhuji_2"));
      expect(after).toMatchObject({
        displayName: "筑基二层",
        gainPerTick: 4,
        nextRealmSlug: before?.nextRealmSlug,
        slug: "zhuji_2",
        sortOrder: 5,
      });
      const list = (await app.inject({ method: "GET", url: "/admin/draft/realms", headers: admin })).json();
      expect(list[4]).toMatchObject({ gainPerTick: 4, etaLabel: "约 9 小时" });
      expect(list[4].changed).toContain("gainPerTick");
      expect(list[4].etaLabel).toBe("约 9 小时");
      const capped = await app.inject({
        method: "PUT",
        url: "/admin/draft/realms/24",
        headers: admin,
        payload: { breakthroughCost: 9, gainPerTick: 2187 },
      });
      expect(capped.statusCode).toBe(400);
      expect(capped.json().error.message).toContain("大乘三层");
      const minorGate = await app.inject({
        method: "PUT",
        url: "/admin/draft/realms/1",
        headers: admin,
        payload: { requiredStageId: "lianqi_1" },
      });
      expect(minorGate.statusCode).toBe(400);
      expect(minorGate.json().error.message).toContain("三层");
      await app.close();
    });
  });

  it("saves requiredStageId on a major's third layer, keeps the slug, clears the gate, and has no realm ult columns", async () => {
    await withDb(async (db) => {
      const { app, admin } = await boot(db);
      const put = (code: number, payload: Record<string, unknown>) =>
        app.inject({ method: "PUT", url: `/admin/draft/realms/${code}`, headers: admin, payload });
      await db.update(contentStages).set({ bosses: [], bossHp: 0 }).where(eq(contentStages.slug, "lianqi_2"));
      const bossless = await put(3, { requiredStageId: "lianqi_2" });
      expect(bossless.statusCode).toBe(400);
      expect(bossless.json().error.message).toContain("没有首领");
      const unknown = await put(3, { requiredStageId: "nope" });
      expect(unknown.statusCode).toBe(400);
      const tooHigh = await put(3, { requiredStageId: "zhuji_3" });
      expect(tooHigh.statusCode).toBe(400);
      expect(tooHigh.json().error.message).toContain("永远打不到");
      const [before] = await db.select().from(contentRealms).where(eq(contentRealms.slug, "lianqi_3"));
      const good = await put(3, { requiredStageId: "lianqi_3" });
      expect(good.statusCode).toBe(200);
      const [row] = await db.select().from(contentRealms).where(eq(contentRealms.slug, "lianqi_3"));
      expect(row).toMatchObject({
        requiredStageSlug: "lianqi_3",
        displayName: "炼气三层",
        slug: "lianqi_3",
        nextRealmSlug: before?.nextRealmSlug,
        gainPerTick: before?.gainPerTick,
      });
      expect(row).not.toHaveProperty("ultName");
      expect(row).not.toHaveProperty("ultDamageMultBp");
      expect(row).not.toHaveProperty("ultCooldownSeconds");
      expect(row).not.toHaveProperty("ultFirstCooldownSeconds");
      const cleared = await put(3, { requiredStageId: "" });
      expect(cleared.statusCode).toBe(200);
      const [after] = await db.select().from(contentRealms).where(eq(contentRealms.slug, "lianqi_3"));
      expect(after?.requiredStageSlug).toBeNull();
      await app.close();
    });
  });

  it("validateContent: a gate stage must have a boss and be reachable; bossless stages are fine", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      expect(validateContent(await loadDraftSnapshot(db)).errors).toEqual([]); // 24 关都有首领（每小层 1 精英或章末）
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
