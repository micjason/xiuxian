import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentRealms } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import { withDb } from "../../test/db.js";
import { createOpsItem, createOpsSkill, createOpsStage, createOpsWeapon, createSkillCategory, createWeaponCategory, deleteOpsItem, deleteOpsSkill, listOpsSkills, listOpsStages, updateSkillCategory } from "./ops-content.js";

describe("ops content", () => {
  it("keeps several stages on one realm and refuses a missing mount", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({ slug: "2", displayName: "练气", sortOrder: 2, nextRealmSlug: null });
      const category = await createSkillCategory(db, { displayName: "吐纳" }, null);
      const renamed = await updateSkillCategory(db, category.id, { displayName: "吐纳心法" }, null);
      expect(renamed.id).toBe(category.id);
      const skill = await createOpsSkill(
        db,
        {
          displayName: "吐纳",
          categoryId: category.id,
          attack: 0,
          defense: 0,
          hp: 0,
          speed: 0,
          cultivateBonus: 10,
        },
        null,
      );
      const skills = await listOpsSkills(db);
      expect(skills.find((row) => row.id === skill.id)?.categoryId).toBe(category.id);
      expect(skills.find((row) => row.id === skill.id)?.categoryName).toBe("吐纳心法");
      const book = await createOpsItem(db, { displayName: "吐纳书" }, null);
      const weaponCategory = await createWeaponCategory(db, { displayName: "长剑" }, null);
      const sword = await createOpsWeapon(
        db,
        { displayName: "木剑", categoryId: weaponCategory.id, slot: "weapon", attack: 4, defense: 0, hp: 0, speed: 0 },
        null,
      );
      await expect(createOpsStage(db, { displayName: "山门", realmCode: 9 }, null)).rejects.toBeInstanceOf(AppError);
      const first = await createOpsStage(
        db,
        {
          displayName: "山门",
          realmCode: 2,
          bosses: [
            {
              name: "山贼",
              attack: 3,
              defense: 1,
              hp: 20,
              interval: 1.5,
              drops: [
                { itemId: sword.id, chancePercent: 30 },
                { itemId: book.id, chancePercent: 0.5 },
                { itemId: skill.id, chancePercent: 10 },
              ],
            },
          ],
        },
        null,
      );
      const second = await createOpsStage(db, { displayName: "后山", realmCode: 2, bosses: [] }, null);
      const rows = await listOpsStages(db);
      expect(rows.map((row) => row.displayName)).toEqual(["后山", "山门"]);
      expect(rows.every((row) => row.realmCode === 2 && row.realmName === "练气")).toBe(true);
      expect(rows.find((row) => row.id === first.id)?.bosses[0]?.drops).toEqual([
        { itemId: sword.id, displayName: "木剑", chancePercent: 30 },
        { itemId: book.id, displayName: "吐纳书", chancePercent: 0.5 },
        { itemId: skill.id, displayName: "吐纳", chancePercent: 10 },
      ]);
      await expect(
        createOpsStage(
          db,
          { displayName: "坏掉率", realmCode: 2, bosses: [{ name: "甲", attack: 1, defense: 0, hp: 1, interval: 1, drops: [{ itemId: sword.id, chancePercent: 101 }] }] },
          null,
        ),
      ).rejects.toMatchObject({ message: "掉率不能超过 100%" });
      await expect(deleteOpsItem(db, sword.id)).rejects.toMatchObject({ message: "这个物品还挂在首领上，先拿掉" });
      await expect(deleteOpsSkill(db, skill.id)).rejects.toMatchObject({ message: "这门功法还挂在首领上，先拿掉" });
      expect(second.id).not.toBe(first.id);
      const [realm] = await db.select().from(contentRealms).where(eq(contentRealms.sortOrder, 2));
      expect(realm?.displayName).toBe("练气");
    });
  });
});
