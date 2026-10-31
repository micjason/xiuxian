/**
 * 洞府 v1：药园种植/领取、炼丹开始/领取、settle、BAG_FULL、QUEUE_FULL、修为丹。
 */
import { and, eq, isNull } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import {
  contentGlobals,
  contentItems,
  contentRealms,
  playerActiveBuffs,
  playerDongfuAlchemy,
  playerDongfuPlots,
  playerItems,
  playerStates,
} from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { AppError } from "../../shared/errors.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { useItem } from "../loop/actions.js";
import { DEFAULT_DONGFU } from "./config.js";
import { allocateServants, buySeed, claimAlchemy, claimGarden, plantSeed, readDongfuState, startAlchemy, upgradeFacility } from "./actions.js";

const DONGFU_ITEMS = [
  { slug: "seed_lingcao", displayName: "灵草种子", kind: "material", quality: "green", stackable: true },
  { slug: "seed_qingxin", displayName: "清心草种子", kind: "material", quality: "blue", stackable: true },
  { slug: "herb_lingcao", displayName: "灵草", kind: "material", quality: "green", stackable: true },
  { slug: "herb_qingxin", displayName: "清心草", kind: "material", quality: "blue", stackable: true },
  {
    slug: "pill_cultivate",
    displayName: "修为丹",
    kind: "pill",
    quality: "green",
    stackable: true,
    effect: { cultivationGain: 100 },
  },
  {
    slug: "pill_atk_temp",
    displayName: "攻击临时丹",
    kind: "pill",
    quality: "blue",
    stackable: true,
    effect: { buffStat: "attack", buffBp: 1000, durationSeconds: 300 },
  },
  {
    slug: "pill_def_temp",
    displayName: "防御临时丹",
    kind: "pill",
    quality: "blue",
    stackable: true,
    effect: { buffStat: "defense", buffBp: 1000, durationSeconds: 300 },
  },
  // 占满行囊用的不可堆叠装备
  ...Array.from({ length: 20 }, (_, i) => ({
    slug: `filler_${i}`,
    displayName: `占位${i}`,
    kind: "equipment",
    quality: "white",
    slot: "weapon",
    attack: 1,
    stackable: false,
  })),
] as const;

async function seedWorld(db: Parameters<Parameters<typeof withDb>[0]>[0], dongfu = DEFAULT_DONGFU) {
  await db.insert(contentRealms).values({
    slug: "1",
    displayName: "凡人",
    majorName: "炼气",
    majorKey: "qi",
    sortOrder: 0,
    nextRealmSlug: null,
    baseAttack: 10,
    baseInterval: 1.5,
    gainPerTick: 1,
  });
  await db.insert(contentGlobals).values({
    id: 1,
    startingRealmSlug: "1",
    offlineCapSeconds: 3600,
    bagCapacity: 20,
    dongfu,
    powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
    combat: {
      minInterval: 0.5,
      defenseConstant: 1,
      recommendedPowerMargin: 1.05,
      challengeCooldownSeconds: 0,
      timeLimitSeconds: 20,
      speedBase: 100,
    },
  });
  await db.insert(contentItems).values([...DONGFU_ITEMS] as never);
}

async function giveStack(
  db: Parameters<Parameters<typeof withDb>[0]>[0],
  playerId: string,
  itemSlug: string,
  quantity: number,
  now: Date,
) {
  await db.insert(playerItems).values({
    playerId,
    itemSlug,
    isStack: true,
    quantity,
    source: "test",
    acquiredAt: now,
  });
}

