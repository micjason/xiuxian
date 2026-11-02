/**
 * 迁移 0071：紫/橙掉率提高；清关卡品质权重覆盖以跟随全局。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentStages } from "./schema.js";
import { DEFAULT_BOSS_RULES } from "../modules/content/boss-rules.js";
import { DEFAULT_TUNING } from "../modules/content/tuning.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0071_drop_rates_orange_purple.sql", import.meta.url), "utf8");

async function migrate(db: TestDb) {
  for (const statement of text.split("--> statement-breakpoint").map((part) => part.replace(/^--.*$/gm, "").trim()).filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

describe("migration 0071 (掉率：紫橙提高)", () => {
  it("is in the journal right after 0070", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { idx: number; tag: string; when: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0071_drop_rates_orange_purple");
    const prev = journal.entries.find((entry) => entry.tag === "0070_realm_stage_gates");
    expect(row?.when).toBe(1801100000000);
    expect(row!.when).toBeGreaterThan(prev!.when);
  });

  it("writes new factory quality tables and clears stage qualityWeights; running twice is a no-op", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      await db.update(contentGlobals).set({
        tuning: {
          ...DEFAULT_TUNING,
          monsterQualityWeights: { white: 60, green: 20, blue: 15, purple: 5, orange: 0 },
          bossRules: {
            ...DEFAULT_BOSS_RULES,
            gearQualityPct: { white: 0, green: 50, blue: 25, purple: 15, orange: 10 },
            repeatGearQualityPct: { white: 0, green: 40, blue: 30, purple: 20, orange: 10 },
          },
        } as never,
      });
      await db
        .update(contentStages)
        .set({ monsterDrop: { chanceBp: 500, qualityWeights: { white: 50, green: 25, blue: 20, purple: 10 } } as never })
        .where(eq(contentStages.slug, "lianqi_3"));

      await migrate(db);
      const [once] = await db.select().from(contentGlobals);
      const tuning = once!.tuning as {
        monsterQualityWeights: Record<string, number>;
        bossRules: { gearQualityPct: Record<string, number>; repeatGearQualityPct: Record<string, number> };
      };
      expect(tuning.monsterQualityWeights).toEqual(DEFAULT_TUNING.monsterQualityWeights);
      expect(tuning.bossRules.gearQualityPct).toEqual(DEFAULT_BOSS_RULES.gearQualityPct);
      expect(tuning.bossRules.repeatGearQualityPct).toEqual(DEFAULT_BOSS_RULES.repeatGearQualityPct);
      const [stage] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_3"));
      expect(stage!.monsterDrop).toEqual({ chanceBp: 500 });

      await migrate(db);
      const [twice] = await db.select().from(contentGlobals);
      expect(twice!.tuning).toEqual(once!.tuning);
    });
  });
});
