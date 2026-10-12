import { describe, expect, it } from "vitest";
import { contentGlobals, contentRealms } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { createOpsItem, createOpsSkill, createOpsWeapon, createSkillCategory, createWeaponCategory } from "../content/ops-content.js";
import { loadDraftSnapshot } from "../content/snapshot.js";
import { combatStats, explainPlayerPower } from "./actions.js";

describe("player power source", () => {
  it("counts reached realms and worn gear, and shows the rounding", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values([
        { slug: "1", displayName: "凡人", sortOrder: 1, nextRealmSlug: null, baseAttack: 10, baseHp: 100, baseInterval: 1.5 },
        { slug: "2", displayName: "练气", sortOrder: 2, nextRealmSlug: null, baseAttack: 10, baseHp: 50, baseInterval: 1.5 },
        { slug: "3", displayName: "筑基", sortOrder: 3, nextRealmSlug: null, baseAttack: 100, baseHp: 100, baseInterval: 1.5 },
      ]);
      await db.insert(contentGlobals).values({
        id: 1,
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        powerWeights: { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 },
        combat: {
          minInterval: 0.7,
          playerDefenseFactor: 0.4,
          bossDefenseFactor: 0.5,
          challengeCooldownSeconds: 3,
          timeLimitSeconds: 60,
          playerDamageFloor: 1,
          bossDamageFloor: 0,
          speedBase: 100,
        },
      });
      const weaponCategory = await createWeaponCategory(db, { displayName: "剑" }, null);
      const sword = await createOpsWeapon(db, { displayName: "木剑", categoryId: weaponCategory.id, attack: 25, defense: 0, hp: 0, speed: 0 }, null);
      const herb = await createOpsItem(db, { displayName: "灵芝" }, null);
      const skillCategory = await createSkillCategory(db, { displayName: "吐纳" }, null);
      const skill = await createOpsSkill(
        db,
        { displayName: "吐纳", categoryId: skillCategory.id, attack: 0, defense: 0, hp: 0, speed: 0, cultivateBonus: 0 },
        null,
      );
      const world = await loadDraftSnapshot(db);
      const explained = explainPlayerPower(
        world,
        "2",
        [
          { itemSlug: sword.id, equippedSlot: "weapon", quantity: 1 },
          { itemSlug: herb.id, equippedSlot: null, quantity: 2 },
        ],
        [{ skillSlug: skill.id, runningSlot: null, level: 1 }],
      );
      const played = combatStats(world, "2", [sword.id], []);
      expect(explained.power).toBe(played.power);
      expect(explained.power).toBe(51);
      expect(explained.lines.filter((line) => line.counted).map((line) => line.name)).toEqual(["凡人", "练气", "木剑"]);
      expect(explained.lines.find((line) => line.name.startsWith("灵芝"))).toMatchObject({ counted: false, note: "在背包，不算战力" });
      expect(explained.lines.find((line) => line.name.startsWith("吐纳"))).toMatchObject({ counted: false, note: "没有运转，不算战力" });
      expect(explained.lines.some((line) => line.name === "筑基")).toBe(false);
      expect(explained.steps.at(-1)).toBe("45 + 0 + 6 + 0 = 51，四舍五入后战力 51");
    });
  });
});
