import { describe, expect, it } from "vitest";
import { publish, saveRealm } from "../content/service.js";
import { registerPlayer } from "../auth/service.js";
import { withDb } from "../../test/db.js";
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
      await saveRealm(db, "publisher", mortal);
      await saveRealm(db, "publisher", { ...mortal, slug: "qi_early", displayName: "炼气初期", sortOrder: 1, nextSlug: null, breakthroughCost: 999999 });
      await publish(db, { id: "unused", name: "publisher" }, start);
      const player = await registerPlayer(db, { username: "racer", password: "correct-horse", now: start });
      const results = await Promise.all(Array.from({ length: 10 }, () => openProgress(db, player.playerId, later)));
      expect(results.every((row) => row.cultivation === 100)).toBe(true);
    });
  });

  it("lets only one of five parallel breakthroughs advance the realm", async () => {
    await withDb(async (db) => {
      await saveRealm(db, "publisher", { ...mortal, breakthroughCost: 0 });
      await saveRealm(db, "publisher", { ...mortal, slug: "qi_early", displayName: "炼气初期", sortOrder: 1, nextSlug: null, breakthroughCost: 999999 });
      await publish(db, { id: "unused", name: "publisher" }, start);
      const player = await registerPlayer(db, { username: "racer2", password: "correct-horse", now: start });
      const results = await Promise.all(Array.from({ length: 5 }, () => tryBreakthrough(db, player.playerId, start)));
      const wins = results.filter((row) => row.ok && row.realmSlug === "qi_early");
      expect(wins).toHaveLength(1);
    });
  });
});
