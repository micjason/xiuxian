/**
 * 药园分配迁移 0061：灵木物品、dongfu 系数补丁、种子掉落追加、player_dongfu。
 * when 必须 ≥ 1799100000000，且晚于 0060。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems } from "./schema.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0061_garden_allocation.sql", import.meta.url), "utf8");

async function migrate(db: TestDb) {
  for (const statement of text
    .split("--> statement-breakpoint")
    .map((part) => part.replace(/^--.*$/gm, "").trim())
    .filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

const LEGACY_DONGFU = {
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

describe("migration 0061 (药园分配)", () => {
  it("is journaled after 0060 with when ≥ 1799100000000", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string; when: number; idx: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0061_garden_allocation");
    const prev = journal.entries.find((entry) => entry.tag === "0060_dongfu_v1");
    expect(row).toBeTruthy();
    expect(prev).toBeTruthy();
    expect(row!.when).toBeGreaterThanOrEqual(1799100000000);
    expect(row!.when).toBeGreaterThan(prev!.when);
    expect(row!.idx).toBeGreaterThan(prev!.idx);
  });

  it("patches defaults once and keeps a later custom coefficient", async () => {
    await withDb(async (db) => {
      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "mortal",
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        dongfu: LEGACY_DONGFU as never,
        tuning: {
          seedDrops: [
            { itemSlug: "seed_lingcao", chanceBp: 800, minCount: 1, maxCount: 1 },
            { itemSlug: "seed_qingxin", chanceBp: 400, minCount: 1, maxCount: 1 },
          ],
        },
      });
      await migrate(db);
      await migrate(db);
      const [wood] = await db.select().from(contentItems).where(eq(contentItems.slug, "wood_lingmu"));
      expect(wood).toMatchObject({ displayName: "灵木", kind: "material", stackable: true });
      const [globals] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1));
      expect(globals?.dongfu).toMatchObject({
        plotCount: 4,
        woodItemSlug: "wood_lingmu",
        startingWood: 32,
        startingServants: 4,
        gardenReducePercent: 5,
        alchemyReducePercent: 5,
        minDurationPercent: 20,
        maxAlchemyQueue: 4,
      });
      expect(globals?.dongfu?.seeds).toHaveLength(1);
      expect(globals?.dongfu?.gardenUpgrades).toHaveLength(3);
      const drops = (globals?.tuning as { seedDrops?: { itemSlug: string }[] } | null)?.seedDrops ?? [];
      expect(drops.filter((row) => row.itemSlug === "wood_lingmu")).toHaveLength(1);
      await db.execute(sql`select 1 from player_dongfu limit 0`);

      await db
        .update(contentGlobals)
        .set({
          dongfu: { ...(globals!.dongfu as object), gardenReducePercent: 9 } as never,
        })
        .where(eq(contentGlobals.id, 1));
      await migrate(db);
      const [again] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1));
      expect(again?.dongfu?.gardenReducePercent).toBe(9);
      const dropsAgain = (again?.tuning as { seedDrops?: { itemSlug: string }[] } | null)?.seedDrops ?? [];
      expect(dropsAgain.filter((row) => row.itemSlug === "wood_lingmu")).toHaveLength(1);
    });
  });
});
