import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentItems, contentSkillCategories, contentSkills } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { STARTING_BREAK_MATERIALS } from "./enhance.js";
import { createOpsItem, createOpsSkill, listOpsItems, listOpsSkills, updateOpsItem, updateOpsSkill } from "./ops-content.js";
import { applyPrototypeV12 } from "./prototype-v12.js";

describe("后台保存物品 / 功法不能清空原有字段（审计 #6）", () => {
  it("editing a 突破石's text keeps it a stackable material with its quality", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const stone = STARTING_BREAK_MATERIALS[0]!;
      const [before] = await db.select().from(contentItems).where(eq(contentItems.slug, stone.slug));
      expect(before!.kind).toBe("material");

      // 旧后台只发名称和描述
      await updateOpsItem(db, stone.slug, { displayName: `${stone.displayName}`, description: "改了描述" }, null);
      const [after] = await db.select().from(contentItems).where(eq(contentItems.slug, stone.slug));
      expect(after).toMatchObject({ kind: "material", quality: before!.quality, stackable: true, description: "改了描述" });

      const listed = (await listOpsItems(db)).find((row) => row.id === stone.slug)!;
      expect(listed).toMatchObject({ kind: "material", quality: before!.quality, stackable: true });
    });
  });

  it("item type / quality / stackable can be set explicitly and are validated; new items default to a material", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const { id } = await createOpsItem(db, { displayName: "回气丹" }, null);
      expect((await db.select().from(contentItems).where(eq(contentItems.slug, id)))[0]).toMatchObject({ kind: "material", quality: "white", stackable: true });
      await updateOpsItem(db, id, { displayName: "回气丹", kind: "pill", quality: "blue", stackable: false }, null);
      expect((await db.select().from(contentItems).where(eq(contentItems.slug, id)))[0]).toMatchObject({ kind: "pill", quality: "blue", stackable: false });
      await expect(updateOpsItem(db, id, { displayName: "回气丹", kind: "equipment" }, null)).rejects.toThrow("物品类型");
      await expect(updateOpsItem(db, id, { displayName: "回气丹", quality: "gold" }, null)).rejects.toThrow("品质");
    });
  });

  it("saving a 功法 keeps its type, rank, realm and prerequisites unless they are sent", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      expect((await db.select().from(contentSkillCategories)).map((row) => row.slug)).toEqual(["cat_heart"]);
      const rows = await db.select().from(contentSkills);
      const first = rows.find((row) => row.slug === "skill_tuna");
      const second = rows.find((row) => row.slug === "skill_qingyuan");
      if (!first || !second) {
        throw new Error("缺少默认技能");
      }
      await db.update(contentSkills).set({ prerequisiteSkillSlugs: [first!.slug], rank: "xuan", requiredRealmOrder: 4 }).where(eq(contentSkills.slug, second!.slug));

      await updateOpsSkill(db, second!.slug, { displayName: second!.displayName, description: "新说明", categoryId: "cat_heart", attack: 0, defense: 0, hp: 0, cultivateBonus: second!.cultivateBonusBp }, null);
      const [after] = await db.select().from(contentSkills).where(eq(contentSkills.slug, second!.slug));
      expect(after).toMatchObject({ role: "heart", rank: "xuan", requiredRealmOrder: 4, prerequisiteSkillSlugs: [first!.slug], description: "新说明" });

      const listed = (await listOpsSkills(db)).find((row) => row.id === second!.slug)!;
      expect(listed).toMatchObject({ role: "heart", rank: "xuan", requiredRealmCode: 4, prerequisiteIds: [first!.slug] });

      // 显式改：清空前置、换类型
      await updateOpsSkill(db, second!.slug, { displayName: second!.displayName, categoryId: "cat_heart", attack: 0, defense: 0, hp: 0, cultivateBonus: 0, role: "attack", prerequisiteIds: [] }, null);
      expect((await db.select().from(contentSkills).where(eq(contentSkills.slug, second!.slug)))[0]).toMatchObject({ role: "attack", prerequisiteSkillSlugs: [] });

      await expect(updateOpsSkill(db, second!.slug, { displayName: "x", categoryId: "cat_heart", attack: 0, defense: 0, hp: 0, cultivateBonus: 0, prerequisiteIds: [second!.slug] }, null)).rejects.toThrow("自己");
      await expect(updateOpsSkill(db, second!.slug, { displayName: "x", categoryId: "cat_heart", attack: 0, defense: 0, hp: 0, cultivateBonus: 0, prerequisiteIds: ["nope"] }, null)).rejects.toThrow("不存在");
      await expect(updateOpsSkill(db, second!.slug, { displayName: "x", categoryId: "cat_heart", attack: 0, defense: 0, hp: 0, cultivateBonus: 0, role: "magic" }, null)).rejects.toThrow("类型");
      await expect(updateOpsSkill(db, second!.slug, { displayName: "x", categoryId: "cat_heart", attack: 0, defense: 0, hp: 0, cultivateBonus: 0, castMode: "manual" }, null)).rejects.toThrow("自动或被动");

      await updateOpsSkill(db, second!.slug, { displayName: second!.displayName, categoryId: "cat_heart", attack: 0, defense: 0, hp: 0, cultivateBonus: 0, fxType: "ice", castMode: "passive", fx: { type: "ice", primary: "#B9F3FF", secondary: "#3D8BFF", scale: 1 } }, null);
      expect((await db.select().from(contentSkills).where(eq(contentSkills.slug, second!.slug)))[0]).toMatchObject({ fxType: "ice", castMode: "passive" });
      expect((await listOpsSkills(db)).find((row) => row.id === second!.slug)).toMatchObject({ fxType: "ice", castMode: "passive" });

      const { id } = await createOpsSkill(db, { displayName: "新功法", categoryId: "cat_heart", attack: 1, defense: 0, hp: 0, cultivateBonus: 0, role: "body", prerequisiteIds: [first!.slug] }, null);
      expect((await db.select().from(contentSkills).where(eq(contentSkills.slug, id)))[0]).toMatchObject({ role: "body", prerequisiteSkillSlugs: [first!.slug] });
    });
  });
});
