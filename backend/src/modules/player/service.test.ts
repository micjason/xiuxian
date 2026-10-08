import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { playerStates } from "../../db/schema.js";
import { registerPlayer } from "../auth/service.js";
import { publish, saveRealm } from "../content/service.js";
import { listOperations } from "../operations/record.js";
import { withDb } from "../../test/db.js";
import { piecePower } from "./power.js";
import { openProgress, tryBreakthrough } from "./service.js";

const start = new Date("2026-10-06T00:00:00.000Z");
const later = new Date(start.getTime() + 50_000);

const mortal = {
  slug: "mortal",
  displayName: "凡人",
  sortOrder: 0,
  gainPerSecond: 2,
  breakthroughCost: 360,
  nextSlug: "qi_early",
  attack: 10,
  defense: 6,
  hp: 50,
  speed: 0,
};

async function publishedMortal(db: Parameters<typeof saveRealm>[0]) {
  await saveRealm(db, "publisher", mortal);
  await saveRealm(db, "publisher", {
    ...mortal,
    slug: "qi_early",
    displayName: "炼气初期",
    sortOrder: 1,
    nextSlug: null,
  });
  await publish(db, { id: "unused", name: "publisher" }, start);
}

describe("openProgress", { timeout: 20_000 }, () => {
  it("settles fifty seconds once and ignores a client cultivation value", async () => {
    await withDb(async (db) => {
      await publishedMortal(db);
      const player = await registerPlayer(db, { username: "settler", password: "correct-horse", now: start });
      const first = await openProgress(db, player.playerId, later);
      expect(first).toMatchObject({
        realmSlug: "mortal",
        realmName: "凡人",
        cultivation: 100,
        gained: 100,
        power: piecePower({ attack: 10, defense: 6, hp: 50, speed: 0 }),
      });
      const second = await openProgress(db, player.playerId, later);
      expect(second.cultivation).toBe(100);
      expect(second.gained).toBe(0);
      const short = await tryBreakthrough(db, player.playerId, later);
      expect(short).toEqual({ ok: false, reason: "not_enough" });
      const rows = await listOperations(db, {
        name: "settler",
        action: "breakthrough",
        from: start,
        to: new Date("2026-10-07T00:00:00.000Z"),
      });
      expect(rows.some((row) => row.result === "failure" && row.reason === "not_enough")).toBe(true);
    });
  });

  it("fails without a published config and does not change cultivation", async () => {
    await withDb(async (db) => {
      const player = await registerPlayer(db, { username: "unpublished", password: "correct-horse", now: start });
      await expect(openProgress(db, player.playerId, later)).rejects.toThrow(/published/);
      const rows = await listOperations(db, {
        name: "unpublished",
        action: "settle",
        from: start,
        to: new Date("2026-10-07T00:00:00.000Z"),
      });
      expect(rows.some((row) => row.result === "failure")).toBe(true);
      const [state] = await db
        .select()
        .from(playerStates)
        .where(eq(playerStates.playerId, player.playerId))
        .limit(1);
      expect(state?.cultivation).toBe(0);
    });
  });

  it("breaks through after cultivation is enough", async () => {
    await withDb(async (db) => {
      await publishedMortal(db);
      const player = await registerPlayer(db, { username: "breaker", password: "correct-horse", now: start });
      const rich = new Date(start.getTime() + 200_000);
      await openProgress(db, player.playerId, rich);
      const result = await tryBreakthrough(db, player.playerId, rich);
      expect(result).toEqual({ ok: true, realmSlug: "qi_early", cultivation: 400 - 360 });
      const rows = await listOperations(db, {
        name: "breaker",
        action: "breakthrough",
        from: start,
        to: new Date("2026-10-07T00:00:00.000Z"),
      });
      expect(JSON.stringify(rows)).toContain("qi_early");
    });
  });
});
