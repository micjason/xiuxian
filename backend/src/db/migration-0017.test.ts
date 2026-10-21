import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { sql } from "drizzle-orm";
import { contentDropTables, contentGlobals, contentItems } from "../db/schema.js";
import { breakMaterialProblems, enhanceRulesFromInput, STARTING_ENHANCE_RULES } from "../modules/content/enhance.js";
import { withDb } from "../test/db.js";

const V3_RULES = {
  expBase: 60,
  expGrowth: 1.25,
  statGrowthBp: 600,
  refundBp: 8000,
  qualities: {
    white: { cap: 5, costMult: 1, decomposeExp: 30 },
    green: { cap: 8, costMult: 1.1, decomposeExp: 60 },
    blue: { cap: 10, costMult: 1.25, decomposeExp: 120 },
    purple: { cap: 12, costMult: 1.4, decomposeExp: 240 },
    orange: { cap: 15, costMult: 1.6, decomposeExp: 480 },
  },
};

/** 迁移文件里除第一句（加列，测试库已经有了）之外的语句，原样执行。 */
function dataStatements(): string[] {
  const text = readFileSync(new URL("../../drizzle/0017_enhance_red_and_breakthrough.sql", import.meta.url), "utf8");
  return text.split("--> statement-breakpoint").map((part) => part.trim()).filter((part) => part.length > 0).slice(1);
}

describe("migration 0017", () => {
  it("adds red and the starter nodes to v3 rules without touching edited numbers", async () => {
    await withDb(async (db) => {
      await db.insert(contentGlobals).values({ id: 1, enhance: { ...V3_RULES, expBase: 77 } as never });
      for (const statement of dataStatements()) {
        await db.execute(sql.raw(statement));
      }
      const [row] = await db.select().from(contentGlobals);
      const parsed = enhanceRulesFromInput(row?.enhance);
      expect(parsed).toEqual({ ...STARTING_ENHANCE_RULES, expBase: 77 });
      const items = await db.select().from(contentItems);
      expect(items.map((item) => item.slug).sort()).toEqual(["enh_stone_high", "enh_stone_low", "enh_stone_mid"]);
      expect(breakMaterialProblems(parsed, items)).toEqual([]);
      // 没有方案首领掉落表时不会写掉落
      const entries = await db.execute(sql`select count(*)::int as n from content_drop_entries`);
      expect((entries as unknown as { n: number }[])[0]?.n).toBe(0);
    });
  });

  it("keeps nodes and red that an admin already saved, and seeds drops when the scheme table exists", async () => {
    await withDb(async (db) => {
      const saved = { ...STARTING_ENHANCE_RULES, qualities: { ...STARTING_ENHANCE_RULES.qualities, red: { cap: 30, costMult: 3, decomposeExp: 5, breakthroughs: [] } } };
      await db.insert(contentGlobals).values({ id: 1, enhance: saved });
      await db.insert(contentDropTables).values({ slug: "scheme_boss", displayName: "方案首领掉落" });
      for (const statement of dataStatements()) {
        await db.execute(sql.raw(statement));
      }
      const [row] = await db.select().from(contentGlobals);
      // 0017 原样保留管理员存过的红；红在 0028 里去掉（见 migration-0028.test.ts），解析时也会忽略红
      expect((row?.enhance as { qualities: Record<string, unknown> }).qualities.red).toEqual(saved.qualities.red);
      expect(enhanceRulesFromInput(row?.enhance)).toEqual(STARTING_ENHANCE_RULES);
      const entries = await db.execute(sql`select item_slug from content_drop_entries order by item_slug`);
      expect((entries as unknown as { item_slug: string }[]).map((entry) => entry.item_slug)).toEqual(["enh_stone_high", "enh_stone_low", "enh_stone_mid"]);
      // 重复执行不报错、不重复
      for (const statement of dataStatements()) {
        await db.execute(sql.raw(statement));
      }
      const again = await db.execute(sql`select count(*)::int as n from content_drop_entries`);
      expect((again as unknown as { n: number }[])[0]?.n).toBe(3);
    });
  });
});
