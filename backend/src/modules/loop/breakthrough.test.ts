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
import { enhanceRulesFromInput, saveEnhanceRules, STARTING_ENHANCE_RULES, type EnhanceRules } from "../content/enhance.js";
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
    realmYieldMult: { qi: 0.25, foundation: 0.45, core: 1 },
    costBase: 10,
    costGrowth: 2,
    costTable: {},
    migrationRatioBp: 10000,
  },
};

async function seed(db: TestDb, rules: EnhanceRules | null = RULES) {
  await db.insert(contentRealms).values({ slug: "1", displayName: "凡人", sortOrder: 1, nextRealmSlug: null, baseAttack: 10, baseInterval: 1.5, gainPerTick: 1 });
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
  it("stops enhancing on a node, takes the configured materials from the bag, then lets the gear continue", async () => {
    await withDb(async (db) => {
      const { now, player, world } = await seed(db);
      const blade = await give(db, player.playerId, "blade", { equippedSlot: "weapon", now });
      await db.update(playerStates).set({ enhanceExp: 1_000_000 }).where(eq(playerStates.playerId, player.playerId));

      // 一键强化遇到 +2 节点就停下，并告诉界面是哪个节点
      const first = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now, { toMax: true }));
      expect(first.enhanced).toMatchObject({ fromLevel: 0, toLevel: 2, spentEssence: 10 + 20, blockedByBreakthrough: 2 });
      // 再强化被拒绝，错误里写明要什么
      await expect(withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now))).rejects.toMatchObject({
        code: "BREAKTHROUGH_REQUIRED",
        message: expect.stringContaining("甲石×3"),
      });
      // 没有材料：拒绝，什么也不扣
      await expect(withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, blade.id, now))).rejects.toMatchObject({
        code: "BREAKTHROUGH_MATERIAL_SHORT",
        message: expect.stringContaining("甲石 还差 3"),
      });
      const [unchanged] = await db.select().from(playerItems).where(eq(playerItems.id, blade.id));
      expect(unchanged?.breakLevel).toBe(0);
      // 材料不够（只有 2 个）：同样拒绝，不扣
      const stack = await give(db, player.playerId, "stone_a", { stack: 2, now });
      await expect(withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, blade.id, now))).rejects.toMatchObject({ code: "BREAKTHROUGH_MATERIAL_SHORT" });
      const [still] = await db.select().from(playerItems).where(eq(playerItems.id, stack.id));
      expect(still?.quantity).toBe(2);
      // 材料够了（5 个）：扣 3 个，剩 2 个，节点记为已突破；不会失败
      await db.update(playerItems).set({ quantity: 5 }).where(eq(playerItems.id, stack.id));
      const broken = await withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, blade.id, now));
      expect(broken.broken).toEqual({ itemId: blade.id, level: 2, materials: [{ itemSlug: "stone_a", count: 3 }] });
      const [left] = await db.select().from(playerItems).where(eq(playerItems.id, stack.id));
      expect(left?.quantity).toBe(2);
      expect(broken.state.items.find((row) => row.id === blade.id)?.breakLevel).toBe(2);
      // 同一个节点不能重复突破
      await expect(withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, blade.id, now))).rejects.toThrow(/不在突破节点/);
      // 继续强化到下一个节点 +4
      const second = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now, { toMax: true }));
      expect(second.enhanced).toMatchObject({ fromLevel: 2, toLevel: 4, blockedByBreakthrough: 4 });
      // +4 节点要两种材料；甲石刚好 2 个（用光后行被删除），乙石没有 → 缺乙石
      await expect(withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, blade.id, now))).rejects.toMatchObject({
        message: expect.stringContaining("乙石 还差 1"),
      });
      const stoneB = await give(db, player.playerId, "stone_b", { stack: 1, now });
      await withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, blade.id, now));
      // 突破石用光（行被删除）；剩下的堆叠只有炼器精粹
      const rows = await db.select().from(playerItems).where(and(eq(playerItems.playerId, player.playerId), eq(playerItems.isStack, true)));
      expect(rows.map((row) => row.itemSlug)).toEqual(["refine_essence"]);
      expect(stoneB.id).toBeTruthy();
      // 突破后一路升到上限 +6，没有失败、没有掉级
      const last = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now, { toMax: true }));
      expect(last.enhanced).toMatchObject({ fromLevel: 4, toLevel: 6, blockedByBreakthrough: null });
      // 这个品质每级 +20%（品质自己的 statGrowthBp 覆盖了通用的 10%）
      const attackAfter = (await readState(db, player.playerId, now)).attack;
      const base = (await readState(db, player.playerId, now)).attack - 100 * (1 + (6 * 2000) / 10000);
      expect(attackAfter - base).toBeCloseTo(220, 5);
    });
  });

  it("only blocks at the exact node level, so gear above a newly added node is not forced back", async () => {
    await withDb(async (db) => {
      const { now, player, world } = await seed(db);
      const blade = await give(db, player.playerId, "blade", { now });
      await db.update(playerItems).set({ enhanceLevel: 3 }).where(eq(playerItems.id, blade.id));
      await db.update(playerStates).set({ enhanceExp: 1_000_000 }).where(eq(playerStates.playerId, player.playerId));
      // 等级 3 已经超过 +2 节点：不受影响，可以升到 +4 再被 +4 节点拦住
      const result = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now, { toMax: true }));
      expect(result.enhanced).toMatchObject({ fromLevel: 3, toLevel: 4, blockedByBreakthrough: 4 });
    });
  });

  it("uses the orange rules for orange gear and its own node", async () => {
    await withDb(async (db) => {
      const { now, player, world } = await seed(db);
      const fairy = await give(db, player.playerId, "fairy_blade", { now });
      await db.update(playerStates).set({ enhanceExp: 1_000 }).where(eq(playerStates.playerId, player.playerId));
      const one = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, fairy.id, now));
      expect(one.enhanced).toMatchObject({ toLevel: 1, spentEssence: 15, blockedByBreakthrough: 1 });
      await expect(withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, fairy.id, now))).rejects.toMatchObject({ code: "BREAKTHROUGH_REQUIRED" });
      await give(db, player.playerId, "stone_b", { stack: 1, now });
      await withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, fairy.id, now));
      const max = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, fairy.id, now, { toMax: true }));
      expect(max.enhanced.toLevel).toBe(3);
      const gone = await withTransaction(db, (tx) => decomposeItem(tx, world, player.playerId, fairy.id, now));
      // 精粹：品质产出 + 强化等级 × 每级返还（+3 × 10）
      expect(gone.gainedEssence).toBe(99 + 3 * 10);
    });
  });

  it("refuses to break through gear that is not on a node, and non-gear", async () => {
    await withDb(async (db) => {
      const { now, player, world } = await seed(db);
      const blade = await give(db, player.playerId, "blade", { now });
      const stack = await give(db, player.playerId, "stone_a", { stack: 9, now });
      await expect(withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, blade.id, now))).rejects.toThrow(/不在突破节点/);
      await expect(withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, stack.id, now))).rejects.toMatchObject({ code: "NOT_EQUIPMENT" });
      await expect(withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, "00000000-0000-0000-0000-000000000000", now))).rejects.toMatchObject({ code: "NOT_FOUND" });
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
      const blade = await give(db, player.playerId, "blade", { now });
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
      const blade = await give(db, player.playerId, "blade", { now });
      await expect(withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now))).rejects.toThrow(/请先在后台填写：强化规则/);
      await expect(withTransaction(db, (tx) => breakthroughItem(tx, world, player.playerId, blade.id, now))).rejects.toThrow(/请先在后台填写：强化规则/);
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
      const result = await withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now, { toMax: true }));
      expect(result.enhanced).toMatchObject({ toLevel: 2, spentEssence: 200 });
      expect(result.state.attack - before).toBeCloseTo(100, 5);
      await expect(withTransaction(db, (tx) => enhanceItem(tx, world, player.playerId, blade.id, now))).rejects.toThrow(/上限 \+2/);
    });
  });
});

describe("saving rules in the admin", () => {
  it("creates the starter materials it needs and rejects unknown or gear materials", async () => {
    await withDb(async (db) => {
      await seed(db, null);
      const saved = await saveEnhanceRules(db, STARTING_ENHANCE_RULES, null);
      expect(saved.createdMaterials.sort()).toEqual(["enh_stone_low", "enh_stone_mid"]);
      const [stone] = await db.select().from(contentItems).where(eq(contentItems.slug, "enh_stone_low"));
      expect(stone).toMatchObject({ kind: "material", stackable: true });
      // 再保存一次不会重复创建
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
