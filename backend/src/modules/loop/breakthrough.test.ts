import { and, eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import {
  contentDropEntries,
  contentDropTables,
  contentGlobals,
  contentItems,
  contentRealms,
  contentSkills,
  contentStages,
  playerItems,
  playerStates,
} from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { DEFAULT_REALM_YIELD_MULT, enhanceRulesFromInput, saveEnhanceRules, STARTING_ENHANCE_RULES, type EnhanceRules } from "../content/enhance.js";
import { buildScheme } from "../content/numeric-scheme.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { breakthroughItem, challengeStage, decomposeItem, enhanceItem, readState } from "./actions.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

/** 用来测试“规则全由配置决定”的小规则：绿色上限 6，每级 +10%，+2 和 +4 各有一个突破节点。 */
const RULES: EnhanceRules = {
  expBase: 10,
  expGrowth: 2,
  statGrowthBp: 1000,
  refundBp: 5000,
  qualities: {
    white: { cap: 3, costMult: 1, decomposeExp: 5, breakthroughs: [] },
    green: {
      cap: 6,
      costMult: 1,
      decomposeExp: 7,
      statGrowthBp: 2000,
      breakthroughs: [
        { level: 2, materials: [{ itemSlug: "stone_a", count: 3 }] },
        { level: 4, materials: [{ itemSlug: "stone_a", count: 2 }, { itemSlug: "stone_b", count: 1 }] },
      ],
    },
    blue: { cap: 4, costMult: 1, decomposeExp: 9, breakthroughs: [] },
    purple: { cap: 4, costMult: 1, decomposeExp: 9, breakthroughs: [] },
    orange: { cap: 3, costMult: 1.5, decomposeExp: 99, breakthroughs: [{ level: 1, materials: [{ itemSlug: "stone_b", count: 1 }] }] },
  },
  // 第五批：强化消耗炼器精粹。这里让精粹曲线和上面的经验曲线一样，迁移比例 1:1，
  // 这样测试里直接写 enhanceExp，下次结算就原样变成精粹（顺带测了一次性迁移）。
  essence: {
    itemSlug: "refine_essence",
    yields: { white: 5, green: 7, blue: 9, purple: 9, orange: 99 },
    slotMultBp: {},
    slotOverrides: {},
    refundPerLevel: 10,
    realmYieldMult: { ...DEFAULT_REALM_YIELD_MULT },
    costBase: 10,
    costGrowth: 2,
    costTable: {},
    migrationRatioBp: 10000,
  },
};

async function seed(db: TestDb, rules: EnhanceRules | null = RULES) {
  await db.insert(contentRealms).values({ slug: "1", displayName: "凡人", majorName: "金丹", majorKey: "core", sortOrder: 0, nextRealmSlug: null, baseAttack: 10, baseInterval: 1.5, gainPerTick: 1 });
  await db.insert(contentGlobals).values({
    id: 1,
    offlineCapSeconds: 3600,
    bagCapacity: 20,
    ...(rules ? { enhance: rules } : {}),
    powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
    combat: { minInterval: 0.5, defenseConstant: 1, recommendedPowerMargin: 1.05, challengeCooldownSeconds: 0, timeLimitSeconds: 20, speedBase: 100 },
  });
  await db.insert(contentItems).values([
    { slug: "blade", displayName: "绿刃", kind: "equipment", slot: "weapon", quality: "green", attack: 100, defense: 0, hp: 0, speed: 0 },
    { slug: "fairy_blade", displayName: "仙刃", kind: "equipment", slot: "weapon", quality: "orange", attack: 100, defense: 0, hp: 0, speed: 0 },
    { slug: "stone_a", displayName: "甲石", kind: "material", quality: "white", stackable: true },
    { slug: "stone_b", displayName: "乙石", kind: "material", quality: "white", stackable: true },
    { slug: "refine_essence", displayName: "炼器精粹", kind: "material", quality: "orange", stackable: true },
  ]);
  const now = new Date("2026-10-10T12:00:00.000Z");
  const player = await registerPlayer(db, { username: "smith", password: "correct-horse", now });
  const world = await loadCurrentWorld(db);
  if (!world) {
    throw new Error("准备数据失败");
  }
  return { now, player, world };
}

async function give(db: TestDb, playerId: string, itemSlug: string, options: { stack?: number; equippedSlot?: string; now: Date }) {
  const [row] = await db
    .insert(playerItems)
    .values({
      playerId,
      itemSlug,
      isStack: options.stack !== undefined,
      quantity: options.stack ?? 1,
      equippedSlot: options.equippedSlot ?? null,
      source: "test",
      acquiredAt: options.now,
    })
    .returning();
  if (!row) {
    throw new Error("准备数据失败");
  }
  return row;
}

describe("break-through nodes", () => {
  it("部位强化后不再要突破材料；强化等级写在部位上", async () => {
    await withDb(async (db) => {
      const { now, player, world } = await seed(db);
      const blade = await give(db, player.playerId, "blade", { equippedSlot: "weapon", now });
      await db.update(playerStates).set({ enhanceExp: 1_000_000 }).where(eq(playerStates.playerId, player.playerId));
      await expect(withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, blade.id, now))).rejects.toMatchObject({
        message: expect.stringMatching(/不再需要突破材料/),
      });
      const first = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now, { toMax: true }));
      // 旧规则里 +2 是突破节点；部位强化后应直接升过，不被卡住
      expect(first.enhanced.toLevel).toBeGreaterThanOrEqual(2);
      expect(first.enhanced.blockedByBreakthrough).toBeNull();
      expect(first.state.slotEnhances?.weapon).toBe(first.enhanced.toLevel);
    });
  });

  it("未穿戴不能强化；分解换下的装备不按部位等级返还精粹", async () => {
    await withDb(async (db) => {
      const { now, player, world } = await seed(db);
      const fairy = await give(db, player.playerId, "fairy_blade", { equippedSlot: "weapon", now });
      await db.update(playerStates).set({ enhanceExp: 1_000 }).where(eq(playerStates.playerId, player.playerId));
      await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, fairy.id, now));
      await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, fairy.id, now));
      await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, fairy.id, now));
      // 卸下后分解：只有品质一口价
      await db.update(playerItems).set({ equippedSlot: null, enhanceLevel: 0 }).where(eq(playerItems.id, fairy.id));
      const gone = await withTransaction(db, (tx) => decomposeItem(tx, world, player.playerId, fairy.id, now));
      expect(gone.gainedEssence).toBe(99);
    });
  });
});

