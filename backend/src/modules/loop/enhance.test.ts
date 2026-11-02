import { and, eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentRealms, playerItems, playerSlotEnhances } from "../../db/schema.js";
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
  essenceCost,
  STARTING_ENHANCE_RULES,
} from "../content/enhance.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { decomposeItem, enhanceItem, equipItem, readState, unequipItem } from "./actions.js";

describe("enhance rules (pure)", () => {
  const rules = STARTING_ENHANCE_RULES;
  it("grows the cost every level; slotBound starting caps are soft (200)", () => {
    expect(enhanceCost(rules, "white", 0)).toBe(60);
    expect(enhanceCost(rules, "white", 1)).toBe(75);
    expect(enhanceCap(rules, "white")).toBe(5);
    expect(enhanceCap(rules, "orange")).toBe(15);
    expect(rules.slotBound).toBe(true);
    expect(essenceCost(rules, "white", 0)).toBe(40);
    expect(essenceCost(rules, "white", 1)).toBe(Math.round(40 * 1.4));
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
    expect(() => enhanceRulesFromInput({ ...rules, qualities: { ...rules.qualities, blue: { cap: 0, costMult: 1, decomposeExp: 1, breakthroughs: [] } } })).toThrow();
    expect(() => enhanceRulesFromInput({ ...rules, expGrowth: 0.5 })).toThrow();
    expect(() => enhanceRulesFromInput({ ...rules, refundBp: 20000 })).toThrow();
  });
});

describe("enhance rules: configurable, red quality, break-through nodes", () => {
  const rules = STARTING_ENHANCE_RULES;
  it("ships five qualities; starting slotBound has empty breakthroughs", () => {
    const parsed = enhanceRulesFromInput(rules);
    expect(Object.keys(parsed.qualities)).toEqual(["white", "green", "blue", "purple", "orange"]);
    expect(enhanceCap(parsed, "orange")).toBe(15);
    expect(parsed.qualities.orange?.breakthroughs).toEqual([]);
    expect(breakMaterialProblems(parsed, STARTING_BREAK_MATERIALS.map((row) => ({ slug: row.slug, kind: "material", enabled: true }))).length).toBe(0);
    const legacy = enhanceRulesFromInput({ ...rules, qualities: { ...rules.qualities, red: { cap: 18, costMult: 2, decomposeExp: 960, breakthroughs: [] } } } as never);
    expect(Object.keys(legacy.qualities)).not.toContain("red");
  });
  it("lets every quality override the exp growth and the per-level stat growth", () => {
    const custom = enhanceRulesFromInput({
      ...rules,
      qualities: { ...rules.qualities, orange: { ...rules.qualities.orange!, expGrowth: 2, statGrowthBp: 1000, cap: 4, breakthroughs: [] } },
    });
    expect(enhanceCost(custom, "orange", 3)).toBe(Math.round(60 * 2 ** 3 * 1.6));
    expect(enhancedStat(100, 4, custom, "orange")).toBe(140);
    expect(enhanceCost(custom, "white", 3)).toBe(Math.round(60 * 1.25 ** 3));
    expect(enhancedStat(100, 4, custom, "white")).toBe(124);
    expect(() => enhanceRulesFromInput({ ...rules, qualities: { ...rules.qualities, purple: { ...rules.qualities.purple!, expGrowth: 0.9 } } })).toThrow(/不能小于 1/);
  });
  it("requires all five qualities when saving but tolerates an old snapshot missing one at runtime", () => {
    const { orange: _orange, ...withoutOrange } = rules.qualities;
    expect(() => enhanceRulesFromInput({ ...rules, qualities: withoutOrange })).toThrow(/橙品质强化上限/);
    const lenient = enhanceRulesFromInput({ ...rules, qualities: withoutOrange }, { requireAll: false });
    expect(enhanceCap(lenient, "purple")).toBe(12);
    expect(() => enhanceCap(lenient, "orange")).toThrow(/还没有橙品质的强化规则/);
  });
  it("validates break-through nodes when provided", () => {
    const withNodes = (breakthroughs: unknown) => ({ ...rules, qualities: { ...rules.qualities, orange: { ...rules.qualities.orange!, breakthroughs } } });
    const stone = [{ itemSlug: "enh_stone_low", count: 1 }];
    expect(() => enhanceRulesFromInput(withNodes([{ level: 200, materials: stone }]))).toThrow(/必须小于等级上限/);
    expect(() => enhanceRulesFromInput(withNodes([{ level: 5, materials: stone }, { level: 5, materials: stone }]))).toThrow(/重复/);
    expect(() => enhanceRulesFromInput(withNodes([{ level: 5, materials: [] }]))).toThrow(/至少要有一种材料/);
    const sorted = enhanceRulesFromInput(withNodes([{ level: 7, materials: stone }, { level: 3, materials: stone }]));
    expect(sorted.qualities.orange?.breakthroughs.map((node) => node.level)).toEqual([3, 7]);
  });
  it("blocks only while the gear sits exactly on an unbroken node (legacy rules)", () => {
    const parsed = enhanceRulesFromInput({
      ...rules,
      qualities: {
        ...rules.qualities,
        orange: {
          ...rules.qualities.orange!,
          cap: 15,
          breakthroughs: [
            { level: 5, materials: [{ itemSlug: "enh_stone_low", count: 1 }] },
            { level: 10, materials: [{ itemSlug: "enh_stone_mid", count: 1 }] },
          ],
        },
        white: { ...rules.qualities.white!, cap: 5, breakthroughs: [] },
      },
    });
    expect(pendingBreakNode(parsed, "orange", 5, 0)?.level).toBe(5);
    expect(pendingBreakNode(parsed, "orange", 5, 5)).toBeNull();
    expect(nextBreakNode(parsed, "orange", 6, 5)?.level).toBe(10);
    expect(pendingBreakNode(parsed, "white", 5, 0)).toBeNull();
  });
});

