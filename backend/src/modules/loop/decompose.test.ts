import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentRealms, playerItems } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { STARTING_ENHANCE_RULES, STARTING_ESSENCE_ITEM } from "../content/enhance.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { decomposeItem } from "./actions.js";

describe("equipment decompose", () => {
  it("turns a spare piece into 炼器精粹 (a stackable material) and leaves worn gear alone", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({
        slug: "1",
        displayName: "凡人",
        majorName: "金丹",
        majorKey: "core",
        sortOrder: 0,
        nextRealmSlug: null,
        baseAttack: 10,
        baseInterval: 1.5,
        gainPerTick: 1,
      });
      await db.insert(contentGlobals).values({
        id: 1,
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        enhance: STARTING_ENHANCE_RULES,
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
        { slug: STARTING_ESSENCE_ITEM.slug, displayName: STARTING_ESSENCE_ITEM.displayName, kind: "material", quality: "orange", stackable: true },
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
      expect(decomposed.gainedEssence).toBe(20);
      expect(decomposed.gainedEnhanceExp).toBe(0);
      expect(decomposed.state.essence).toEqual({ itemSlug: "refine_essence", count: 20 });
      expect(decomposed.state.enhanceExp).toBe(0);
      const left = await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId));
      expect(left.map((row) => [row.itemSlug, row.quantity]).sort()).toEqual([["refine_essence", 20], ["worn", 1]]);
    });
  });
});