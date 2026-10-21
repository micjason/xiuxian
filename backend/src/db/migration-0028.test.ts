import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { eq, sql } from "drizzle-orm";
import { contentDropTables, contentGlobals, contentItems, contentRealms, contentStages, playerItems, players } from "./schema.js";
import { STARTING_ENHANCE_RULES, enhanceRulesFromInput } from "../modules/content/enhance.js";
import { withDb } from "../test/db.js";

/** 0028 里的数据语句（UPDATE），加列 / 删列在测试库里已经执行过。 */
function updates(): string[] {
  const text = readFileSync(new URL("../../drizzle/0028_batch2_equipment.sql", import.meta.url), "utf8");
  return text
    .split("--> statement-breakpoint")
    .map((part) => part.split("\n").filter((line) => !line.trim().startsWith("--")).join("\n").trim())
    .filter((part) => part.startsWith("UPDATE"));
}

describe("migration 0028 (去掉红、默认功法栏位)", () => {
  it("merges red into orange safely: rules drop red, red items become orange, enhance levels clamp to the orange cap, red weights drop; re-running is a no-op", async () => {
    await withDb(async (db) => {
      const raw = { ...STARTING_ENHANCE_RULES, qualities: { ...STARTING_ENHANCE_RULES.qualities, red: { cap: 18, costMult: 2, decomposeExp: 960, breakthroughs: [] } } };
      await db.insert(contentGlobals).values({ id: 1, enhance: raw as never });
      for (const [order, slug, major] of [
        [1, "lianqi_1", "lianqi"],
        [2, "lianqi_2", "lianqi"],
        [3, "zhuji_1", "zhuji"],
        [4, "jindan_1", "jindan"],
        [5, "yuanying_1", "yuanying"],
      ] as const) {
        await db.insert(contentRealms).values({ slug, displayName: slug, majorName: major, majorKey: major, sortOrder: order, breakthroughCost: 1 });
      }
      await db.insert(contentItems).values([
        { slug: "red_blade", displayName: "仙剑", kind: "equipment", slot: "weapon", quality: "red", stackable: false },
        { slug: "blue_blade", displayName: "蓝剑", kind: "equipment", slot: "weapon", quality: "blue", stackable: false },
      ]);
      const [player] = await db.insert(players).values({ username: "m28", usernameLower: "m28", passwordHash: "x" }).returning();
      const [hot] = await db.insert(playerItems).values({ playerId: player!.id, itemSlug: "red_blade", isStack: false, quantity: 1, enhanceLevel: 17, source: "test" }).returning();
      const [low] = await db.insert(playerItems).values({ playerId: player!.id, itemSlug: "red_blade", isStack: false, quantity: 1, enhanceLevel: 4, source: "test" }).returning();
      const [blue] = await db.insert(playerItems).values({ playerId: player!.id, itemSlug: "blue_blade", isStack: false, quantity: 1, enhanceLevel: 9, source: "test" }).returning();
      await db.insert(contentDropTables).values({ slug: "t", displayName: "t" });
      await db.insert(contentStages).values({
        slug: "s1",
        displayName: "关一",
        monsterDrop: { qualityWeights: { white: 50, orange: 1, red: 9 } } as never,
        bossDropTableSlug: "t",
        idleDropTableSlug: "t",
        firstClearDropTableSlug: "t",
      });

      for (let round = 0; round < 2; round += 1) {
        for (const statement of updates()) {
          await db.execute(sql.raw(statement));
        }
        const [globals] = await db.select().from(contentGlobals);
        expect(Object.keys((globals!.enhance as { qualities: object }).qualities).sort()).toEqual(["blue", "green", "orange", "purple", "white"]);
        expect(enhanceRulesFromInput(globals!.enhance)).toEqual(STARTING_ENHANCE_RULES);
        // 默认功法栏位：保持以前的玩法，第一个境界起就 3 个
        expect(globals!.artSlotRules).toEqual([{ minRealmOrder: 1, slots: 3 }]);
        const [red] = await db.select().from(contentItems).where(eq(contentItems.slug, "red_blade"));
        expect(red!.quality).toBe("orange");
        const orangeCap = STARTING_ENHANCE_RULES.qualities.orange!.cap;
        const levels = Object.fromEntries((await db.select().from(playerItems)).map((row) => [row.id, row.enhanceLevel]));
        expect(levels[hot!.id]).toBe(orangeCap);
        expect(levels[low!.id]).toBe(4);
        expect(levels[blue!.id]).toBe(9);
        const [stage] = await db.select().from(contentStages);
        expect((stage!.monsterDrop as { qualityWeights: Record<string, number> }).qualityWeights).toEqual({ white: 50, orange: 1 });
      }
    });
  });

  it("keeps skill slot rules an admin already saved", async () => {
    await withDb(async (db) => {
      await db.insert(contentGlobals).values({ id: 1, artSlotRules: [{ minRealmOrder: 1, slots: 2 }] });
      for (const statement of updates()) {
        await db.execute(sql.raw(statement));
      }
      const [globals] = await db.select().from(contentGlobals);
      expect(globals!.artSlotRules).toEqual([{ minRealmOrder: 1, slots: 2 }]);
    });
  });

  it("journal: 0028 runs after 0027, below the 0040+ range of batch 3", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as { entries: { idx: number; tag: string; when: number }[] };
    const tags = journal.entries.map((row) => row.tag);
    expect(tags.indexOf("0028_batch2_equipment")).toBeGreaterThan(tags.indexOf("0027_equipment_grants"));
    const whens = journal.entries.map((row) => row.when);
    expect([...whens].sort((a, b) => a - b)).toEqual(whens);
    expect(Math.max(...whens)).toBeLessThan(1795000000000);
  });
});