describe("dongfu v1 garden + alchemy", () => {

  it("grants startingSeeds on first dongfu read; buySeed spends spirit stones", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-10-31T04:00:00.000Z");
      const player = await registerPlayer(db, { username: "seedling", password: "correct-horse", now });
      await db.update(playerStates).set({ spiritStones: 50 }).where(eq(playerStates.playerId, player.playerId));
      const world = await loadCurrentWorld(db);
      const first = await withTransaction(db, (tx) => readDongfuState(tx, world, player.playerId, now));
      expect(first.seedOffers).toHaveLength(2);
      const seeds = await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId));
      const bySlug = Object.fromEntries(seeds.filter((r) => r.isStack).map((r) => [r.itemSlug, r.quantity]));
      expect(bySlug.seed_lingcao).toBe(8);
      expect(bySlug.seed_qingxin).toBe(4);
      // 第二次读不再重复发
      await withTransaction(db, (tx) => readDongfuState(tx, world, player.playerId, now));
      const again = await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId));
      const bySlug2 = Object.fromEntries(again.filter((r) => r.isStack).map((r) => [r.itemSlug, r.quantity]));
      expect(bySlug2.seed_lingcao).toBe(8);
      const bought = await withTransaction(db, (tx) => buySeed(tx, world, player.playerId, { seedSlug: "seed_lingcao" }, now));
      expect(bought.dongfu.seedOffers[0]?.seedSlug).toBe("seed_lingcao");
      const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, player.playerId));
      expect(state?.spiritStones).toBe(40);
      const after = await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId));
      const bySlug3 = Object.fromEntries(after.filter((r) => r.isStack).map((r) => [r.itemSlug, r.quantity]));
      expect(bySlug3.seed_lingcao).toBe(9);
    });
  });
  it("plants a seed, matures offline, and claims herb into bag", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const plantedAt = new Date("2026-10-29T04:00:00.000Z");
      const player = await registerPlayer(db, { username: "gardener", password: "correct-horse", now: plantedAt });
      await giveStack(db, player.playerId, "seed_lingcao", 2, plantedAt);
      const world = await loadCurrentWorld(db);
      if (!world) throw new Error("no world");

      const planted = await withTransaction(db, (tx) =>
        plantSeed(tx, world, player.playerId, { slot: 0, seedSlug: "seed_lingcao" }, plantedAt),
      );
      expect(planted.dongfu.plots[0]).toMatchObject({
        slot: 0,
        seedSlug: "seed_lingcao",
        herbSlug: "herb_lingcao",
        status: "growing",
      });
      expect(planted.dongfu.plotCount).toBe(4);
      expect(planted.dongfu.plots).toHaveLength(4);

      const seedsLeft = await db
        .select()
        .from(playerItems)
        .where(and(eq(playerItems.playerId, player.playerId), eq(playerItems.itemSlug, "seed_lingcao")));
      // giveStack(2) + ensureProgress startingSeeds(8) - plant(1) = 9
      expect(seedsLeft[0]?.quantity).toBe(9);

      const readyAt = new Date(plantedAt.getTime() + 60_000);
      const beforeClaim = await withTransaction(db, (tx) => readDongfuState(tx, world, player.playerId, readyAt));
      expect(beforeClaim.plots[0]?.status).toBe("ready");
      expect(beforeClaim.claimable.plots).toBe(1);

      const claimed = await withTransaction(db, (tx) =>
        claimGarden(tx, world, player.playerId, {}, readyAt),
      );
      expect(claimed.dongfu.plots[0]?.status).toBe("empty");
      expect(claimed.dongfu.claimable.plots).toBe(0);
      expect(claimed.gained).toEqual([{ itemSlug: "herb_lingcao", quantity: 1 }]);
      const herbs = await db
        .select()
        .from(playerItems)
        .where(and(eq(playerItems.playerId, player.playerId), eq(playerItems.itemSlug, "herb_lingcao")));
      expect(herbs[0]?.quantity).toBe(1);
      const plotRows = await db.select().from(playerDongfuPlots).where(eq(playerDongfuPlots.playerId, player.playerId));
      expect(plotRows).toHaveLength(0);
    });
  });

  it("rejects plant on occupied slot and unknown seed", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-10-29T04:00:00.000Z");
      const player = await registerPlayer(db, { username: "busy", password: "correct-horse", now });
      await giveStack(db, player.playerId, "seed_lingcao", 3, now);
      const world = await loadCurrentWorld(db);
      if (!world) throw new Error("no world");
      await withTransaction(db, (tx) => plantSeed(tx, world, player.playerId, { slot: 1, seedSlug: "seed_lingcao" }, now));
      await expect(
        withTransaction(db, (tx) => plantSeed(tx, world, player.playerId, { slot: 1, seedSlug: "seed_lingcao" }, now)),
      ).rejects.toMatchObject({ code: "INVALID_INPUT" });
      await expect(
        withTransaction(db, (tx) => plantSeed(tx, world, player.playerId, { slot: 2, seedSlug: "seed_nope" }, now)),
      ).rejects.toMatchObject({ code: "INVALID_INPUT" });
    });
  });

  it("starts alchemy, waits, claims pill; QUEUE_FULL when queue is full", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-10-29T05:00:00.000Z");
      const player = await registerPlayer(db, { username: "alchemist", password: "correct-horse", now });
      await giveStack(db, player.playerId, "herb_lingcao", 10, now);
      await giveStack(db, player.playerId, "herb_qingxin", 10, now);
      const world = await loadCurrentWorld(db);
      if (!world) throw new Error("no world");

      const first = await withTransaction(db, (tx) =>
        startAlchemy(tx, world, player.playerId, { recipeSlug: "pill_cultivate" }, now),
      );
      expect(first.dongfu.alchemy).toHaveLength(1);
      expect(first.dongfu.alchemy[0]).toMatchObject({
        recipeSlug: "pill_cultivate",
        outputItemSlug: "pill_cultivate",
        outputQty: 1,
        status: "crafting",
      });
      expect(first.dongfu.alchemyQueueLength).toBe(2);

      await withTransaction(db, (tx) =>
        startAlchemy(tx, world, player.playerId, { recipeSlug: "pill_cultivate" }, now),
      );
      await expect(
        withTransaction(db, (tx) => startAlchemy(tx, world, player.playerId, { recipeSlug: "pill_cultivate" }, now)),
      ).rejects.toBeInstanceOf(AppError);
      await expect(
        withTransaction(db, (tx) => startAlchemy(tx, world, player.playerId, { recipeSlug: "pill_cultivate" }, now)),
      ).rejects.toMatchObject({ code: "QUEUE_FULL" });

      const readyAt = new Date(now.getTime() + 30_000);
      const claimed = await withTransaction(db, (tx) => claimAlchemy(tx, world, player.playerId, {}, readyAt));
      expect(claimed.gained).toEqual([
        { itemSlug: "pill_cultivate", quantity: 1 },
        { itemSlug: "pill_cultivate", quantity: 1 },
      ]);
      expect(claimed.dongfu.alchemy).toHaveLength(0);
      expect(claimed.dongfu.claimable.alchemy).toBe(0);
      const pills = await db
        .select()
        .from(playerItems)
        .where(and(eq(playerItems.playerId, player.playerId), eq(playerItems.itemSlug, "pill_cultivate")));
      expect(pills[0]?.quantity).toBe(2);
      const openJobs = await db
        .select()
        .from(playerDongfuAlchemy)
        .where(and(eq(playerDongfuAlchemy.playerId, player.playerId), isNull(playerDongfuAlchemy.claimedAt)));
      expect(openJobs).toHaveLength(0);
    });
  });

  it("throws BAG_FULL when claiming into a full bag with no existing herb stack", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const plantedAt = new Date("2026-10-29T06:00:00.000Z");
      const player = await registerPlayer(db, { username: "fullbag", password: "correct-horse", now: plantedAt });
      await giveStack(db, player.playerId, "seed_lingcao", 1, plantedAt);
      // 填满 20 格装备
      for (let i = 0; i < 20; i += 1) {
        await db.insert(playerItems).values({
          playerId: player.playerId,
          itemSlug: `filler_${i}`,
          isStack: false,
          quantity: 1,
          source: "test",
          acquiredAt: plantedAt,
        });
      }
      const world = await loadCurrentWorld(db);
      if (!world) throw new Error("no world");
      await withTransaction(db, (tx) =>
        plantSeed(tx, world, player.playerId, { slot: 0, seedSlug: "seed_lingcao" }, plantedAt),
      );
      const readyAt = new Date(plantedAt.getTime() + 60_000);
      await expect(
        withTransaction(db, (tx) => claimGarden(tx, world, player.playerId, {}, readyAt)),
      ).rejects.toMatchObject({ code: "BAG_FULL", message: "行囊已满，请先分解或使用" });
    });
  });

  it("useItem pill_cultivate adds cultivation; temp pill writes active buff", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-10-29T07:00:00.000Z");
      const player = await registerPlayer(db, { username: "piller", password: "correct-horse", now });
      const [cultPill] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: "pill_cultivate", isStack: true, quantity: 1, source: "test", acquiredAt: now })
        .returning();
      const [atkPill] = await db
        .insert(playerItems)
        .values({ playerId: player.playerId, itemSlug: "pill_atk_temp", isStack: true, quantity: 1, source: "test", acquiredAt: now })
        .returning();
      await db.update(playerStates).set({ cultivation: 50 }).where(eq(playerStates.playerId, player.playerId));
      const world = await loadCurrentWorld(db);
      if (!world || !cultPill || !atkPill) throw new Error("no world");

      const used = await withTransaction(db, (tx) => useItem(tx, world, player.playerId, cultPill.id, now));
      expect(used.state.cultivation).toBeGreaterThanOrEqual(150);
      expect(used).toMatchObject({ used: { itemSlug: "pill_cultivate", cultivationGain: 100 } });

      const buffed = await withTransaction(db, (tx) => useItem(tx, world, player.playerId, atkPill.id, now));
      expect(buffed).toMatchObject({
        used: { itemSlug: "pill_atk_temp", buffStat: "attack", buffBp: 1000, durationSeconds: 300 },
      });
      const buffs = await db.select().from(playerActiveBuffs).where(eq(playerActiveBuffs.playerId, player.playerId));
      expect(buffs).toHaveLength(1);
      expect(buffs[0]).toMatchObject({ buffStat: "attack", buffBp: 1000, sourceItemSlug: "pill_atk_temp" });
    });
  });
});

