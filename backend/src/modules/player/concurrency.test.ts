import { describe, expect, it } from "vitest";
import { publish, saveRealm } from "../content/service.js";
import { registerPlayer } from "../auth/service.js";
import { testAdmin } from "../../test/admin.js";
import { insertStartingRealm, withDb } from "../../test/db.js";
import { contentGlobals, contentRealms } from "../../db/schema.js";
import { eq } from "drizzle-orm";
import { openProgress, tryBreakthrough } from "./service.js";

const start = new Date("2026-10-08T00:00:00.000Z");
const later = new Date(start.getTime() + 50_000);

const mortal = {
  slug: "mortal",
  displayName: "凡人",
  sortOrder: 0,
  gainPerSecond: 2,
  breakthroughCost: 10,
  nextSlug: "qi_early",
  attack: 10,
  defense: 6,
  hp: 50,
  speed: 0,
};

describe("player concurrency", () => {
  it("settles ten parallel reads as one gain", async () => {
    await withDb(async (db) => {
      await insertStartingRealm(db);
      await saveRealm(db, "publisher", mortal);
      await saveRealm(db, "publisher", { ...mortal, slug: "qi_early", displayName: "炼气初期", sortOrder: 1, nextSlug: null, breakthroughCost: 999999 });
      await publish(db, await testAdmin(db), start);
      // /me 和 /me/state 共用新结算：给新内容里的境界补上每秒 2 点的修炼和基础出手间隔。
      await db.update(contentRealms).set({ tickSeconds: 1, gainPerTick: 2, baseInterval: 1.5, baseAttack: 10, baseDefense: 6, baseHp: 50 }).where(eq(contentRealms.slug, "mortal"));
      await db.update(contentGlobals).set({ offlineCapSeconds: 28800, bagCapacity: 20, powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 }, combat: { minInterval: 0.5, challengeCooldownSeconds: 0, timeLimitSeconds: 45, defenseConstant: 1, speedBase: 100, recommendedPowerMargin: 1.05 } }).where(eq(contentGlobals.id, 1));
      const player = await registerPlayer(db, { username: "racer", password: "correct-horse", now: start });
      const results = await Promise.all(Array.from({ length: 10 }, () => openProgress(db, player.playerId, later)));
      expect(results.every((row) => row.cultivation === 100)).toBe(true);
    });
  });

  it("lets only one of five parallel breakthroughs advance the realm", async () => {
    await withDb(async (db) => {
      await insertStartingRealm(db);
      await saveRealm(db, "publisher", { ...mortal, breakthroughCost: 0 });
      await saveRealm(db, "publisher", { ...mortal, slug: "qi_early", displayName: "炼气初期", sortOrder: 1, nextSlug: null, breakthroughCost: 999999 });
      await publish(db, await testAdmin(db), start);
      const player = await registerPlayer(db, { username: "racer2", password: "correct-horse", now: start });
      const results = await Promise.all(Array.from({ length: 5 }, () => tryBreakthrough(db, player.playerId, start)));
      const wins = results.filter((row) => row.ok && row.realmSlug === "qi_early");
      expect(wins).toHaveLength(1);
    });
  });
});
