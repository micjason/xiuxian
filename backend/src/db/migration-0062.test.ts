/**
 * 迁移 0062：content_skills 增加表现字段，并播种至少 8 条默认可玩技能。
 * when 必须 ≥ 1800200000000，且晚于 0061。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { DEFAULT_SKILLS } from "../modules/content/default-skills.js";
import { contentItems, contentSkills } from "./schema.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0062_outfit_skill_defaults.sql", import.meta.url), "utf8");

async function migrate(db: TestDb) {
  for (const statement of text
    .split("--> statement-breakpoint")
    .map((part) => part.replace(/^--.*$/gm, "").trim())
    .filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

describe("migration 0062 (技能表现与换装种子技能)", () => {
  it("is journaled after 0061 with when ≥ 1800200000000", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string; when: number; idx: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0062_outfit_skill_defaults");
    const prev = journal.entries.find((entry) => entry.tag === "0061_garden_allocation");
    expect(row).toBeTruthy();
    expect(prev).toBeTruthy();
    expect(row!.when).toBeGreaterThanOrEqual(1800200000000);
    expect(row!.when).toBeGreaterThan(prev!.when);
    expect(row!.idx).toBeGreaterThan(prev!.idx);
    expect(text).not.toContain("'manual'");
    expect(text).not.toMatch(/'[^']*大招[^']*'/);
  });

  it("adds columns, seeds real fx types, and does not overwrite a later edit", async () => {
    await withDb(async (db) => {
      await migrate(db);
      await migrate(db);
      const rows = await db.select().from(contentSkills);
      expect(rows.length).toBeGreaterThanOrEqual(8);
      for (const skill of DEFAULT_SKILLS) {
        const row = rows.find((item) => item.slug === skill.slug);
        expect(row).toMatchObject({
          fxType: skill.fxType,
          castMode: skill.castMode,
          fx: skill.fx,
        });
        expect(row?.castMode === "auto" || row?.castMode === "passive").toBe(true);
      }
      const books = await db.select().from(contentItems).where(eq(contentItems.kind, "skill_book"));
      expect(books.length).toBeGreaterThanOrEqual(8);
      expect(books.every((book) => book.description.includes("学会技能"))).toBe(true);

      await db.update(contentSkills).set({ fxType: "fire", castMode: "passive" }).where(eq(contentSkills.slug, "skill_hanbing"));
      await migrate(db);
      const [kept] = await db.select().from(contentSkills).where(eq(contentSkills.slug, "skill_hanbing"));
      expect(kept).toMatchObject({ fxType: "fire", castMode: "passive" });
    });
  });
});