async function seedEnhanceWorld(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
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
    { slug: "better_sword", displayName: "好剑", kind: "equipment", slot: "weapon", quality: "white", attack: 20, defense: 0, hp: 0, speed: 0 },
    { slug: "fodder", displayName: "废剑", kind: "equipment", slot: "weapon", quality: "white", attack: 1, defense: 0, hp: 0, speed: 0 },
    { slug: "glove", displayName: "护手", kind: "equipment", slot: "gloves", quality: "blue", attack: 2, defense: 3, hp: 0, speed: 0 },
    { slug: "refine_essence", displayName: "炼器精粹", kind: "material", quality: "orange", stackable: true },
  ]);
}

describe("slot-bound enhance (六条定稿)", () => {
  it("1–3: 等级绑部位、换下归0、只吃精粹必成功无突破", async () => {
    await withDb(async (db) => {
      await seedEnhanceWorld(db);
      const now = new Date("2026-10-10T12:00:00.000Z");
      const player = await registerPlayer(db, { username: "slotsmith", password: "correct-horse", now });
      const [sword] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: "sword", isStack: false, quantity: 1, equippedSlot: "weapon", source: "test", acquiredAt: now })
        .returning();
      const [spare] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: "better_sword", isStack: false, quantity: 1, source: "test", acquiredAt: now })
        .returning();
      await db.insert(playerItems).values({ playerId: player.playerId, itemSlug: "refine_essence", isStack: true, quantity: 500, source: "test", acquiredAt: now });
      const world = await loadCurrentWorld(db);
      if (!world || !sword || !spare) throw new Error("准备失败");

      const one = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, sword.id, now));
      expect(one.enhanced).toMatchObject({ itemId: sword.id, slot: "weapon", fromLevel: 0, toLevel: 1, spentEssence: 40, blockedByBreakthrough: null });
      const slotRow = await db.select().from(playerSlotEnhances).where(and(eq(playerSlotEnhances.playerId, player.playerId), eq(playerSlotEnhances.slot, "weapon")));
      expect(slotRow[0]?.enhanceLevel).toBe(1);
      expect((await db.select().from(playerItems).where(eq(playerItems.id, sword.id)))[0]?.enhanceLevel).toBe(0);

      // 换装：新装备吃该格强化；被换下归 0
      const swapped = await withTransaction(db, (tx) => equipItem(tx, world, player.playerId, spare.id, now));
      const worn = swapped.state.items.find((row) => row.id === spare.id);
      const bagged = swapped.state.items.find((row) => row.id === sword.id);
      expect(worn?.equippedSlot).toBe("weapon");
      expect(worn?.enhanceLevel).toBe(1);
      expect(bagged?.equippedSlot).toBeNull();
      expect(bagged?.enhanceLevel).toBe(0);
      expect(swapped.state.slotEnhances?.weapon).toBe(1);

      // 卸下：部位等级仍在
      await withTransaction(db, (tx) => unequipItem(tx, world, player.playerId, spare.id, now));
      const afterUnequip = await readState(db, player.playerId, now);
      expect(afterUnequip.slotEnhances?.weapon).toBe(1);
      expect(afterUnequip.items.find((row) => row.id === spare.id)?.enhanceLevel).toBe(0);

      // 未穿戴不能强化
      await expect(withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, spare.id, now))).rejects.toMatchObject({
        message: expect.stringMatching(/先穿上/),
      });
    });
  });

  it("5+防刷: 消耗随等级拉陡；换下分解不返还强化精粹", async () => {
    await withDb(async (db) => {
      await seedEnhanceWorld(db);
      const now = new Date("2026-10-10T12:00:00.000Z");
      const player = await registerPlayer(db, { username: "steep", password: "correct-horse", now });
      const [sword] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: "sword", isStack: false, quantity: 1, equippedSlot: "weapon", source: "test", acquiredAt: now })
        .returning();
      await db.insert(playerItems).values({ playerId: player.playerId, itemSlug: "refine_essence", isStack: true, quantity: 1000, source: "test", acquiredAt: now });
      const world = await loadCurrentWorld(db);
      if (!world || !sword) throw new Error("准备失败");

      const first = essenceCost(STARTING_ENHANCE_RULES, "white", 0);
      const second = essenceCost(STARTING_ENHANCE_RULES, "white", 1);
      expect(second).toBeGreaterThan(first);
      expect(second / first).toBeCloseTo(1.4, 5);

      await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, sword.id, now));
      await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, sword.id, now));
      // 换下后分解：只有品质一口价，没有强化等级返还
      await withTransaction(db, (tx) => unequipItem(tx, world, player.playerId, sword.id, now));
      const before = (await readState(db, player.playerId, now)).essence?.count ?? 0;
      const refunded = await withTransaction(db, (tx) => decomposeItem(tx, world, player.playerId, sword.id, now));
      expect(refunded.gainedEssence).toBe(20);
      expect(((await readState(db, player.playerId, now)).essence?.count ?? 0) - before).toBe(20);
      // 部位等级仍在，再穿别的还能吃到
      expect((await readState(db, player.playerId, now)).slotEnhances?.weapon).toBe(2);
    });
  });

  it("无上限：精粹够就能一直升，不被旧 cap/突破卡住", async () => {
    await withDb(async (db) => {
      await seedEnhanceWorld(db);
      const now = new Date("2026-10-10T12:00:00.000Z");
      const player = await registerPlayer(db, { username: "nocap", password: "correct-horse", now });
      const [sword] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: "sword", isStack: false, quantity: 1, equippedSlot: "weapon", source: "test", acquiredAt: now })
        .returning();
      await db.insert(playerItems).values({ playerId: player.playerId, itemSlug: "refine_essence", isStack: true, quantity: 50_000, source: "test", acquiredAt: now });
      const world = await loadCurrentWorld(db);
      if (!world || !sword) throw new Error("准备失败");
      const many = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, sword.id, now, { toMax: true }));
      expect(many.enhanced.toLevel).toBeGreaterThan(15);
      expect(many.enhanced.blockedByBreakthrough).toBeNull();
      expect(many.state.slotEnhances?.weapon).toBe(many.enhanced.toLevel);
    });
  });
});
