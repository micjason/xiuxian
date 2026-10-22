import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentRealms, playerItems, playerStates } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import {
  breakMaterialProblems,
  decomposeEnhanceExp,
  nextBreakNode,
  pendingBreakNode,
  STARTING_BREAK_MATERIALS,
  enhanceCap,
  enhanceCost,
  enhanceInvested,
  enhanceRulesFromInput,
  enhancedStat,
  STARTING_ENHANCE_RULES,
} from "../content/enhance.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { decomposeItem, enhanceItem, readState } from "./actions.js";

describe("enhance rules (pure)", () => {
  const rules = STARTING_ENHANCE_RULES;
  it("grows the cost every level and caps by quality", () => {
    expect(enhanceCost(rules, "white", 0)).toBe(60);
    expect(enhanceCost(rules, "white", 1)).toBe(75);
    expect(enhanceCost(rules, "white", 4)).toBe(Math.round(60 * 1.25 ** 4));
    expect(enhanceCost(rules, "orange", 0)).toBe(96);
    expect(enhanceCap(rules, "white")).toBe(5);
    expect(enhanceCap(rules, "orange")).toBe(15);
    expect(enhanceInvested(rules, "white", 0)).toBe(0);
    expect(enhanceInvested(rules, "white", 2)).toBe(60 + 75);
  });
  it("scales stats linearly per level and refunds part of the invested exp", () => {
    expect(enhancedStat(100, 0, rules)).toBe(100);
    expect(enhancedStat(100, 5, rules)).toBe(130);
    expect(decomposeEnhanceExp(rules, "white", 0)).toBe(30);
    expect(decomposeEnhanceExp(rules, "white", 2)).toBe(30 + Math.floor((135 * 8000) / 10000));
  });
  it("rejects missing or broken rules instead of guessing", () => {
    expect(() => enhanceRulesFromInput(null)).toThrow();
    expect(() => enhanceRulesFromInput({ ...rules, qualities: { ...rules.qualities, blue: { cap: 0, costMult: 1, decomposeExp: 1 } } })).toThrow();
    expect(() => enhanceRulesFromInput({ ...rules, expGrowth: 0.5 })).toThrow();
    expect(() => enhanceRulesFromInput({ ...rules, refundBp: 20000 })).toThrow();
  });
});

