import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentRealms, playerItems, playerStates } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { decomposeItem, setAutoDecompose } from "./actions.js";

describe("equipment decompose", () => {
  it("turns a weaker spare piece into cultivation and remembers the switch", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({
        slug: "1",
        displayName: "凡人",
        sortOrder: 1,
        nextRealmSlug: null,
        baseAttack: 10,
        baseInterval: 1.5,
        gainPerTick: 1,
      });
      await db.insert(contentGlobals).values({
        id: 1,
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
        combat: {
          minInterval: 0.5,
          defenseConstant: 1,
          recommendedPowerMargin: 1.05,
          challengeCooldownSeconds: 0,
          timeLimitSeconds: 20,
          speedBase: 100,
        },
      });
      await db.insert(contentItems).values([
        { slug: "worn", displayName: "身上", kind: "equipment", slot: "weapon", quality: "green", attack: 10, defense: 0, hp: 0, speed: 0 },
        { slug: "spare", displayName: "背包", kind: "equipment", slot: "weapon", quality: "white", attack: 4, defense: 0, hp: 0, speed: 0 },
      ]);
      const now = new Date("2026-10-10T12:00:00.000Z");
      const player = await registerPlayer(db, { username: "reader", password: "correct-horse", now });
      await db.insert(playerItems).values({
        playerId: player.playerId,
        itemSlug: "worn",
        isStack: false,
        quantity: 1,
        equippedSlot: "weapon",
        source: "test",
        acquiredAt: now,
      });
      const [spare] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: "spare", isStack: false, quantity: 1, source: "test", acquiredAt: now })
        .returning();
      const world = await loadCurrentWorld(db);
      if (!world || !spare) {
        throw new Error("准备数据失败");
      }
      const decomposed = await withTransaction(db, (tx) => decomposeItem(tx, world, player.playerId, spare.id, now));
      expect(decomposed.convertedCultivation).toBe(30);
      const left = await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId));
      expect(left.map((row) => row.itemSlug)).toEqual(["worn"]);
      const switched = await withTransaction(db, (tx) => setAutoDecompose(tx, world, player.playerId, true, now));
      expect(switched.state.autoDecompose).toBe(true);
      const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, player.playerId));
      expect(state?.autoDecompose).toBe(true);
    });
  });
});