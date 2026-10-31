import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals } from "./schema.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0066_dongfu_starting_seeds.sql", import.meta.url), "utf8");

async function migrate(db: TestDb) {
  for (const statement of text
    .split("--> statement-breakpoint")
    .map((part) => part.replace(/^--.*$/gm, "").trim())
    .filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

describe("migration 0066 dongfu starting seeds", () => {
  it("is journaled after 0065", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string; when: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0066_dongfu_starting_seeds");
    const prev = journal.entries.find((entry) => entry.tag === "0065_drop_realm_ult");
    expect(row).toBeTruthy();
    expect(prev).toBeTruthy();
    expect(row!.when).toBeGreaterThan(prev!.when);
  });

  it("adds seeds_granted and patches startingSeeds once", async () => {
    await withDb(async (db) => {
      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "mortal",
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        dongfu: {
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
        } as never,
      });
      await migrate(db);
      await migrate(db);
      await db.execute(sql`select seeds_granted from player_dongfu limit 0`);
      const [globals] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1));
      expect(globals?.dongfu).toMatchObject({
        startingSeeds: [
          { itemSlug: "seed_lingcao", quantity: 8 },
          { itemSlug: "seed_qingxin", quantity: 4 },
        ],
      });
      expect((globals?.dongfu as { seedOffers?: unknown[] } | null)?.seedOffers).toHaveLength(2);
    });
  });
});
