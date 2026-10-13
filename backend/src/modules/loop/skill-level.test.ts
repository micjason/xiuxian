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
          defenseConstant: 1,
          recommendedPowerMargin: 1.05,
          challengeCooldownSeconds: 0,
          timeLimitSeconds: 60,
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
      expect(combatStats(world, "1", [], [{ slug: skill.id, level: 2 }]).attack).toBeCloseTo(10 * (1 + 0.04 * 1.15));
      const withGear = combatStats(world, "1", [], [{ slug: skill.id, level: 2 }]).attack;
      const naked = combatStats(world, "1", [], []).attack;
      expect(withGear - naked).toBeCloseTo(10 * 0.04 * 1.15);
    });
  });

  it("adds skill percents and ignores gear when measuring the skill", () => {
    const world = {
      globals: {
        startingRealmSlug: "1",
        starterItems: [],
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
        combat: { minInterval: 0.5, challengeCooldownSeconds: 0, timeLimitSeconds: 20, defenseConstant: 1, speedBase: 100, recommendedPowerMargin: 1.05 },
      },
      realms: [
        {
          slug: "1",
          sortOrder: 1,
          nextRealmSlug: null,
          tickSeconds: 1,
          gainPerTick: 1,
          breakthroughCost: 1,
          minRateBp: 10000,
          baseRateBp: 10000,
          maxRateBp: 10000,
          requiredStageSlug: null,
          recommendedPower: 0,
          baseAttack: 10,
          baseDefense: 10,
          baseHp: 33,
          baseSpeed: 0,
          baseInterval: 1.5,
          enabled: true,
        },
      ],
      stages: [],
      dropTables: [],
      items: [{ slug: "sword", kind: "equipment", slot: "weapon", skillSlug: null, attack: 20, defense: 0, hp: 0, speed: 0, enabled: true, prerequisiteSkillSlugs: [] }],
      skills: [
        { slug: "atk", prerequisiteSkillSlugs: [], attack: 1800, defense: 0, hp: 0, enabled: true },
        { slug: "def", prerequisiteSkillSlugs: [], attack: 0, defense: 800, hp: 0, enabled: true },
      ],
    };
    const both = combatStats(world, "1", [], [
      { slug: "atk", level: 1 },
      { slug: "def", level: 1 },
    ]);
    expect(both.attack).toBeCloseTo(10 * (1 + 0.18));
    expect(both.defense).toBeCloseTo(10 * (1 + 0.08));
    const bare = combatStats(world, "1", [], [{ slug: "atk", level: 1 }]).attack;
    const armed = combatStats(world, "1", ["sword"], [{ slug: "atk", level: 1 }]).attack;
    expect(armed - bare).toBe(20);
  });

  it("turns another book into cultivation once the skill is complete", async () => {
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
      const category = await createSkillCategory(db, { displayName: "吐纳" }, null);
      const skill = await createOpsSkill(
        db,
        { displayName: "吐纳", categoryId: category.id, attack: 5, defense: 0, hp: 0, speed: 0, cultivateBonus: 0 },
        null,
      );
      const now = new Date("2026-10-10T12:00:00.000Z");
      const player = await registerPlayer(db, { username: "reader", password: "correct-horse", now });
      const bookSlug = await ensureSkillBook(db, { slug: skill.id, displayName: "吐纳" }, null);
      await db.insert(playerSkills).values({ playerId: player.playerId, skillSlug: skill.id, learnedAt: now, level: 7 });
      const [book] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: bookSlug, isStack: false, quantity: 1, source: "test", acquiredAt: now })
        .returning();
      const world = await loadCurrentWorld(db);
      if (!world || !book) {
        throw new Error("准备数据失败");
      }
      const result = await withTransaction(db, (tx) => useItem(tx, world, player.playerId, book.id, now));
      expect(result.learned).toEqual({ displayName: "吐纳", level: 7, convertedCultivation: 30 });
      const [learned] = await db.select().from(playerSkills).where(eq(playerSkills.playerId, player.playerId));
      expect(learned?.level).toBe(7);
    });
  });
});
