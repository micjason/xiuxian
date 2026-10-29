/**
 * 迁移 0047：洞府种子掉落物品占位 + stages.seed_drops 列 + tuning.seedDrops 默认。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentStages } from "./schema.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { DEFAULT_SEED_DROPS } from "../modules/content/seed-drops.js";
import { tuningOf } from "../modules/content/tuning.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0047_dongfu_seed_drops.sql", import.meta.url), "utf8");

async function migrate(db: TestDb) {
  for (const statement of text.split("--> statement-breakpoint").map((part) => part.replace(/^--.*$/gm, "").trim()).filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

describe("migration 0047 (洞府种子掉落)", () => {
  it("is in the journal after 0046 with when 1795000700000 (before lead 0050+ and 洞府 0060+)", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { idx: number; tag: string; when: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0047_dongfu_seed_drops");
    const prev = journal.entries.find((entry) => entry.tag === "0046_boss_names_art_battle_bg");
    const next = journal.entries.find((entry) => entry.tag === "0050_refine_essence");
    expect(row?.when).toBe(1795000700000);
    expect(row!.when).toBeGreaterThan(prev!.when);
    expect(row!.when).toBeLessThan(next!.when);
  });

  it("inserts seed/herb/pill stubs, adds seed_drops column, writes tuning.seedDrops; running twice is safe", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      await db.execute(sql.raw(`ALTER TABLE "content_stages" DROP COLUMN IF EXISTS "seed_drops"`));
      const [globalsBefore] = await db.select().from(contentGlobals);
      const tuningBefore = { ...(globalsBefore!.tuning as object) } as Record<string, unknown>;
      delete tuningBefore.seedDrops;
      await db.update(contentGlobals).set({ tuning: tuningBefore as never });

      await migrate(db);
      await migrate(db);

      const slugs = (await db.select({ slug: contentItems.slug }).from(contentItems)).map((row) => row.slug);
      for (const slug of ["seed_lingcao", "seed_qingxin", "herb_lingcao", "herb_qingxin", "pill_cultivate", "pill_atk_temp", "pill_def_temp"]) {
        expect(slugs).toContain(slug);
      }
      const [seed] = await db.select().from(contentItems).where(eq(contentItems.slug, "seed_lingcao"));
      expect(seed).toMatchObject({ kind: "material", stackable: true, displayName: "灵草种子" });
      const [pill] = await db.select().from(contentItems).where(eq(contentItems.slug, "pill_atk_temp"));
      expect(pill).toMatchObject({ kind: "pill", stackable: true });

      const [globals] = await db.select().from(contentGlobals);
      expect(tuningOf(globals!.tuning).seedDrops).toEqual(DEFAULT_SEED_DROPS);

      // column exists (nullable)
      await db.update(contentStages).set({ seedDrops: [] }).where(eq(contentStages.slug, "lianqi_1"));
      const [stage] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_1"));
      expect(stage!.seedDrops).toEqual([]);
    });
  });
});
