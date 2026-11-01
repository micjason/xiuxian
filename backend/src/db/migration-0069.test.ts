/**
 * 0069 阵法日游：array_shard + arrayDaily 配表 + player_dongfu 列。
 * when 必须晚于 0068 trial（1800800000000）；本 PR 用 1800900000000。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems } from "./schema.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0069_dongfu_array_daily.sql", import.meta.url), "utf8");

async function migrate(db: TestDb) {
  for (const statement of text
    .split("--> statement-breakpoint")
    .map((part) => part.replace(/^--.*$/gm, "").trim())
    .filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

const BASE_DONGFU = {
  plotCount: 4,
  alchemyQueueLength: 2,
  seeds: [{ seedSlug: "seed_lingcao", herbSlug: "herb_lingcao", growSeconds: 60 }],
  recipes: [
    {
      recipeSlug: "pill_cultivate",
      outputItemSlug: "pill_cultivate",
      outputQty: 1,
      craftSeconds: 30,
      spiritStones: 0,
      costs: [{ itemSlug: "herb_lingcao", count: 2 }],
    },
  ],
};

describe("migration 0069 (dongfu array daily)", () => {
  it("is journaled as 0069 after 0068 trial with when > 0068", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string; when: number; idx: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0069_dongfu_array_daily");
    const prev = journal.entries.find((entry) => entry.tag === "0068_dongfu_trial_kuilei")
      ?? journal.entries.find((entry) => entry.tag === "0067_p1_dongfu_config_fields");
    expect(row).toBeTruthy();
    expect(prev).toBeTruthy();
    expect(row!.when).toBeGreaterThan(1800800000000);
    expect(row!.when).toBeGreaterThanOrEqual(1800900000000);
    expect(row!.when).toBeGreaterThan(prev!.when);
    expect(row!.idx).toBeGreaterThan(prev!.idx);
  });

  it("inserts array_shard, patches arrayDaily once, adds player columns", async () => {
    await withDb(async (db) => {
      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "mortal",
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        dongfu: BASE_DONGFU as never,
      });
      await migrate(db);
      await migrate(db);
      const [item] = await db.select().from(contentItems).where(eq(contentItems.slug, "array_shard"));
      expect(item?.displayName).toBe("阵纹残片");
      expect(item?.kind).toBe("material");
      const [globals] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1));
      const dongfu = globals?.dongfu as { arrayDaily?: { enabled?: boolean; puzzles?: { puzzleId: string }[] } };
      expect(dongfu?.arrayDaily?.enabled).toBe(true);
      expect(dongfu?.arrayDaily?.puzzles?.map((p) => p.puzzleId)).toEqual(["vein_01", "vein_02", "vein_03"]);
      await db.execute(sql`select array_xp, last_clear_day, last_puzzle_id from player_dongfu limit 0`);
    });
  });
});
