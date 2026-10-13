import { describe, expect, it } from "vitest";
import { contentGlobals, contentRealms, playerItems } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { createOpsItem, createOpsWeapon, createWeaponCategory } from "../content/ops-content.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { equipItem } from "./actions.js";

describe("wear a weapon", () => {
  it("wears a weapon that has no body slot and refuses an ordinary item", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({
        slug: "1",
        displayName: "凡人",
        sortOrder: 1,
        nextRealmSlug: null,
        baseAttack: 10,
        baseHp: 100,
        baseInterval: 1.5,
      });
      await db.insert(contentGlobals).values({
        id: 1,
        offlineCapSeconds: 3600,
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
      const category = await createWeaponCategory(db, { displayName: "刀" }, null);
      const knife = await createOpsWeapon(db, { displayName: "刀", categoryId: category.id, slot: "weapon", attack: 10, defense: 0, hp: 0, speed: 0 }, null);
      const herb = await createOpsItem(db, { displayName: "灵芝" }, null);
      const now = new Date("2026-10-10T12:00:00.000Z");
      const player = await registerPlayer(db, { username: "wearer", password: "correct-horse", now });
      const [knifeRow] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: knife.id, isStack: false, quantity: 1, source: "test", acquiredAt: now })
        .returning();
      const [herbRow] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: herb.id, isStack: true, quantity: 1, source: "test", acquiredAt: now })
        .returning();
      const world = await loadCurrentWorld(db);
      if (!world || !knifeRow || !herbRow) {
        throw new Error("准备数据失败");
      }
      const worn = await withTransaction(db, (tx) => equipItem(tx, world, player.playerId, knifeRow.id, now));
      expect(worn.state.attack).toBe(20);
      expect(worn.state.items.find((item) => item.id === knifeRow.id)?.equippedSlot).toBe("weapon");
      await expect(withTransaction(db, (tx) => equipItem(tx, world, player.playerId, herbRow.id, now))).rejects.toMatchObject({
        message: "这不是武器，不能穿",
      });
    });
  });
});