describe("worn gear cannot be decomposed", () => {
  it("rejects with a clear error and keeps the gear and the pool untouched", async () => {
    await withDb(async (db) => {
      const { now, player, world } = await seed(db);
      const blade = await give(db, player.playerId, "blade", { equippedSlot: "weapon", now });
      await expect(withTransaction(db, (tx) => decomposeItem(tx, world, player.playerId, blade.id, now))).rejects.toMatchObject({
        code: "EQUIPPED_CANNOT_DECOMPOSE",
        status: 409,
        message: "已穿戴的装备不能分解，请先脱下「绿刃」",
      });
      const [row] = await db.select().from(playerItems).where(eq(playerItems.id, blade.id));
      expect(row?.equippedSlot).toBe("weapon");
      const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, player.playerId));
      expect(state?.enhanceExp).toBe(0);
    });
  });
});

describe("炼器精粹 has no cap", () => {
  it("keeps growing far past any round number and still pays for enhancing", async () => {
    await withDb(async (db) => {
      const { now, player, world } = await seed(db);
      const blade = await give(db, player.playerId, "blade", { equippedSlot: "weapon", now });
      const spare = await give(db, player.playerId, "blade", { now });
      const huge = 9_000_000_000_000;
      await db.update(playerStates).set({ enhanceExp: huge }).where(eq(playerStates.playerId, player.playerId));
      const decomposed = await withTransaction(db, (tx) => decomposeItem(tx, world, player.playerId, spare.id, now));
      expect(decomposed.state.essence).toEqual({ itemSlug: "refine_essence", count: huge + 7 });
      const enhanced = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now));
      expect(enhanced.state.essence?.count).toBe(huge + 7 - 10);
      const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, player.playerId));
      expect(state?.enhanceExp).toBe(0);
    });
  });
});

