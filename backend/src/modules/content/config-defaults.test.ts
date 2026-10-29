import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentStages } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { readConfigOverview, saveConfigOverview, saveGearParams, saveTuning } from "./config-overview.js";
import { listGear, resetGearPiece, syncGear, updateGearPiece } from "./gear.js";
import { dropMultsOf, pickSlot, pickSlotWeighted, rollBossRepeatGear, rollMonsterKillDrop } from "./monster-drops.js";
import { listOpsStages, updateOpsStage } from "./ops-content.js";
import { applyPrototypeV12 } from "./prototype-v12.js";
import { loadDraftSnapshot } from "./snapshot.js";
import { DEFAULT_TUNING, tuningOf } from "./tuning.js";

const effectiveDrop = async (db: Parameters<Parameters<typeof withDb>[0]>[0], slug: string) =>
  (await loadDraftSnapshot(db)).stages.find((row) => row.slug === slug)!.monsterDrop!;

describe("配置概览: stages inherit the global default drop, overrides stay", () => {
  it("changing the default moves every inheriting stage, a customized stage keeps its own value, restore = inherit again", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      expect(await effectiveDrop(db, "lianqi_1")).toEqual({ chanceBp: 500, qualityWeights: { white: 70, green: 25, blue: 5, purple: 0, orange: 0 } });

      // 黑风岭·二 单独把掉率改成 8%
      await updateOpsStage(db, "lianqi_2", { displayName: "黑风岭·二", realmCode: 2, bosses: [], monsterDrop: { chancePercent: 8, weights: { white: 70, green: 25, blue: 5, purple: 0 } } }, null);
      const [stage2] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_2"));
      expect(stage2!.monsterDrop).toEqual({ chanceBp: 800 });

      await saveTuning(db, { monsterDropChanceBp: 600, monsterQualityWeights: { white: 60, green: 30, blue: 10, purple: 0, orange: 0 } }, null);
      expect(await effectiveDrop(db, "lianqi_1")).toEqual({ chanceBp: 600, qualityWeights: { white: 60, green: 30, blue: 10, purple: 0, orange: 0 } });
      // 只改了掉率的关卡：掉率保持 8%，权重跟着新默认
      expect(await effectiveDrop(db, "lianqi_2")).toEqual({ chanceBp: 800, qualityWeights: { white: 60, green: 30, blue: 10, purple: 0, orange: 0 } });
      // 筑基关卡迁移时就是自定义权重：不动
      expect((await effectiveDrop(db, "zhuji_1")).qualityWeights).toEqual({ white: 50, green: 35, blue: 13, purple: 2, orange: 0 });

      const listed = (await listOpsStages(db)).find((row) => row.id === "lianqi_2")!;
      expect(listed.dropCustomCount).toBe(1);
      expect(listed.monsterDrop.chancePercent).toBe(8);
      expect(listed.dropDefaults.chancePercent).toBe(6);

      // 填回默认值 = 恢复默认
      await updateOpsStage(db, "lianqi_2", { displayName: "黑风岭·二", realmCode: 2, bosses: [], monsterDrop: { chancePercent: 6, weights: {} } }, null);
      expect((await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_2")))[0]!.monsterDrop).toBeNull();

      const overview = await readConfigOverview(db);
      expect(overview.stages.total).toBe(24);
      // 炼气跟随全局默认；其余大境界品质权重写在种子里，算已自定义
      expect(overview.stages.customized.map((row) => row.id).sort()).toEqual([
        "dacheng_1", "dacheng_2", "dacheng_3",
        "heti_1", "heti_2", "heti_3",
        "huashen_1", "huashen_2", "huashen_3",
        "jindan_1", "jindan_2", "jindan_3",
        "lianxu_1", "lianxu_2", "lianxu_3",
        "yuanying_1", "yuanying_2", "yuanying_3",
        "zhuji_1", "zhuji_2", "zhuji_3",
      ]);
    });
  });

  it("normal monsters never drop orange, even if the default says so", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      await saveTuning(db, { monsterQualityWeights: { white: 1, green: 0, blue: 0, purple: 0, orange: 1000 } }, null);
      expect((await effectiveDrop(db, "lianqi_1")).qualityWeights.orange).toBe(0);
    });
  });

  it("the config overview saves all-or-nothing", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      await expect(
        saveConfigOverview(db, { tuning: { bossOrangeChanceBp: 500 }, rules: { attackWeight: -1 } }, null),
      ).rejects.toThrow();
      const [row] = await db.select().from(contentGlobals);
      expect(tuningOf(row!.tuning).bossOrangeChanceBp).toBe(DEFAULT_TUNING.bossOrangeChanceBp);
      await expect(saveTuning(db, { slotShares: { ...DEFAULT_TUNING.slotShares, weapon: 0.3 } }, null)).rejects.toThrow("合计要等于 100%");
      const saved = await saveConfigOverview(db, { tuning: { bossOrangeChanceBp: 500, skillMaxLayers: 9 } }, null);
      expect(saved.tuning).toMatchObject({ bossOrangeChanceBp: 500, skillMaxLayers: 9 });
      expect((await loadDraftSnapshot(db)).globals.tuning?.skillMaxLayers).toBe(9);
    });
  });
});