describe("enhance rules: configurable, red quality, break-through nodes", () => {
  const rules = STARTING_ENHANCE_RULES;
  it("ships five qualities (white → orange, no red) whose nodes all pass the strict check", () => {
    const parsed = enhanceRulesFromInput(rules);
    expect(Object.keys(parsed.qualities)).toEqual(["white", "green", "blue", "purple", "orange"]);
    expect(enhanceCap(parsed, "orange")).toBe(15);
    expect(breakMaterialProblems(parsed, STARTING_BREAK_MATERIALS.map((row) => ({ slug: row.slug, kind: "material", enabled: true })))).toEqual([]);
    // 老数据里残留的红色规则读的时候直接忽略
    const legacy = enhanceRulesFromInput({ ...rules, qualities: { ...rules.qualities, red: { cap: 18, costMult: 2, decomposeExp: 960, breakthroughs: [] } } } as never);
    expect(Object.keys(legacy.qualities)).not.toContain("red");
  });
  it("lets every quality override the exp growth and the per-level stat growth", () => {
    const custom = enhanceRulesFromInput({
      ...rules,
      qualities: { ...rules.qualities, orange: { ...rules.qualities.orange, expGrowth: 2, statGrowthBp: 1000, cap: 4, breakthroughs: [] } },
    });
    expect(enhanceCost(custom, "orange", 3)).toBe(Math.round(60 * 2 ** 3 * 1.6));
    expect(enhancedStat(100, 4, custom, "orange")).toBe(140);
    // 其他品质仍用通用值
    expect(enhanceCost(custom, "white", 3)).toBe(Math.round(60 * 1.25 ** 3));
    expect(enhancedStat(100, 4, custom, "white")).toBe(124);
    expect(() => enhanceRulesFromInput({ ...rules, qualities: { ...rules.qualities, purple: { ...rules.qualities.purple, expGrowth: 0.9 } } })).toThrow(/不能小于 1/);
  });
  it("requires all five qualities when saving but tolerates an old snapshot missing one at runtime", () => {
    const { orange: _orange, ...withoutOrange } = rules.qualities;
    expect(() => enhanceRulesFromInput({ ...rules, qualities: withoutOrange })).toThrow(/橙品质强化上限/);
    const lenient = enhanceRulesFromInput({ ...rules, qualities: withoutOrange }, { requireAll: false });
    expect(enhanceCap(lenient, "purple")).toBe(12);
    expect(() => enhanceCap(lenient, "orange")).toThrow(/还没有橙品质的强化规则/);
  });
  it("validates break-through nodes", () => {
    const withNodes = (breakthroughs: unknown) => ({ ...rules, qualities: { ...rules.qualities, orange: { ...rules.qualities.orange, breakthroughs } } });
    const stone = [{ itemSlug: "enh_stone_low", count: 1 }];
    expect(() => enhanceRulesFromInput(withNodes([{ level: 15, materials: stone }]))).toThrow(/必须小于等级上限/);
    expect(() => enhanceRulesFromInput(withNodes([{ level: 5, materials: stone }, { level: 5, materials: stone }]))).toThrow(/重复/);
    expect(() => enhanceRulesFromInput(withNodes([{ level: 5, materials: [] }]))).toThrow(/至少要有一种材料/);
    expect(() => enhanceRulesFromInput(withNodes([{ level: 5, materials: [{ itemSlug: "enh_stone_low", count: 0 }] }]))).toThrow(/必须大于 0/);
    expect(() => enhanceRulesFromInput(withNodes([{ level: 5, materials: [{ itemSlug: "", count: 1 }] }]))).toThrow(/没选材料/);
    // 节点按等级排序，不要求按 5 的倍数
    const sorted = enhanceRulesFromInput(withNodes([{ level: 7, materials: stone }, { level: 3, materials: stone }]));
    expect(sorted.qualities.orange?.breakthroughs.map((node) => node.level)).toEqual([3, 7]);
  });
  it("checks break-through materials exist and are not gear", () => {
    const parsed = enhanceRulesFromInput(rules);
    const problems = breakMaterialProblems(parsed, [
      { slug: "enh_stone_low", kind: "material" },
      { slug: "enh_stone_mid", kind: "equipment" },
    ]);
    expect(problems.some((line) => line.includes("enh_stone_mid") && line.includes("不能是装备"))).toBe(true);
    // 去掉红以后默认规则不再用上品突破石，所以不会报它缺
    expect(problems.some((line) => line.includes("enh_stone_high"))).toBe(false);
  });
  it("blocks only while the gear sits exactly on an unbroken node", () => {
    const parsed = enhanceRulesFromInput(rules);
    expect(pendingBreakNode(parsed, "orange", 4, 0)).toBeNull();
    expect(pendingBreakNode(parsed, "orange", 5, 0)?.level).toBe(5);
    expect(pendingBreakNode(parsed, "orange", 5, 5)).toBeNull();
    expect(pendingBreakNode(parsed, "orange", 8, 0)).toBeNull();
    expect(pendingBreakNode(parsed, "orange", 10, 5)?.level).toBe(10);
    expect(pendingBreakNode(parsed, "white", 5, 0)).toBeNull();
    expect(nextBreakNode(parsed, "orange", 6, 5)?.level).toBe(10);
    expect(nextBreakNode(parsed, "orange", 11, 10)).toBeNull();
  });
});

