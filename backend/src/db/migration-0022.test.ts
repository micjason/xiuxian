import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { eq, sql } from "drizzle-orm";
import { contentGlobals, contentStages } from "./schema.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { withDb } from "../test/db.js";
import { loadDraftSnapshot } from "../modules/content/snapshot.js";

const text = readFileSync(new URL("../../drizzle/0022_drop_rate_5pct_stones_x2_daily5.sql", import.meta.url), "utf8");

async function runMigration(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
  for (const statement of text.split(/;\s*\n/).map((part) => part.replace(/^--.*$/gm, "").trim()).filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

describe("migration 0022 (5% kill drop, stones x2 of the original, 5 daily repeat rewards)", () => {
  it("is in the journal", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as { entries: { idx: number; tag: string }[] };
    expect(journal.entries[22]).toMatchObject({ idx: 22, tag: "0022_drop_rate_5pct_stones_x2_daily5" });
  });

  it("the seed ships the new defaults", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const stages = await db.select().from(contentStages);
      // 0024 起关卡只存改过的项：5% 是默认值，存成「跟随默认」
      expect(stages.every((row) => row.monsterDrop?.chanceBp == null)).toBe(true);
      expect((await loadDraftSnapshot(db)).stages.every((row) => row.monsterDrop?.chanceBp === 500)).toBe(true);
      const extras = stages.flatMap((row) => row.bosses.flatMap((boss) => boss.repeat?.extras ?? []));
      expect(extras.filter((e) => e.itemSlug === "enh_stone_low").map((e) => e.chanceBp)).toEqual([7000, 7000, 7000]);
      expect(extras.filter((e) => e.itemSlug === "enh_stone_mid").map((e) => e.chanceBp)).toEqual([3000, 3000]);
      const [globals] = await db.select().from(contentGlobals);
      expect(globals?.combat?.bossDailyRewardCount).toBe(5);
    });
  });

  it("only touches entries still at the old defaults", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const stages = await db.select().from(contentStages);
      // 回到旧默认（4% / 52.5% / 22.5% / 每天 3 次），再让一个关卡和一个首领条目、全局次数保持"后台改过"的值
      for (const row of stages) {
        const bosses = row.bosses.map((boss) => ({
          ...boss,
          repeat: boss.repeat ? { ...boss.repeat, extras: boss.repeat.extras.map((e) => ({ ...e, chanceBp: e.itemSlug === "enh_stone_low" ? 5250 : 2250 })) } : boss.repeat,
        }));
        await db.update(contentStages).set({ monsterDrop: { ...row.monsterDrop!, chanceBp: 400 }, bosses }).where(eq(contentStages.slug, row.slug));
      }
      await db.update(contentStages).set({ monsterDrop: { chanceBp: 450, qualityWeights: { white: 100 } } }).where(eq(contentStages.slug, "lianqi_1"));
      const [bear] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_3"));
      await db.update(contentStages).set({ bosses: bear!.bosses.map((b) => ({ ...b, repeat: { gear: true, extras: [{ itemSlug: "enh_stone_low", chanceBp: 6000, minQty: 1, maxQty: 2 }] } })) }).where(eq(contentStages.slug, "lianqi_3"));
      const [globals] = await db.select().from(contentGlobals);
      await db.update(contentGlobals).set({ combat: { ...globals!.combat!, bossDailyRewardCount: 3 } });

      await runMigration(db);

      const after = await db.select().from(contentStages);
      const bySlug = Object.fromEntries(after.map((row) => [row.slug, row]));
      expect(bySlug.lianqi_1!.monsterDrop?.chanceBp).toBe(450);
      expect(bySlug.lianqi_2!.monsterDrop?.chanceBp).toBe(500);
      expect(bySlug.lianqi_3!.bosses[0]!.repeat!.extras[0]!.chanceBp).toBe(6000);
      const zhuji = bySlug.zhuji_3!.bosses[0]!.repeat!.extras;
      expect(zhuji.map((e) => [e.itemSlug, e.chanceBp])).toEqual([["enh_stone_low", 7000], ["enh_stone_mid", 3000]]);
      const [g] = await db.select().from(contentGlobals);
      expect(g?.combat?.bossDailyRewardCount).toBe(5);

      // 后台把每日次数改成别的值：迁移不动
      await db.update(contentGlobals).set({ combat: { ...g!.combat!, bossDailyRewardCount: 4 } });
      await runMigration(db);
      const [kept] = await db.select().from(contentGlobals);
      expect(kept?.combat?.bossDailyRewardCount).toBe(4);
    });
  });
});
