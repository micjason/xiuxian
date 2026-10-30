/**
 * 离线挂机掉装：等效击杀 = countedSeconds / waveCycle（余数携带）；掷 idleDropTableSlug；
 * 尊重 offlineCapSeconds；满包装备跳过；无 ×0.5。
 */
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import {
  contentDropEntries,
  contentDropTables,
  contentGlobals,
  contentItems,
  contentStages,
  playerItems,
  playerStates,
  players,
} from "../../db/schema.js";
import { applyPrototypeV12 } from "../content/prototype-v12.js";
import { loadDraftSnapshot } from "../content/snapshot.js";
import { readGameRules } from "../content/rules.js";
import { withDb } from "../../test/db.js";
import { idleEquivalentKills, settleOfflineIdleDrops, setWaveRandom } from "./waves.js";

const start = new Date("2026-10-30T04:00:00.000Z");

describe("idleEquivalentKills", () => {
  it("floors countedSeconds / waveCycle and carries the remainder", () => {
    expect(idleEquivalentKills(25, 10, 0)).toEqual({ kills: 2, remainderSeconds: 5 });
    expect(idleEquivalentKills(5, 10, 5)).toEqual({ kills: 1, remainderSeconds: 0 });
    expect(idleEquivalentKills(0, 10, 7)).toEqual({ kills: 0, remainderSeconds: 7 });
    expect(idleEquivalentKills(9, 10, 0)).toEqual({ kills: 0, remainderSeconds: 9 });
  });

  it("does not apply an extra ×0.5 offline multiplier", () => {
    // 60s / 10s = 6 kills，不是 3
    expect(idleEquivalentKills(60, 10, 0).kills).toBe(6);
  });

  it("returns zero kills when cycle is invalid", () => {
    expect(idleEquivalentKills(100, 0, 3)).toEqual({ kills: 0, remainderSeconds: 3 });
    expect(idleEquivalentKills(100, -1, 2)).toEqual({ kills: 0, remainderSeconds: 2 });
  });
});

