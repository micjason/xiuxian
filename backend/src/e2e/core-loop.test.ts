import { describe, expect, it } from "vitest";
import {
  contentDropTables,
  contentGlobals,
  contentItems,
  contentRealms,
  contentSkills,
  contentStages,
} from "../db/schema.js";
import { publishSnapshot } from "../modules/content/snapshot.js";
import { withDb } from "../test/db.js";
import { buildApp } from "../app.js";

const start = new Date("2026-10-08T03:00:00.000Z");

async function seedWorld(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
  await db.insert(contentGlobals).values({
    id: 1,
    offlineCapSeconds: 28800,
    bagCapacity: 20,
    powerWeights: { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 },
    combat: {
      minInterval: 0.7,
      defenseConstant: 1,
      recommendedPowerMargin: 1.05,
      challengeCooldownSeconds: 0,
      timeLimitSeconds: 60,
      speedBase: 100,
    },
  });
  await db.insert(contentRealms).values([
    {
      slug: "mortal",
      displayName: "凡人",
      sortOrder: 0,
      nextRealmSlug: "qi_early",
      tickSeconds: 1,
      gainPerTick: 10,
      breakthroughCost: 20,
      baseRateBp: 10000,
      minRateBp: 10000,
      maxRateBp: 10000,
      baseAttack: 40,
      baseDefense: 10,
      baseHp: 80,
      baseInterval: 1.5,
    },
    {
      slug: "qi_early",
      displayName: "炼气初期",
      sortOrder: 1,
      nextRealmSlug: null,
      tickSeconds: 1,
      gainPerTick: 20,
      breakthroughCost: 9999,
      baseRateBp: 10000,
      minRateBp: 10000,
      maxRateBp: 10000,
      baseAttack: 50,
      baseDefense: 10,
      baseHp: 100,
      baseInterval: 1.5,
    },
  ]);
  await db.insert(contentSkills).values({
    slug: "breath",
    displayName: "吐纳",
    role: "heart",
    cultivateBonusBp: 1500,
  });
  await db.insert(contentItems).values([
    {
      slug: "wood_sword",
      displayName: "木剑",
      kind: "equipment",
      slot: "weapon",
      attack: 12,
      stackable: false,
    },
    {
      slug: "breath_book",
      displayName: "吐纳书",
      kind: "skill_book",
      skillSlug: "breath",
      stackable: true,
    },
  ]);
  await db.insert(contentDropTables).values([
    { slug: "drop_boss", displayName: "首领" },
    { slug: "drop_idle", displayName: "挂机" },
    { slug: "drop_first", displayName: "首通" },
  ]);
  const { contentDropEntries } = await import("../db/schema.js");
  await db.insert(contentDropEntries).values([
    { dropTableSlug: "drop_first", itemSlug: "breath_book", chanceBp: 10000, minQty: 1, maxQty: 1 },
  ]);
  await db.insert(contentStages).values([
    {
      slug: "grove",
      displayName: "林间",
      sortOrder: 0,
      nextStageSlug: "grove_2",
      requiredRealmOrder: 0,
      bosses: [{ name: "木傀", attack: 1, defense: 0, hp: 10, interval: 2, drops: [{ itemSlug: "wood_sword", chanceBp: 10000 }] }],
      bossName: "木傀",
      bossAttack: 1,
      bossDefense: 0,
      bossHp: 10,
      bossInterval: 2,
      bossDropTableSlug: "drop_boss",
      idleDropTableSlug: "drop_idle",
      firstClearDropTableSlug: "drop_first",
    },
    {
      slug: "grove_2",
      displayName: "林深",
      sortOrder: 1,
      nextStageSlug: null,
      bossName: "石傀",
      bossHp: 30,
      bossDropTableSlug: "drop_boss",
      idleDropTableSlug: "drop_idle",
      firstClearDropTableSlug: "drop_first",
    },
  ]);
  await publishSnapshot(db, "核心循环", null, start);
}

describe("core loop", () => {
  it("breaks through, clears a boss, equips, and runs a skill", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      let clock = start;
      const app = await buildApp(db, () => clock, { randomInt: () => 0 });
      const registered = await app.inject({
        method: "POST",
        url: "/api/v1/auth/register",
        payload: { username: "loop_user", password: "correct-horse" },
      });
      expect(registered.statusCode).toBe(200);
      const token = registered.json().token as string;
      const headers = { authorization: `Bearer ${token}`, "idempotency-key": "breakthrough-1" };
      clock = new Date(start.getTime() + 10_000);
      const synced = await app.inject({ method: "POST", url: "/api/v1/me/sync", headers });
      expect(synced.statusCode).toBe(200);
      expect(synced.json().cultivation).toBe(100);

      const firstBreak = await app.inject({ method: "POST", url: "/api/v1/me/breakthrough", headers });
      const secondBreak = await app.inject({ method: "POST", url: "/api/v1/me/breakthrough", headers });
      expect(firstBreak.statusCode).toBe(200);
      expect(secondBreak.json()).toEqual(firstBreak.json());
      expect(firstBreak.json().result.success).toBe(true);
      expect(firstBreak.json().state.realmSlug).toBe("qi_early");
      expect(firstBreak.json().state.cultivation).toBe(80);

      const challenged = await app.inject({
        method: "POST",
        url: "/api/v1/me/stages/grove/challenge",
        headers: { ...headers, "idempotency-key": "challenge-1" },
      });
      expect(challenged.statusCode).toBe(200);
      expect(challenged.json().battle.win).toBe(true);
      const items = challenged.json().state.items as { id: string; itemSlug: string }[];
      expect(items.map((row) => row.itemSlug).sort()).toEqual(["breath_book", "wood_sword"]);
      const stages = challenged.json().state.stages as { stageSlug: string }[];
      expect(stages.map((row) => row.stageSlug)).toEqual(expect.arrayContaining(["grove", "grove_2"]));
      const beforePower = challenged.json().state.power as number;
      const sword = items.find((row) => row.itemSlug === "wood_sword");
      const book = items.find((row) => row.itemSlug === "breath_book");

      const equipped = await app.inject({
        method: "POST",
        url: `/api/v1/me/items/${sword?.id}/equip`,
        headers: { ...headers, "idempotency-key": "equip-sword" },
      });
      expect(equipped.statusCode).toBe(200);
      expect(equipped.json().state.power).toBeGreaterThan(beforePower);

      const learned = await app.inject({
        method: "POST",
        url: `/api/v1/me/items/${book?.id}/use`,
        headers: { ...headers, "idempotency-key": "learn-book" },
      });
      expect(learned.statusCode).toBe(200);
      const running = await app.inject({
        method: "POST",
        url: "/api/v1/me/skills/breath/run",
        headers: { ...headers, "idempotency-key": "run-heart" },
        payload: { slot: "heart" },
      });
      expect(running.statusCode).toBe(200);
      expect(running.json().state.cultivationRate.bonusBp).toBe(1500);
      const stopped = await app.inject({
        method: "POST",
        url: "/api/v1/me/skills/breath/stop",
        headers: { ...headers, "idempotency-key": "stop-heart" },
      });
      expect(stopped.statusCode).toBe(200);
      expect(stopped.json().state.cultivationRate.bonusBp).toBe(0);
      const unequipped = await app.inject({
        method: "POST",
        url: `/api/v1/me/items/${sword?.id}/unequip`,
        headers: { ...headers, "idempotency-key": "unequip-weapon" },
      });
      expect(unequipped.statusCode).toBe(200);
      expect(unequipped.json().state.power).toBe(beforePower);
      await app.close();
    });
  });
});
