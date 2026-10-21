import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { eq, sql } from "drizzle-orm";
import { contentGlobals, contentItems, contentStages } from "./schema.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { loadDraftSnapshot } from "../modules/content/snapshot.js";
import { withDb } from "../test/db.js";

const text = readFileSync(new URL("../../drizzle/0024_config_overview_defaults.sql", import.meta.url), "utf8");

async function runMigration(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
  for (const statement of text.split(/;\s*\n/).map((part) => part.replace(/^--.*$/gm, "").trim()).filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

describe("migration 0024 (config overview defaults: stages inherit, recommended power null = auto)", () => {
  it("is in the journal", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as { entries: { idx: number; tag: string }[] };
    expect(journal.entries[24]).toMatchObject({ idx: 24, tag: "0024_config_overview_defaults" });
  });

  it("stores only what differs from the new defaults, so effective drops are exactly the same as before", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      // 回到 0024 之前的样子：每关一整份掉落配置，推荐战力 0 = 自动
      const legacy: Record<string, unknown> = {
        lianqi_1: { chanceBp: 500, qualityWeights: { white: 70, green: 25, blue: 5, purple: 0 } },
        lianqi_2: { chanceBp: 450, qualityWeights: { white: 70, green: 25, blue: 5, purple: 0 } },
        zhuji_1: { chanceBp: 500, qualityWeights: { white: 50, green: 35, blue: 13, purple: 2 } },
        // 老数据里没写的权重 = 0：迁移后要写成显式的 0，不能变成跟随默认的 25 / 5
        jindan_1: { chanceBp: 500, qualityWeights: { white: 100 } },
      };
      for (const [slug, monsterDrop] of Object.entries(legacy)) {
        await db.update(contentStages).set({ monsterDrop: monsterDrop as never, recommendedPower: 0 }).where(eq(contentStages.slug, slug));
      }
      await db.execute(sql`UPDATE content_stages SET recommended_power = 900 WHERE slug = 'lianqi_3'`);
      await db.update(contentGlobals).set({ tuning: null });
      await db.update(contentItems).set({ displayName: "青锋剑" }).where(eq(contentItems.slug, "gear_major1_weapon_blue"));

      await runMigration(db);

      const rows = Object.fromEntries((await db.select().from(contentStages)).map((row) => [row.slug, row]));
      expect(rows.lianqi_1!.monsterDrop).toBeNull();
      expect(rows.lianqi_2!.monsterDrop).toEqual({ chanceBp: 450 });
      expect(rows.zhuji_1!.monsterDrop).toEqual({ qualityWeights: { white: 50, green: 35, blue: 13, purple: 2 } });
      expect(rows.jindan_1!.monsterDrop).toEqual({ qualityWeights: { white: 100, green: 0, blue: 0 } });
      expect(rows.lianqi_1!.recommendedPower).toBeNull();
      expect(rows.lianqi_3!.recommendedPower).toBe(900);

      const world = await loadDraftSnapshot(db);
      const effective = Object.fromEntries(world.stages.map((row) => [row.slug, row.monsterDrop]));
      expect(effective.lianqi_1).toEqual({ chanceBp: 500, qualityWeights: { white: 70, green: 25, blue: 5, purple: 0, orange: 0 } });
      expect(effective.lianqi_2?.chanceBp).toBe(450);
      expect(effective.zhuji_1?.qualityWeights).toEqual({ white: 50, green: 35, blue: 13, purple: 2, orange: 0 });
      expect(effective.jindan_1?.qualityWeights).toEqual({ white: 100, green: 0, blue: 0, purple: 0, orange: 0 });
      expect(world.stages.find((row) => row.slug === "lianqi_1")?.recommendedPower).toBe(0);

      const [sword] = await db.select().from(contentItems).where(eq(contentItems.slug, "gear_major1_weapon_blue"));
      const [plain] = await db.select().from(contentItems).where(eq(contentItems.slug, "gear_major1_weapon_green"));
      expect(sword).toMatchObject({ nameCustom: true, dropMult: 1 });
      expect(plain).toMatchObject({ nameCustom: false, dropMult: 1 });

      // 可以重复执行
      await runMigration(db);
      expect((await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_2")))[0]!.monsterDrop).toEqual({ chanceBp: 450 });
    });
  });
});