describe("settleOfflineIdleDrops", () => {
  it("rolls idleDropTableSlug once per equivalent kill and grants gear + materials", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      await db.insert(contentItems).values({
        slug: "mat_idle_stone",
        displayName: "挂机石",
        kind: "material",
        quality: "green",
        stackable: true,
      }).onConflictDoNothing();
      await db.insert(contentDropTables).values({ slug: "test_idle", displayName: "测挂机" }).onConflictDoNothing();
      await db.delete(contentDropEntries).where(eq(contentDropEntries.dropTableSlug, "test_idle"));
      await db.insert(contentDropEntries).values([
        { dropTableSlug: "test_idle", itemSlug: "gear_major1_weapon_white", chanceBp: 10000, minQty: 1, maxQty: 1 },
        { dropTableSlug: "test_idle", itemSlug: "mat_idle_stone", chanceBp: 10000, minQty: 2, maxQty: 2 },
      ]);
      await db.update(contentStages).set({ idleDropTableSlug: "test_idle" }).where(eq(contentStages.slug, "lianqi_1"));
      // 让波次周期稳定：强玩家秒杀，cycleSeconds 仍 > 0
      const world = await loadDraftSnapshot(db);
      const stage = world.stages.find((row) => row.slug === "lianqi_1")!;
      const [player] = await db.insert(players).values({ username: "idle1", usernameLower: "idle1", passwordHash: "x" }).returning();
      await db.insert(playerStates).values({ playerId: player!.id, cultivation: 0, spiritStones: 0, realmSlug: "lianqi_1", lastSettledAt: start });

      setWaveRandom(() => 0);
      const rules = readGameRules(world);
      const stats = { attack: 10_000, defense: 10_000, hp: 50_000, interval: 1 };
      // 先量一波周期，再塞刚好 2 个周期的秒数
      const { cycleFor } = await import("./waves.js");
      const cycle = cycleFor(rules, stats, stage.monsters![0]!);
      expect(cycle.cycleSeconds).toBeGreaterThan(0);

      const result = await settleOfflineIdleDrops(db as never, world as never, player!.id, {
        rules,
        stage: stage as never,
        stats,
        countedSeconds: cycle.cycleSeconds * 2,
        remainderSeconds: 0,
        capacity: 50,
        now: start,
      });
      expect(result.kills).toBe(2);
      expect(result.progress).toBeCloseTo(0, 5);
      expect(result.drops.filter((row) => row.idle && row.itemSlug === "gear_major1_weapon_white")).toHaveLength(2);
      expect(result.drops.filter((row) => row.idle && row.itemSlug === "mat_idle_stone")).toHaveLength(2);
      const bag = await db.select().from(playerItems).where(eq(playerItems.playerId, player!.id));
      expect(bag.filter((row) => row.itemSlug === "gear_major1_weapon_white")).toHaveLength(2);
      expect(bag.find((row) => row.itemSlug === "mat_idle_stone")?.quantity).toBe(4);
    });
  });

  it("carries remainder across calls", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      await db.insert(contentDropTables).values({ slug: "test_idle2", displayName: "测" }).onConflictDoNothing();
      await db.delete(contentDropEntries).where(eq(contentDropEntries.dropTableSlug, "test_idle2"));
      await db.insert(contentDropEntries).values({
        dropTableSlug: "test_idle2",
        itemSlug: "enh_stone_low",
        chanceBp: 10000,
        minQty: 1,
        maxQty: 1,
      });
      await db.update(contentStages).set({ idleDropTableSlug: "test_idle2" }).where(eq(contentStages.slug, "lianqi_1"));
      const world = await loadDraftSnapshot(db);
      const stage = world.stages.find((row) => row.slug === "lianqi_1")!;
      const [player] = await db.insert(players).values({ username: "idle2", usernameLower: "idle2", passwordHash: "x" }).returning();
      await db.insert(playerStates).values({ playerId: player!.id, cultivation: 0, spiritStones: 0, realmSlug: "lianqi_1", lastSettledAt: start });
      setWaveRandom(() => 0);
      const rules = readGameRules(world);
      const stats = { attack: 10_000, defense: 10_000, hp: 50_000, interval: 1 };
      const { cycleFor } = await import("./waves.js");
      const cycle = cycleFor(rules, stats, stage.monsters![0]!);
      const half = cycle.cycleSeconds / 2;
      const first = await settleOfflineIdleDrops(db as never, world as never, player!.id, {
        rules,
        stage: stage as never,
        stats,
        countedSeconds: half,
        remainderSeconds: 0,
        capacity: 50,
        now: start,
      });
      expect(first.kills).toBe(0);
      expect(first.progress).toBeCloseTo(half, 5);
      const second = await settleOfflineIdleDrops(db as never, world as never, player!.id, {
        rules,
        stage: stage as never,
        stats,
        countedSeconds: half + 0.001,
        remainderSeconds: first.progress,
        capacity: 50,
        now: start,
      });
      expect(second.kills).toBe(1);
    });
  });

  it("skips equipment when bag is full and sets bagFull; materials still grant", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const [globals] = await db.select().from(contentGlobals);
      await db.update(contentGlobals).set({
        bagCapacity: 1,
        tuning: { ...(globals!.tuning as object), bagFullSkipSources: ["stage_drop", "boss_first", "boss_repeat"] } as never,
      });
      await db.insert(contentItems).values({
        slug: "mat_idle_herb",
        displayName: "挂机草",
        kind: "material",
        quality: "green",
        stackable: true,
      }).onConflictDoNothing();
      await db.insert(contentDropTables).values({ slug: "test_idle3", displayName: "测" }).onConflictDoNothing();
      await db.delete(contentDropEntries).where(eq(contentDropEntries.dropTableSlug, "test_idle3"));
      await db.insert(contentDropEntries).values([
        { dropTableSlug: "test_idle3", itemSlug: "gear_major1_weapon_white", chanceBp: 10000, minQty: 1, maxQty: 1 },
        { dropTableSlug: "test_idle3", itemSlug: "mat_idle_herb", chanceBp: 10000, minQty: 1, maxQty: 1 },
      ]);
      await db.update(contentStages).set({ idleDropTableSlug: "test_idle3" }).where(eq(contentStages.slug, "lianqi_1"));
      const world = await loadDraftSnapshot(db);
      const stage = world.stages.find((row) => row.slug === "lianqi_1")!;
      const [player] = await db.insert(players).values({ username: "idle3", usernameLower: "idle3", passwordHash: "x" }).returning();
      await db.insert(playerStates).values({
        playerId: player!.id,
        cultivation: 0,
        spiritStones: 0,
        realmSlug: "lianqi_1",
        lastSettledAt: start,
        bagBonus: 0,
      });
      // 占满唯一格子
      await db.insert(playerItems).values({
        playerId: player!.id,
        itemSlug: "gear_major1_helmet_white",
        isStack: false,
        quantity: 1,
        source: "test",
        acquiredAt: start,
      });
      setWaveRandom(() => 0);
      const rules = readGameRules(world);
      expect(rules.bagCapacity).toBe(1);
      const stats = { attack: 10_000, defense: 10_000, hp: 50_000, interval: 1 };
      const { cycleFor } = await import("./waves.js");
      const cycle = cycleFor(rules, stats, stage.monsters![0]!);
      const result = await settleOfflineIdleDrops(db as never, world as never, player!.id, {
        rules,
        stage: stage as never,
        stats,
        countedSeconds: cycle.cycleSeconds,
        remainderSeconds: 0,
        capacity: 1,
        now: start,
      });
      expect(result.kills).toBe(1);
      expect(result.bagFull).toBe(true);
      expect(result.drops.some((row) => row.itemSlug === "gear_major1_weapon_white" && row.dropped)).toBe(true);
      expect(result.drops.some((row) => row.itemSlug === "mat_idle_herb" && !row.dropped)).toBe(true);
      const bag = await db.select().from(playerItems).where(eq(playerItems.playerId, player!.id));
      expect(bag.some((row) => row.itemSlug === "gear_major1_weapon_white")).toBe(false);
      expect(bag.find((row) => row.itemSlug === "mat_idle_herb")?.quantity).toBe(1);
    });
  });
});
