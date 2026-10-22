import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentDropTables, contentGlobals, contentRealms, contentStages, players } from "../db/schema.js";
import { saveRules, type RulesInput } from "../modules/content/rules.js";
import { SCHEME_TIME_LIMIT_SECONDS } from "../modules/content/numeric-scheme.js";
import { publishSnapshot } from "../modules/content/snapshot.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z");
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

const RULES: RulesInput = {
  offlineCapSeconds: 28800,
  bagCapacity: 20,
  attackWeight: 1,
  defenseWeight: 0.8,
  hpWeight: 0.04,
  speedWeight: 1.5,
  baseInterval: 1.5,
  minInterval: 0.7,
  challengeCooldownSeconds: 0,
  defenseConstant: 1,
  speedBase: 100,
  recommendedPowerMargin: 1.05,
};

/**
 * 玩家攻击 10、出手间隔 1.5 秒（没有速度），首领防御 0、气血 200：每下 10 点，要 20 下 = 第 30 秒打死。
 * 首领攻击 1，打不死玩家，所以胜负只取决于时限。
 */
async function seed(db: TestDb, timeLimitSeconds: number) {
  await db.insert(contentGlobals).values({
    id: 1,
    startingRealmSlug: "mortal",
    offlineCapSeconds: 28800,
    bagCapacity: 20,
    powerWeights: { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 },
    combat: { minInterval: 0.7, defenseConstant: 1, recommendedPowerMargin: 1.05, challengeCooldownSeconds: 0, timeLimitSeconds, speedBase: 100 },
  });
  await db.insert(contentRealms).values({
    slug: "mortal",
    displayName: "凡人",
    sortOrder: 0,
    nextRealmSlug: null,
    tickSeconds: 1,
    gainPerTick: 1,
    breakthroughCost: 99999,
    baseAttack: 10,
    baseDefense: 10,
    baseHp: 1000,
    baseInterval: 1.5,
  });
  await db.insert(contentDropTables).values([
    { slug: "drop_boss", displayName: "首领" },
    { slug: "drop_idle", displayName: "挂机" },
    { slug: "drop_first", displayName: "首通" },
  ]);
  await db.insert(contentStages).values({
    slug: "boss30",
    displayName: "三十秒关",
    sortOrder: 0,
    nextStageSlug: null,
    requiredRealmOrder: 0,
    bosses: [{ name: "木桩", attack: 1, defense: 0, hp: 200, interval: 5, drops: [] }],
    bossName: "木桩",
    bossAttack: 1,
    bossDefense: 0,
    bossHp: 200,
    bossInterval: 5,
    bossDropTableSlug: "drop_boss",
    idleDropTableSlug: "drop_idle",
    firstClearDropTableSlug: "drop_first",
  });
}

async function challenge(db: TestDb) {
  const app = await buildApp(db, () => start, { randomInt: () => 0 });
  const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "limit_user", password: "correct-horse" } });
  expect(registered.statusCode).toBe(200);
  const response = await app.inject({
    method: "POST",
    url: "/api/v1/me/stages/boss30/challenge",
    headers: { authorization: `Bearer ${registered.json().token as string}`, "idempotency-key": "boss-limit-1" },
  });
  expect(response.statusCode).toBe(200);
  await app.close();
  return response.json().battle as { win: boolean; reason: string; durationSeconds: number };
}

describe("boss time limit is an admin-configurable value", () => {
  it("the scheme default is 45 seconds", () => {
    expect(SCHEME_TIME_LIMIT_SECONDS).toBe(45);
  });

  it("a 30 s fight is lost at the old 20 s limit", async () => {
    await withDb(async (db) => {
      await seed(db, 20);
      await publishSnapshot(db, "limit 20", null, start);
      expect(await challenge(db)).toMatchObject({ win: false, reason: "timeout", durationSeconds: 20 });
    });
  });

  it("saving 45 s in the admin rules (then publishing the version) makes the same fight a win", async () => {
    await withDb(async (db) => {
      await seed(db, 20);
      await saveRules(db, { ...RULES, timeLimitSeconds: 45 }, null);
      const [saved] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1));
      expect(saved?.combat?.timeLimitSeconds).toBe(45);
      await publishSnapshot(db, "limit 45", null, start);
      const battle = await challenge(db);
      expect(battle.win).toBe(true);
      expect(battle.durationSeconds).toBe(30);
      expect((await db.select().from(players)).length).toBe(1);
    });
  });

  it("the game reads the saved value right away (loadCurrentWorld reads live content; publish only records a version)", async () => {
    await withDb(async (db) => {
      await seed(db, 45);
      await publishSnapshot(db, "limit 45", null, start);
      await saveRules(db, { ...RULES, timeLimitSeconds: 10 }, null);
      expect(await challenge(db)).toMatchObject({ win: false, reason: "timeout", durationSeconds: 10 });
    });
  });

  it("rejects 0 or a missing limit when saving", async () => {
    await withDb(async (db) => {
      await seed(db, 45);
      await expect(saveRules(db, { ...RULES, timeLimitSeconds: 0 }, null)).rejects.toThrow();
      await expect(saveRules(db, { ...RULES, timeLimitSeconds: -5 }, null)).rejects.toThrow();
    });
  });
});
