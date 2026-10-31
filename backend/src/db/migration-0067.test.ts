/**
 * P1 洞府配表铺垫 0067：globals 试炼/灵气默认值 + plots/player_dongfu 列。
 * when 必须晚于 0066_dongfu_starting_seeds（1800600000000）；本 PR 用 1800700000000。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals } from "./schema.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0067_p1_dongfu_config_fields.sql", import.meta.url), "utf8");

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

describe("migration 0067 (P1 洞府配表铺垫)", () => {
  it("is journaled after 0066 with when > 0066", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string; when: number; idx: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0067_p1_dongfu_config_fields");
    const prev = journal.entries.find((entry) => entry.tag === "0066_dongfu_starting_seeds");
    expect(row).toBeTruthy();
    expect(prev).toBeTruthy();
    expect(row!.when).toBeGreaterThan(1800600000000);
    expect(row!.when).toBeGreaterThanOrEqual(1800700000000);
    expect(row!.when).toBeGreaterThan(prev!.when);
    expect(row!.idx).toBeGreaterThan(prev!.idx);
  });

  it("patches dongfu defaults once and keeps a later custom coefficient", async () => {
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
      const [globals] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1));
      expect(globals?.dongfu).toMatchObject({
        plotCount: 4,
        alchemyTrialSlotCount: 3,
        alchemyTrialDailyLimit: 20,
        alchemyTrialExtraCostLingshi: 50,
        gardenAuraMax: 5,
        gardenAuraMatureBpPerPoint: 500,
        gardenAgeToAncientSeconds: 86400,
        auraSources: [],
      });
      await db.execute(sql`select aura, ancient_at from player_dongfu_plots limit 0`);
      await db.execute(sql`select discovered_recipe_slugs, trial_used_on_day, alchemy_xp from player_dongfu limit 0`);

      await db
        .update(contentGlobals)
        .set({
          dongfu: { ...(globals!.dongfu as object), alchemyTrialDailyLimit: 9 } as never,
        })
        .where(eq(contentGlobals.id, 1));
      await migrate(db);
      const [again] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1));
      expect((again?.dongfu as { alchemyTrialDailyLimit?: number } | null)?.alchemyTrialDailyLimit).toBe(9);
    });
  });
});