describe("装备配置: regeneration keeps what the admin changed", () => {
  it("renaming / multiplier survive a regeneration, untouched pieces follow the defaults, reset restores everything", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const before = (await db.select().from(contentItems).where(eq(contentItems.slug, "gear_major1_weapon_blue")))[0]!;
      await updateGearPiece(db, "gear_major1_weapon_blue", { displayName: "青锋剑", dropMult: 0.5, iconKey: "gear_foundation_weapon" }, null);

      await saveGearParams(db, { gearBudgetRatio: 0.6 }, null);
      const after = (await db.select().from(contentItems).where(eq(contentItems.slug, "gear_major1_weapon_blue")))[0]!;
      expect(after.attack).toBeGreaterThan(before.attack);
      expect(after).toMatchObject({ displayName: "青锋剑", nameCustom: true, dropMult: 0.5, iconKey: "gear_foundation_weapon", description: before.description });

      // 没改过的名称跟着默认走（例如大境界改名后）
      await db.update(contentItems).set({ displayName: "旧名字" }).where(eq(contentItems.slug, "gear_major1_weapon_green"));
      await syncGear(db, null);
      expect((await db.select().from(contentItems).where(eq(contentItems.slug, "gear_major1_weapon_green")))[0]!.displayName).toBe("炼气·绿·武器");

      const listed = (await listGear(db)).majors[0]!.pieces.find((piece) => piece.id === "gear_major1_weapon_blue")!;
      expect(listed).toMatchObject({ displayName: "青锋剑", defaultName: "炼气·蓝·武器", nameCustom: true, dropMult: 0.5 });

      // 名称填回默认名 = 恢复默认
      await updateGearPiece(db, "gear_major1_weapon_blue", { displayName: "炼气·蓝·武器" }, null);
      expect((await db.select().from(contentItems).where(eq(contentItems.slug, "gear_major1_weapon_blue")))[0]!.nameCustom).toBe(false);
      await resetGearPiece(db, "gear_major1_weapon_blue", null);
      expect((await db.select().from(contentItems).where(eq(contentItems.slug, "gear_major1_weapon_blue")))[0]).toMatchObject({ dropMult: 1, iconKey: "", nameCustom: false });
      await expect(updateGearPiece(db, "gear_major1_weapon_blue", { dropMult: -1 }, null)).rejects.toThrow("掉率倍数");

      // 快照里带上掉率倍数和图标，客户端能拿到
      await updateGearPiece(db, "gear_major1_weapon_blue", { dropMult: 2, iconKey: "gear_core_weapon" }, null);
      const item = (await loadDraftSnapshot(db)).items.find((row) => row.slug === "gear_major1_weapon_blue");
      expect(item).toMatchObject({ dropMult: 2, iconKey: "gear_core_weapon" });
    });
  });
});

describe("掉率倍数: one piece's share = its multiplier ÷ the sum of the 6 pieces of the same tier and quality", () => {
  const seq = (...values: number[]) => {
    let index = 0;
    return () => values[index++] ?? 0;
  };

  it("all ×1 behaves exactly like the old uniform pick (same random call)", () => {
    const multOf = dropMultsOf([]);
    for (let roll = 0; roll < 6; roll += 1) {
      expect(pickSlotWeighted("major1", "blue", seq(roll), multOf)).toBe(pickSlot(seq(roll)));
    }
  });

  it("×0 never drops, ×2 doubles the chance, applies to monster kills and boss repeat gear alike", () => {
    const multOf = dropMultsOf([
      { slug: "gear_major1_weapon_green", dropMult: 0 },
      { slug: "gear_major1_clothes_green", dropMult: 2 },
    ]);
    const counts: Record<string, number> = {};
    // 部位掷骰范围 = 倍数之和 × 1000 = (0 + 2 + 1 × 4) × 1000
    for (let roll = 0; roll < 6000; roll += 1) {
      const slot = pickSlotWeighted("major1", "green", (min, max) => (max === 6000 ? roll : 0), multOf)!;
      counts[slot] = (counts[slot] ?? 0) + 1;
    }
    expect(counts.weapon).toBeUndefined();
    expect(counts.clothes).toBe(2000);
    expect(counts.helmet).toBe(1000);

    const config = { chanceBp: 10000, qualityWeights: { white: 0, green: 1 } };
    expect(rollMonsterKillDrop("major1", config, seq(0, 0, 0), multOf)?.slug).toBe("gear_major1_clothes_green");
    // 首领重复奖励：不出橙时同一规则（白改绿）
    expect(rollBossRepeatGear("major1", { white: 1 }, 0, seq(0, 0), multOf)?.slug).toBe("gear_major1_clothes_green");
    // 出橙：橙色 6 件也按倍数分
    const orangeMult = dropMultsOf([{ slug: "gear_major1_weapon_orange", dropMult: 0 }]);
    expect(rollBossRepeatGear("major1", { white: 1 }, 10000, seq(0, 0), orangeMult)?.slug).toBe("gear_major1_clothes_orange");
  });
});