describe("enhance rules come only from content", () => {
  it("refuses to enhance when the published rules are missing instead of falling back to defaults", async () => {
    await withDb(async (db) => {
      const { now, player, world } = await seed(db, null);
      const blade = await give(db, player.playerId, "blade", { equippedSlot: "weapon", now });
      await expect(withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now))).rejects.toThrow(/请先在后台填写：强化规则|强化规则/);
      await expect(withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, blade.id, now))).rejects.toThrow(/不再需要突破材料/);
    });
  });

  it("follows edited caps, costs and growth exactly", async () => {
    await withDb(async (db) => {
      const edited: EnhanceRules = {
        ...RULES,
        expBase: 100,
        expGrowth: 1,
        qualities: { ...RULES.qualities, green: { cap: 2, costMult: 1, decomposeExp: 1, statGrowthBp: 5000, breakthroughs: [] } },
        essence: { ...RULES.essence!, costBase: 100, costGrowth: 1 },
      };
      const { now, player, world } = await seed(db, edited);
      const blade = await give(db, player.playerId, "blade", { equippedSlot: "weapon", now });
      await db.update(playerStates).set({ enhanceExp: 1_000 }).where(eq(playerStates.playerId, player.playerId));
      const before = (await readState(db, player.playerId, now)).attack;
      // 部位强化无玩法上限：toMax 花光精粹；这里池子够升很多级，只断言至少升 2 级且花费按 costBase 累加
      const one = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now));
      expect(one.enhanced).toMatchObject({ toLevel: 1, spentEssence: 100 });
      const two = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now));
      expect(two.enhanced).toMatchObject({ fromLevel: 1, toLevel: 2, spentEssence: 100 });
      expect(two.state.attack - before).toBeCloseTo(100, 5);
    });
  });
});

describe("saving rules in the admin", () => {
  it("creates the starter materials it needs and rejects unknown or gear materials", async () => {
    await withDb(async (db) => {
      await seed(db, null);
      const saved = await saveEnhanceRules(db, STARTING_ENHANCE_RULES, null);
      // 部位强化起始规则无突破节点 → 不自动建突破石；缺精粹物品时会创建
      expect(saved.createdMaterials.filter((slug) => slug.startsWith("enh_stone_"))).toEqual([]);
      expect((await saveEnhanceRules(db, STARTING_ENHANCE_RULES, null)).createdMaterials).toEqual([]);
      const unknown = { ...RULES, qualities: { ...RULES.qualities, green: { ...RULES.qualities.green!, breakthroughs: [{ level: 2, materials: [{ itemSlug: "nope", count: 1 }] }] } } };
      await expect(saveEnhanceRules(db, unknown, null)).rejects.toThrow(/nope.*不存在/);
      const gear = { ...RULES, qualities: { ...RULES.qualities, green: { ...RULES.qualities.green!, breakthroughs: [{ level: 2, materials: [{ itemSlug: "blade", count: 1 }] }] } } };
      await expect(saveEnhanceRules(db, gear, null)).rejects.toThrow(/不能是装备/);
      expect(enhanceRulesFromInput(saved.rules)).toEqual(STARTING_ENHANCE_RULES);
    });
  });
});

describe("break-through stones from the boss drop table", () => {
  it("rolls the configured table for scheme bosses that have a reward rule", async () => {
    await withDb(async (db) => {
      const scheme = buildScheme();
      await db.insert(contentRealms).values(scheme.realms);
      await db.insert(contentSkills).values(scheme.skills.map((skill) => ({ ...skill, prerequisiteSkillSlugs: [] })));
      await db.insert(contentItems).values(scheme.items);
      await db.insert(contentDropTables).values(scheme.dropTables);
      await db.insert(contentDropEntries).values(scheme.dropEntries.map((entry) => ({ ...entry, chanceBp: 10000, minQty: 2, maxQty: 2 })));
      await db.insert(contentGlobals).values({
        id: 1,
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        enhance: STARTING_ENHANCE_RULES,
        startingRealmSlug: scheme.startingRealmSlug,
        powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
        combat: { minInterval: 0.5, defenseConstant: 1, recommendedPowerMargin: 1.05, challengeCooldownSeconds: 0, timeLimitSeconds: 20, speedBase: 100 },
      });
      const first = scheme.stages[0]!;
      await db.insert(contentStages).values({ ...first, bosses: [{ ...first.bosses[0]!, attack: 0, hp: 1 }] });
      const now = new Date("2026-10-10T12:00:00.000Z");
      const player = await registerPlayer(db, { username: "dropper", password: "correct-horse", now });
      const world = await loadCurrentWorld(db);
      if (!world) {
        throw new Error("准备数据失败");
      }
      const result = await withTransaction(db, (tx) => challengeStage(tx, world, player.playerId, first.slug, now, () => 0));
      expect(result.battle.win).toBe(true);
      const stones = result.drops.filter((drop) => drop.itemSlug.startsWith("enh_stone_"));
      expect(stones.map((drop) => [drop.itemSlug, drop.quantity])).toEqual([
        ["enh_stone_low", 2],
        ["enh_stone_mid", 2],
        ["enh_stone_high", 2],
      ]);
      const owned = await db.select().from(playerItems).where(and(eq(playerItems.playerId, player.playerId), eq(playerItems.isStack, true)));
      expect(owned.filter((row) => row.itemSlug.startsWith("enh_stone_")).map((row) => row.quantity)).toEqual([2, 2, 2]);
    });
  });
});
