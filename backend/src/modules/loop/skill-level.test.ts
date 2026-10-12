import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentRealms, playerItems, playerSkills } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { createOpsSkill, createSkillCategory, ensureSkillBook } from "../content/ops-content.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { combatStats, useItem } from "./actions.js";

describe("skill book layers", () => {
  it("consumes each book and doubles the effect at the next layer", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({
        slug: "1",
        displayName: "凡人",
        sortOrder: 1,
        nextRealmSlug: null,
        baseAttack: 10,
        baseInterval: 1.5,
      });
      await db.insert(contentGlobals).values({
        id: 1,
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        powerWeights: { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 },
        combat: {
          minInterval: 0.7,
          playerDefenseFactor: 0.4,
          bossDefenseFactor: 0.5,
          challengeCooldownSeconds: 0,
          timeLimitSeconds: 60,
          playerDamageFloor: 1,
          bossDamageFloor: 0,
          speedBase: 100,
        },
      });
      const category = await createSkillCategory(db, { displayName: "吐纳" }, null);
      const skill = await createOpsSkill(
        db,
        { displayName: "吐纳", categoryId: category.id, attack: 4, defense: 0, hp: 0, speed: 0, cultivateBonus: 10 },
        null,
      );
      const now = new Date("2026-10-10T12:00:00.000Z");
      const player = await registerPlayer(db, { username: "reader", password: "correct-horse", now });
      const bookSlug = await ensureSkillBook(db, { slug: skill.id, displayName: "吐纳" }, null);
      const [firstBook] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: bookSlug, isStack: false, quantity: 1, source: "test", acquiredAt: now })
        .returning();
      const [secondBook] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: bookSlug, isStack: false, quantity: 1, source: "test", acquiredAt: now })
        .returning();
      const world = await loadCurrentWorld(db);
      if (!world || !firstBook || !secondBook) {
        throw new Error("准备数据失败");
      }
      const first = await withTransaction(db, (tx) => useItem(tx, world, player.playerId, firstBook.id, now));
      expect(first.learned).toEqual({ displayName: "吐纳", level: 1 });
      const second = await withTransaction(db, (tx) => useItem(tx, world, player.playerId, secondBook.id, now));
      expect(second.learned).toEqual({ displayName: "吐纳", level: 2 });
      const left = await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId));
      expect(left).toEqual([]);
      const [learned] = await db.select().from(playerSkills).where(eq(playerSkills.playerId, player.playerId));
      expect(learned?.level).toBe(2);
      expect(combatStats(world, "1", [], [{ slug: skill.id, level: 2 }]).attack).toBe(18);
    });
  });
});
