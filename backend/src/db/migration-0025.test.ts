import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { sql } from "drizzle-orm";
import { contentSkillCategories, contentSkills, playerNotices, players, popupTypes } from "./schema.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { withDb } from "../test/db.js";

const text = readFileSync(new URL("../../drizzle/0025_heart_category_notices.sql", import.meta.url), "utf8");

async function runMigration(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
  for (const statement of text.split(/;\s*\n/).map((part) => part.replace(/^--.*$/gm, "").trim()).filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

describe("migration 0025 (「心法」 category, drop the income popup)", () => {
  it("is in the journal", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as { entries: { idx: number; tag: string }[] };
    expect(journal.entries[25]).toMatchObject({ idx: 25, tag: "0025_heart_category_notices" });
  });

  it("puts the uncategorized heart skills under a new 「心法」 category and removes income notices; running twice changes nothing", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      // 回到线上的样子：没有分类
      await db.update(contentSkills).set({ skillCategorySlug: null });
      await db.delete(contentSkillCategories);
      await db.insert(popupTypes).values([
        { slug: "announcement", priority: 2, enabled: true, template: "acknowledge" },
        { slug: "income", priority: 3, enabled: true, template: "reward" },
      ]);
      const [player] = await db.insert(players).values({ username: "m25", usernameLower: "m25", passwordHash: "x" }).returning();
      await db.insert(playerNotices).values({ playerId: player!.id, noticeId: "income-1", type: "income", priority: 3, template: "reward", triggeredAt: new Date(), payload: {} });

      await runMigration(db);
      await runMigration(db);

      const categories = await db.select().from(contentSkillCategories);
      expect(categories).toHaveLength(1);
      expect(categories[0]).toMatchObject({ slug: "cat_heart", displayName: "心法" });
      const skills = await db.select().from(contentSkills);
      expect(skills.length).toBe(3);
      expect(skills.every((row) => row.skillCategorySlug === "cat_heart")).toBe(true);
      expect((await db.select().from(popupTypes)).map((row) => row.slug)).toEqual(["announcement"]);
      expect(await db.select().from(playerNotices)).toEqual([]);
    });
  });
});