describe("enhance loop", () => {
  it("decomposes gear into 炼器精粹, spends it with no failures, and raises worn stats", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({
        slug: "1",
        displayName: "凡人",
        majorName: "金丹",
        majorKey: "core",
        sortOrder: 0,
        nextRealmSlug: null,
        baseAttack: 10,
        baseInterval: 1.5,
        gainPerTick: 1,
      });
      await db.insert(contentGlobals).values({
        id: 1,
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        enhance: STARTING_ENHANCE_RULES,
        powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
        combat: { minInterval: 0.5, defenseConstant: 1, recommendedPowerMargin: 1.05, challengeCooldownSeconds: 0, timeLimitSeconds: 20, speedBase: 100 },
      });
      await db.insert(contentItems).values([
        { slug: "sword", displayName: "剑", kind: "equipment", slot: "weapon", quality: "white", attack: 10, defense: 0, hp: 0, speed: 0 },
        { slug: "fodder", displayName: "废剑", kind: "equipment", slot: "weapon", quality: "white", attack: 1, defense: 0, hp: 0, speed: 0 },
        { slug: "glove", displayName: "护手", kind: "equipment", slot: "gloves", quality: "blue", attack: 2, defense: 3, hp: 0, speed: 0 },
        { slug: "refine_essence", displayName: "炼器精粹", kind: "material", quality: "orange", stackable: true },
      ]);
      const now = new Date("2026-10-10T12:00:00.000Z");
      const player = await registerPlayer(db, { username: "smith", password: "correct-horse", now });
      const [sword] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: "sword", isStack: false, quantity: 1, equippedSlot: "weapon", source: "test", acquiredAt: now })
        .returning();
      const spares = await db
        .insert(playerItems)
        .values([1, 2, 3].map(() => ({ playerId: player.playerId, itemSlug: "fodder", isStack: false, quantity: 1, source: "test", acquiredAt: now })))
        .returning();
      const world = await loadCurrentWorld(db);
      if (!world || !sword) {
        throw new Error("准备数据失败");
      }
      const attackBefore = (await readState(db, player.playerId, now)).attack;
      const essence = async () => (await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId))).filter((row) => row.itemSlug === "refine_essence").reduce((sum, row) => sum + row.quantity, 0);
      // 没有炼器精粹：不能强化
      await expect(withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, sword.id, now))).rejects.toMatchObject({ code: "ESSENCE_SHORT", message: expect.stringMatching(/炼器精粹不足/) });
      // 分解 3 件白装 = 3 × 20 精粹（第五批：白 20 / 绿 60 / 蓝 150 / 紫 400 / 橙 1000）
      for (const spare of spares) {
        await withTransaction(db, (tx) => decomposeItem(tx, world, player.playerId, spare.id, now));
      }
      expect(await essence()).toBe(60);
      // 身上的不能分解
      await expect(withTransaction(db, (tx) => decomposeItem(tx, world, player.playerId, sword.id, now))).rejects.toMatchObject({ code: "EQUIPPED_CANNOT_DECOMPOSE", message: expect.stringMatching(/已穿戴.*不能分解/) });
      // 强化一级：花 40 精粹（40 × 1.25^0 × 1），剩 20，攻击 +6%
      const one = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, sword.id, now));
      expect(one.enhanced).toEqual({ itemId: sword.id, fromLevel: 0, toLevel: 1, spentEssence: 40, spentExp: 0, blockedByBreakthrough: null });
      expect(one.state.essence).toEqual({ itemSlug: "refine_essence", count: 20 });
      expect(one.state.attack).toBeCloseTo(attackBefore + 0.6, 5);
      // 20 不够下一级（50）
      await expect(withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, sword.id, now))).rejects.toThrow(/需要 50/);
      // 旧的强化经验：下次结算按 0.7 换成精粹（向上取整），只换一次
      await db.update(playerStates).set({ enhanceExp: 100000 }).where(eq(playerStates.playerId, player.playerId));
      expect((await readState(db, player.playerId, now)).essence?.count).toBe(20 + 70000);
      expect((await readState(db, player.playerId, now)).essence?.count).toBe(20 + 70000);
      const max = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, sword.id, now, { toMax: true }));
      expect(max.enhanced.toLevel).toBe(5);
      expect(max.enhanced.spentEssence).toBe(50 + 63 + 78 + 98);
      await expect(withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, sword.id, now))).rejects.toThrow(/上限/);
      // 分解已强化装备：品质产出 + 等级 × 40 返还；先脱下再分解
      await db.update(playerItems).set({ equippedSlot: null }).where(eq(playerItems.id, sword.id));
      const refunded = await withTransaction(db, (tx) => decomposeItem(tx, world, player.playerId, sword.id, now));
      expect(refunded.gainedEssence).toBe(20 + 5 * 40);
    });
  });
});