describe("dongfu servant allocation and facility upgrade", () => {
  it("grants starter servants and wood, then shortens grow time when servants are assigned", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const plantedAt = new Date("2026-10-29T08:00:00.000Z");
      const player = await registerPlayer(db, { username: "warden", password: "correct-horse", now: plantedAt });
      await giveStack(db, player.playerId, "seed_lingcao", 2, plantedAt);
      const world = await loadCurrentWorld(db);
      if (!world) throw new Error("no world");

      const opened = await withTransaction(db, (tx) => readDongfuState(tx, world, player.playerId, plantedAt));
      expect(opened.servantTotal).toBe(4);
      expect(opened.allocation).toEqual({ garden: 0, alchemy: 0 });
      expect(opened.woodCount).toBe(32);
      expect(opened.timeScale.garden).toBe(1);
      expect(opened.upgrades.garden.canUpgrade).toBe(true);

      const assigned = await withTransaction(db, (tx) =>
        allocateServants(tx, world, player.playerId, { garden: 4, alchemy: 0 }, plantedAt),
      );
      expect(assigned.dongfu.timeScale.garden).toBe(0.8);
      expect(assigned.dongfu.allocation).toEqual({ garden: 4, alchemy: 0 });

      const planted = await withTransaction(db, (tx) =>
        plantSeed(tx, world, player.playerId, { slot: 0, seedSlug: "seed_lingcao" }, plantedAt),
      );
      expect(planted.dongfu.plots[0]?.matureAt).toBe(new Date(plantedAt.getTime() + 48_000).toISOString());

      await expect(
        withTransaction(db, (tx) => allocateServants(tx, world, player.playerId, { garden: 3, alchemy: 2 }, plantedAt)),
      ).rejects.toMatchObject({ code: "INVALID_INPUT" });
    });
  });

  it("rescales the remaining grow time when allocation changes", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const plantedAt = new Date("2026-10-29T08:10:00.000Z");
      const player = await registerPlayer(db, { username: "shift", password: "correct-horse", now: plantedAt });
      await giveStack(db, player.playerId, "seed_lingcao", 1, plantedAt);
      const world = await loadCurrentWorld(db);
      if (!world) throw new Error("no world");
      await withTransaction(db, (tx) => plantSeed(tx, world, player.playerId, { slot: 0, seedSlug: "seed_lingcao" }, plantedAt));
      const midway = new Date(plantedAt.getTime() + 30_000);
      const shifted = await withTransaction(db, (tx) =>
        allocateServants(tx, world, player.playerId, { garden: 4, alchemy: 0 }, midway),
      );
      expect(shifted.dongfu.plots[0]?.matureAt).toBe(new Date(midway.getTime() + 24_000).toISOString());
      expect(shifted.dongfu.plots[0]?.status).toBe("growing");
    });
  });

  it("spends spirit wood to add a garden plot and an alchemy queue", async () => {
    await withDb(async (db) => {
      await seedWorld(db, { ...DEFAULT_DONGFU, startingWood: 0 });
      const now = new Date("2026-10-29T08:20:00.000Z");
      const player = await registerPlayer(db, { username: "builder", password: "correct-horse", now });
      await giveStack(db, player.playerId, "herb_lingcao", 8, now);
      const world = await loadCurrentWorld(db);
      if (!world) throw new Error("no world");

      await expect(
        withTransaction(db, (tx) => upgradeFacility(tx, world, player.playerId, "garden", now)),
      ).rejects.toMatchObject({ code: "MATERIAL_SHORT" });

      await giveStack(db, player.playerId, "wood_lingmu", 8, now);
      const garden = await withTransaction(db, (tx) => upgradeFacility(tx, world, player.playerId, "garden", now));
      expect(garden.dongfu.gardenLevel).toBe(2);
      expect(garden.dongfu.plotCount).toBe(5);
      expect(garden.dongfu.plots).toHaveLength(5);
      expect(garden.dongfu.woodCount).toBe(0);

      await giveStack(db, player.playerId, "wood_lingmu", 8, now);
      const alchemy = await withTransaction(db, (tx) => upgradeFacility(tx, world, player.playerId, "alchemy", now));
      expect(alchemy.dongfu.alchemyLevel).toBe(2);
      expect(alchemy.dongfu.alchemyQueueLength).toBe(3);
      await withTransaction(db, (tx) => startAlchemy(tx, world, player.playerId, { recipeSlug: "pill_cultivate" }, now));
      await withTransaction(db, (tx) => startAlchemy(tx, world, player.playerId, { recipeSlug: "pill_cultivate" }, now));
      const third = await withTransaction(db, (tx) =>
        startAlchemy(tx, world, player.playerId, { recipeSlug: "pill_cultivate" }, now),
      );
      expect(third.dongfu.alchemy).toHaveLength(3);
      expect(third.dongfu.alchemy[0]?.readyAt).toBe(new Date(now.getTime() + 30_000).toISOString());
    });
  });

  it("shortens an in-progress alchemy job when servants move to the furnace", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-10-29T08:30:00.000Z");
      const player = await registerPlayer(db, { username: "furnace", password: "correct-horse", now });
      await giveStack(db, player.playerId, "herb_lingcao", 4, now);
      const world = await loadCurrentWorld(db);
      if (!world) throw new Error("no world");
      const started = await withTransaction(db, (tx) =>
        startAlchemy(tx, world, player.playerId, { recipeSlug: "pill_cultivate" }, now),
      );
      expect(started.dongfu.alchemy[0]?.readyAt).toBe(new Date(now.getTime() + 30_000).toISOString());
      const later = new Date(now.getTime() + 10_000);
      const shifted = await withTransaction(db, (tx) =>
        allocateServants(tx, world, player.playerId, { garden: 0, alchemy: 4 }, later),
      );
      // 已过 10/30，剩余 2/3；新总时长 24s，剩余 16s。
      expect(shifted.dongfu.alchemy[0]?.readyAt).toBe(new Date(later.getTime() + 16_000).toISOString());
      expect(shifted.dongfu.timeScale.alchemy).toBe(0.8);
    });
  });
});
