import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentGlobals, contentRealms, contentSkills, playerSkills, playerStates, players } from "../db/schema.js";
import { publishSnapshot } from "../modules/content/snapshot.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z");
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

/** 每秒 1 点修为、离线上限 8 小时、一本 +15% 的心法。 */
async function seedWorld(db: TestDb) {
  await db.insert(contentGlobals).values({
    id: 1,
    startingRealmSlug: "qi_early",
    offlineCapSeconds: 28800,
    bagCapacity: 20,
    powerWeights: { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 },
    combat: { minInterval: 0.7, defenseConstant: 1, recommendedPowerMargin: 1.05, challengeCooldownSeconds: 0, timeLimitSeconds: 45, speedBase: 100 },
  });
  await db.insert(contentRealms).values({
    slug: "qi_early",
    displayName: "炼气一层",
    sortOrder: 1,
    nextRealmSlug: null,
    tickSeconds: 1,
    gainPerTick: 1,
    breakthroughCost: 9999,
    baseAttack: 10,
    baseDefense: 10,
    baseHp: 33,
    baseInterval: 1.5,
  });
  await db.insert(contentSkills).values({ slug: "breath", displayName: "吐纳", role: "heart", cultivateBonusBp: 1500 });
  await publishSnapshot(db, "settle remainder", null, start);
}

async function newPlayerWithRunningSkill(db: TestDb, app: Awaited<ReturnType<typeof buildApp>>) {
  const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "remainder_user", password: "correct-horse" } });
  expect(registered.statusCode).toBe(200);
  const token = registered.json().token as string;
  const [player] = await db.select().from(players).where(eq(players.usernameLower, "remainder_user"));
  await db.insert(playerSkills).values({ playerId: player!.id, skillSlug: "breath", learnedAt: start, level: 1, runningSlot: "heart" });
  return { token, playerId: player!.id };
}

describe("cultivation settlement with a +15% skill at 1/s", () => {
  it("online: 300 polls of GET /me/state, 3 s apart, add up to 1,035 (not 900)", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      let clock = start;
      const app = await buildApp(db, () => clock, { randomInt: () => 0 });
      const { token, playerId } = await newPlayerWithRunningSkill(db, app);
      const headers = { authorization: `Bearer ${token}` };
      let last = 0;
      for (let poll = 1; poll <= 300; poll += 1) {
        clock = new Date(start.getTime() + poll * 3000);
        const response = await app.inject({ method: "GET", url: "/api/v1/me/state", headers });
        expect(response.statusCode).toBe(200);
        last = response.json().cultivation as number;
        expect(last).toBeGreaterThanOrEqual(0);
      }
      expect(last).toBe(1035);
      const [row] = await db.select().from(playerStates).where(eq(playerStates.playerId, playerId));
      expect(row?.cultivation).toBe(1035);
      expect(row?.cultivationRemainderBp).toBe(0);
      await app.close();
    });
  }, 120_000);

  it("offline: one request after 8 h gives 33,120 and keeps no remainder", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      let clock = start;
      const app = await buildApp(db, () => clock, { randomInt: () => 0 });
      const { token } = await newPlayerWithRunningSkill(db, app);
      clock = new Date(start.getTime() + 8 * 3600 * 1000);
      const response = await app.inject({ method: "GET", url: "/api/v1/me/state", headers: { authorization: `Bearer ${token}` } });
      expect(response.statusCode).toBe(200);
      expect(response.json().cultivation).toBe(33120);
      await app.close();
    });
  });

  it("the remainder survives between requests and is stored in the database", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      let clock = start;
      const app = await buildApp(db, () => clock, { randomInt: () => 0 });
      const { token, playerId } = await newPlayerWithRunningSkill(db, app);
      const headers = { authorization: `Bearer ${token}` };
      clock = new Date(start.getTime() + 1000);
      expect((await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json().cultivation).toBe(1);
      let [row] = await db.select().from(playerStates).where(eq(playerStates.playerId, playerId));
      expect(row?.cultivationRemainderBp).toBe(1500);
      clock = new Date(start.getTime() + 2000);
      expect((await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json().cultivation).toBe(2);
      [row] = await db.select().from(playerStates).where(eq(playerStates.playerId, playerId));
      expect(row?.cultivationRemainderBp).toBe(3000);
      await app.close();
    });
  });
});
