import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { withDb } from "../../test/db.js";
import { contentItems } from "../../db/schema.js";
import { loadDraftSnapshot } from "./snapshot.js";
import { validateContent } from "./validate.js";
import { simulateBattle } from "../combat/battle.js";
import { computePower, ratePower } from "../combat/stats.js";
import { stageRecommendedPower } from "./stage-power.js";
import { PROTOTYPE_LAYERS, PROTOTYPE_MAJORS, PROTOTYPE_STAGES, applyPrototypeV12 } from "./prototype-v12.js";
import { REALM_FACTORY } from "./realm-factory.js";

const sim = JSON.parse(readFileSync(new URL("../../../../tools/sim/prototype-v1.2.config.json", import.meta.url), "utf8")) as {
  layers: { id: string; name: string; gainPerTick: number; costToNext: number | null; stats: Record<string, number> }[];
  stages: { id: string; name: string; monster: { name: string; hp: number; attack: number; defense: number; interval: number; killXp: number }; boss?: { id: string; hp: number; attack: number; defense: number; interval: number; recommendedPower: number } }[];
  majors: { ult: { multBp: number; cooldownSeconds: number } }[];
  gearTable: Record<string, Record<string, number>[]>;
};

const GATE_SLUGS = ["lianqi_3", "zhuji_3", "jindan_3", "yuanying_3", "huashen_3", "lianxu_3", "heti_3"] as const;

describe("prototype v1.2 content", () => {
  it("keeps the simulation config drift guard for the original 9 layers / 3 majors / overlapping stages", () => {
    expect(PROTOTYPE_LAYERS.map((row) => ({ id: row.slug, name: row.name, gainPerTick: row.gainPerTick, costToNext: row.costToNext, stats: row.stats }))).toEqual(
      sim.layers.map((row) => ({ id: row.id, name: row.name, gainPerTick: row.gainPerTick, costToNext: row.costToNext ?? null, stats: row.stats })),
    );
    expect(PROTOTYPE_MAJORS.slice(0, 3).map((row) => ({ multBp: row.ultMultBp, cooldownSeconds: row.ultCooldown }))).toEqual(sim.majors.map((row) => row.ult));
    const byId = new Map(PROTOTYPE_STAGES.map((row) => [row.slug, row]));
    for (const row of sim.stages) {
      const stage = byId.get(row.id);
      expect(stage, row.id).toBeTruthy();
      const { art: _art, ...monster } = stage!.monster;
      // 名称与小怪对照模拟表；章末首领对照表 2.3。炼气首关精英是后来手填压战力，不在原模拟表里。
      expect({ id: stage!.slug, name: stage!.name, monster }).toEqual({ id: row.id, name: row.name, monster: row.monster });
      if (row.boss) {
        expect(stage!.boss).toMatchObject({ slug: row.boss.id, hp: row.boss.hp, attack: row.boss.attack, defense: row.boss.defense, interval: row.boss.interval, recommendedPower: row.boss.recommendedPower });
      }
    }
  });

  it("ships 24 same-slug stages with a boss each, 8 chapters, and only the 7 major-end gates", async () => {
    await withDb(async (db) => {
      const seeded = await applyPrototypeV12(db);
      expect(seeded.stageSlugs).toHaveLength(24);
      expect(seeded.stageSlugs).toEqual(REALM_FACTORY.map((row) => row.slug));
      expect(seeded.realmSlugs).toEqual(REALM_FACTORY.map((row) => row.slug));
      const world = await loadDraftSnapshot(db);
      expect(world.realms).toHaveLength(24);
      expect(world.stages).toHaveLength(24);
      expect(world.stages.every((row) => (row.bosses ?? []).length === 1)).toBe(true);
      expect(world.stages.map((row) => row.slug)).toEqual(REALM_FACTORY.map((row) => row.slug));
      expect(world.realms.map((row) => row.requiredStageSlug)).toEqual(
        REALM_FACTORY.map((row) => (GATE_SLUGS as readonly string[]).includes(row.slug) ? row.slug : null),
      );
      expect(world.stages.filter((row) => row.tier === "chief").map((row) => row.slug)).toEqual([
        "lianqi_3", "zhuji_3", "jindan_3", "yuanying_3", "huashen_3", "lianxu_3", "heti_3", "dacheng_3",
      ]);
      expect(world.chapters?.map((row) => [row.slug, row.displayName, row.bgKey, row.bossFx, row.chiefStageSlug])).toEqual([
        ["heifeng", "黑风岭", "heifeng", "default", "lianqi_3"],
        ["youming", "幽冥古道", "youming", "default", "zhuji_3"],
        ["chiyan", "赤炎火山", "chiyan", "chiyan", "jindan_3"],
        ["zixiao", "紫霄秘境", "youming", "default", "yuanying_3"],
        ["shenyou", "神游泽", "heifeng", "default", "huashen_3"],
        ["taixu", "太虚谷", "youming", "default", "lianxu_3"],
        ["hedao", "合道峰", "chiyan", "chiyan", "heti_3"],
        ["daluo", "大罗天", "heifeng", "default", "dacheng_3"],
      ]);
      // 炼气首关：精英压到推荐战力 187，炼气≈187 可过
      const wolfElite = world.stages.find((row) => row.slug === "lianqi_1")!;
      expect(wolfElite.recommendedPower).toBe(187);
      expect(wolfElite.bosses![0]).toMatchObject({ name: "青鬃狼王", tier: "elite", artKey: "boss_wolf", hp: 110, attack: 8, defense: 8, interval: 1.5 });
      const weights = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };
      const reported = { attack: 14, defense: 14, hp: 49, speed: 20 };
      expect(ratePower(reported, weights)).toBe(187);
      const interval = computePower({ ...reported, baseInterval: 1.5, minInterval: 0.5, speedBase: 100, weights }).interval;
      const boss = wolfElite.bosses![0]!;
      const fight = simulateBattle(
        { attack: reported.attack, defense: reported.defense, hp: reported.hp, interval },
        { attack: boss.attack, defense: boss.defense, hp: boss.hp, interval: boss.interval },
        { timeLimitSeconds: 45, defenseConstant: 1 },
      );
      expect(fight.win).toBe(true);
      expect(wolfElite.bosses![0]!.firstClear).toEqual([{ kind: "spiritStones", amount: 50 }, { kind: "item", itemSlug: "enh_stone_low", quantity: 1 }, { kind: "gear", count: 1 }]);
      expect(stageRecommendedPower(world, wolfElite)).toBe(187);
      const check = validateContent(world);
      expect(check.errors).toEqual([]);
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
