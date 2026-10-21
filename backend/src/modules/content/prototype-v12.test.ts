import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { withDb } from "../../test/db.js";
import { contentItems } from "../../db/schema.js";
import { loadDraftSnapshot } from "./snapshot.js";
import { validateContent } from "./validate.js";
import { stageRecommendedPower } from "./stage-power.js";
import { PROTOTYPE_LAYERS, PROTOTYPE_MAJORS, PROTOTYPE_STAGES, applyPrototypeV12 } from "./prototype-v12.js";

const sim = JSON.parse(readFileSync(new URL("../../../../tools/sim/prototype-v1.2.config.json", import.meta.url), "utf8")) as {
  layers: { id: string; name: string; gainPerTick: number; costToNext: number | null; stats: Record<string, number> }[];
  stages: { id: string; name: string; monster: { name: string; hp: number; attack: number; defense: number; interval: number; killXp: number }; boss?: { id: string; hp: number; attack: number; defense: number; interval: number; recommendedPower: number } }[];
  majors: { ult: { multBp: number; cooldownSeconds: number } }[];
  gearTable: Record<string, Record<string, number>[]>;
};

describe("prototype v1.2 content", () => {
  it("has exactly the numbers of the simulation config (drift guard)", () => {
    expect(PROTOTYPE_LAYERS.map((row) => ({ id: row.slug, name: row.name, gainPerTick: row.gainPerTick, costToNext: row.costToNext, stats: row.stats }))).toEqual(
      sim.layers.map((row) => ({ id: row.id, name: row.name, gainPerTick: row.gainPerTick, costToNext: row.costToNext ?? null, stats: row.stats })),
    );
    // art（立绘编号，第三批）不在模拟配置里，比对时去掉
    expect(PROTOTYPE_STAGES.map((row) => ({ id: row.slug, name: row.name, monster: (({ art: _art, ...rest }) => rest)(row.monster), boss: row.boss ? { id: row.boss.slug, hp: row.boss.hp, attack: row.boss.attack, defense: row.boss.defense, interval: row.boss.interval, recommendedPower: row.boss.recommendedPower } : undefined }))).toEqual(
      sim.stages.map((row) => ({ id: row.id, name: row.name, monster: row.monster, boss: row.boss ? { id: row.boss.id, hp: row.boss.hp, attack: row.boss.attack, defense: row.boss.defense, interval: row.boss.interval, recommendedPower: row.boss.recommendedPower } : undefined })),
    );
    expect(PROTOTYPE_MAJORS.map((row) => ({ multBp: row.ultMultBp, cooldownSeconds: row.ultCooldown }))).toEqual(sim.majors.map((row) => row.ult));
  });

  it("seeds a valid world: 9 layers, 3 majors, 9 stages, 3 bosses, major gates, generated gear equal to table 3.1", async () => {
    await withDb(async (db) => {
      const seeded = await applyPrototypeV12(db);
      expect(seeded.realmSlugs).toHaveLength(9);
      const world = await loadDraftSnapshot(db);
      expect(world.realms.map((row) => row.requiredStageSlug)).toEqual([null, null, "lianqi_3", null, null, "zhuji_3", null, null, null]);
      expect(world.realms.filter((row) => (row.ultDamageMultBp ?? 0) > 0)).toHaveLength(9);
      // 第三批：每关都有首领；每章最后一关是章末（大首领），其余是本关小怪的精英版
      expect(world.stages.filter((row) => (row.bosses ?? []).length !== 1)).toEqual([]);
      expect(world.stages.filter((row) => row.tier === "chief").map((row) => row.slug)).toEqual(["lianqi_3", "zhuji_3", "jindan_3"]);
      expect(world.chapters?.map((row) => [row.slug, row.displayName, row.bgKey, row.bossFx, row.chiefStageSlug])).toEqual([
        ["heifeng", "黑风岭", "heifeng", "default", "lianqi_3"],
        ["youming", "幽冥古道", "youming", "default", "zhuji_3"],
        ["chiyan", "赤炎火山", "chiyan", "chiyan", "jindan_3"],
      ]);
      const wolfElite = world.stages.find((row) => row.slug === "lianqi_1")!.bosses![0]!;
      expect(wolfElite).toMatchObject({ name: "精英·青鬃狼", tier: "elite", artKey: "wolf", hp: 550, attack: 31, defense: 17, interval: 1.5 });
      expect(wolfElite.firstClear).toEqual([{ kind: "spiritStones", amount: 50 }, { kind: "item", itemSlug: "enh_stone_low", quantity: 1 }, { kind: "gear", count: 1 }]);
      const check = validateContent(world);
      expect(check.errors).toEqual([]);
      // 装备生成器 + 速度比例 0.3，和数值表 3.1 的小数一致
      const items = await db.select().from(contentItems);
      const piece = (major: number, slot: string, quality = "white") => items.find((row) => row.slug === `gear_major${major}_${slot}_${quality}`);
      for (const [slot, rows] of Object.entries(sim.gearTable).filter(([key]) => !key.startsWith("_"))) {
        [1, 4, 7].forEach((major, index) => {
          for (const [stat, value] of Object.entries(rows[index]!)) {
            expect(piece(major, slot)?.[stat as "attack"], `${slot} ${stat} major${major}`).toBeCloseTo(value, 2);
          }
        });
      }
    });
  });

  it("ships the hand-filled recommended power of table 2.3 (900 / 2450 / 6590), not the boss-derived value", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const world = await loadDraftSnapshot(db);
      const power = (slug: string) => stageRecommendedPower(world, world.stages.find((row) => row.slug === slug)!);
      expect([power("lianqi_3"), power("zhuji_3"), power("jindan_3")]).toEqual([900, 2450, 6590]);
    });
  });
});
