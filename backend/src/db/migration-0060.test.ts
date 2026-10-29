/**
 * 洞府 v1 迁移 0060：药园/炼丹表、物品、dongfu 配置、effect 列。
 * when ≥ 1800000000000，避开 0053–0059（强化线）。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems } from "./schema.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0060_dongfu_v1.sql", import.meta.url), "utf8");

async function migrate(db: TestDb) {
  for (const statement of text
    .split("--> statement-breakpoint")
    .map((part) => part.replace(/^--.*$/gm, "").trim())
    .filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

describe("migration 0060 (洞府 v1)", () => {
  it("is in the journal after 0052 and uses 0060+ when (≥1800000000000)", () => {
    const journal = JSON.parse(
      readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8"),
    ) as { entries: { tag: string; when: number }[] };
    const row = journal.entries.find((entry) => entry.tag === "0060_dongfu_v1");
    const prev = journal.entries.find((entry) => entry.tag === "0052_global_base_interval");
    expect(row).toBeTruthy();
    expect(prev).toBeTruthy();
    expect(row!.when).toBeGreaterThanOrEqual(1800000000000);
    expect(row!.when).toBeGreaterThan(prev!.when);
    // 0053–0059 留给强化线：本迁移 when 必须高于 1799…
    expect(row!.when).toBeGreaterThanOrEqual(1799000000000);
  });

  it("seeds items, dongfu defaults, and is idempotent", async () => {
    await withDb(async (db) => {
      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "mortal",
        offlineCapSeconds: 3600,
        bagCapacity: 20,
      });
      await migrate(db);
      await migrate(db);
      const items = await db
        .select()
        .from(contentItems)
        .where(
          sql`${contentItems.slug} in ('seed_lingcao','seed_qingxin','herb_lingcao','herb_qingxin','pill_cultivate','pill_atk_temp','pill_def_temp')`,
        );
      expect(items).toHaveLength(7);
      const pill = items.find((row) => row.slug === "pill_cultivate");
      expect(pill?.effect).toMatchObject({ cultivationGain: 100 });
      const atk = items.find((row) => row.slug === "pill_atk_temp");
      expect(atk?.effect).toMatchObject({ buffStat: "attack", buffBp: 1000, durationSeconds: 300 });
      const [globals] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1));
      expect(globals?.dongfu).toMatchObject({ plotCount: 4, alchemyQueueLength: 2 });
      expect(globals?.dongfu?.seeds).toHaveLength(2);
      expect(globals?.dongfu?.recipes).toHaveLength(3);
      await db.execute(sql`select 1 from player_dongfu_plots limit 0`);
      await db.execute(sql`select 1 from player_dongfu_alchemy limit 0`);
      await db.execute(sql`select 1 from player_active_buffs limit 0`);
    });
  });
});
