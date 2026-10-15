import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentGlobals, contentRealms, contentSkills, playerSkills, playerStates, players } from "../db/schema.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z");
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

async function seed(db: TestDb) {
  await db.insert(contentGlobals).values({
    id: 1,
    startingRealmSlug: "qi_early",
    offlineCapSeconds: 28800,
    bagCapacity: 20,
    powerWeights: { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 },
    combat: { minInterval: 0.7, defenseConstant: 1, recommendedPowerMargin: 1.05, challengeCooldownSeconds: 0, timeLimitSeconds: 45, speedBase: 100 },
  });
  await db.insert(contentRealms).values({ slug: "qi_early", displayName: "炼气一层", sortOrder: 1, nextRealmSlug: null, tickSeconds: 1, gainPerTick: 1, breakthroughCost: 9999, baseAttack: 10, baseDefense: 10, baseHp: 33, baseInterval: 1.5 });
  await db.insert(contentSkills).values({ slug: "breath", displayName: "吐纳", role: "heart", cultivateBonusBp: 1500 });
}

describe("GET /me (legacy endpoint) uses the same settlement as /me/state", () => {
  it("300 polls of GET /me, 3 s apart, add up to 1,035 with a +15% skill (the old path gave 900)", async () => {
    await withDb(async (db) => {
      await seed(db);
      let clock = start;
      const app = await buildApp(db, () => clock, { randomInt: () => 0 });
      const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "me_user", password: "correct-horse" } });
      const token = registered.json().token as string;
      const [player] = await db.select().from(players).where(eq(players.usernameLower, "me_user"));
      await db.insert(playerSkills).values({ playerId: player!.id, skillSlug: "breath", learnedAt: start, level: 1, runningSlot: "heart" });
      const headers = { authorization: `Bearer ${token}` };
      let last: Record<string, unknown> = {};
      for (let poll = 1; poll <= 300; poll += 1) {
        clock = new Date(start.getTime() + poll * 3000);
        const response = await app.inject({ method: "GET", url: "/api/v1/me", headers });
        expect(response.statusCode).toBe(200);
        last = response.json();
      }
      expect(last.cultivation).toBe(1035);
      expect(last).toMatchObject({ realmSlug: "qi_early", realmName: "炼气一层", offlineCapSeconds: 28800, canBreakthrough: false });
      expect(Array.isArray(last.notices)).toBe(true);
      const [row] = await db.select().from(playerStates).where(eq(playerStates.playerId, player!.id));
      expect(row?.cultivation).toBe(1035);
      await app.close();
    });
  }, 120_000);

  it("keeps the endpoint shape and caps an 8 h gap at the offline limit", async () => {
    await withDb(async (db) => {
      await seed(db);
      let clock = start;
      const app = await buildApp(db, () => clock, { randomInt: () => 0 });
      const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "me_user2", password: "correct-horse" } });
      const headers = { authorization: `Bearer ${registered.json().token as string}` };
      clock = new Date(start.getTime() + 10 * 3600 * 1000);
      const response = await app.inject({ method: "GET", url: "/api/v1/me", headers });
      expect(response.statusCode).toBe(200);
      expect(response.json()).toMatchObject({ cultivation: 28800, gained: 28800, gainPerSecond: 1 });
      await app.close();
    });
  });
});
