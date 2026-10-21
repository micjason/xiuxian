import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentDropTables, contentGlobals, contentItems, contentRealms, contentStages, equipmentGrants, playerItems, playerStates } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { STARTING_ENHANCE_RULES } from "../content/enhance.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { challengeStage } from "./actions.js";
import { grantItem } from "./bag.js";
import { readGrantResult } from "./boss-rewards.js";
import { grantEquipment } from "../player/grant.js";
import { tuningOf } from "../content/tuning.js";

const now = new Date("2026-10-10T12:00:00.000Z");
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

async function seed(db: TestDb) {
  await db.insert(contentRealms).values({ slug: "1", displayName: "凡人", sortOrder: 1, nextRealmSlug: null, baseAttack: 100, baseDefense: 10, baseHp: 500, baseInterval: 1.5, tickSeconds: 1, gainPerTick: 1 });
  await db.insert(contentGlobals).values({
    id: 1,
    offlineCapSeconds: 3600,
    bagCapacity: 3,
    enhance: STARTING_ENHANCE_RULES,
    powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
    combat: { minInterval: 0.5, defenseConstant: 1, recommendedPowerMargin: 1.05, challengeCooldownSeconds: 0, timeLimitSeconds: 45, speedBase: 100 },
  });
  const gear = (slug: string, quality: string, slot = "weapon") => ({ slug, displayName: slug, kind: "equipment", slot, quality, attack: 5, defense: 0, hp: 0, speed: 0 });
  await db.insert(contentItems).values([
    gear("white_a", "white"),
    gear("white_b", "white", "helmet"),
    gear("green_a", "green", "clothes"),
    gear("blue_a", "blue", "gloves"),
    gear("purple_a", "purple", "shoes"),
    { slug: "stone", displayName: "突破石", kind: "material", quality: "green", stackable: true },
  ]);
  const player = await registerPlayer(db, { username: "bagger", password: "correct-horse", now });
  const world = await loadCurrentWorld(db);
  if (!world) throw new Error("no world");
  return { player, world };
}

async function fill(db: TestDb, playerId: string, rows: { itemSlug: string; enhanceLevel?: number; equippedSlot?: string }[]) {
  let tick = 0;
  for (const row of rows) {
    tick += 1;
    await db.insert(playerItems).values({ playerId, itemSlug: row.itemSlug, isStack: false, quantity: 1, enhanceLevel: row.enhanceLevel ?? 0, equippedSlot: row.equippedSlot ?? null, source: "test", acquiredAt: new Date(now.getTime() + tick * 1000) });
  }
}

const bagOf = async (db: TestDb, playerId: string) => (await db.select().from(playerItems).where(eq(playerItems.playerId, playerId))).map((row) => row.itemSlug).sort();
const options = (patch: Partial<Parameters<typeof grantItem>[7]> = {}) => ({ capacity: 3, ...patch });

describe("bag capacity (第五批：满包不发装备，不再自动分解；SPEC_Q §17.5)", () => {
  it("puts the item in the bag while there is a free slot", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      const result = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "blue_a", 1, "wave:s1", now, options()));
      expect(result).toMatchObject({ added: 1, decomposed: 0, dropped: 0 });
      expect(await bagOf(db, player.playerId)).toEqual(["blue_a"]);
    });
  });

  it("full bag: stage drops and boss gear (first / repeat) are not granted, whatever the quality; nothing is decomposed", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      await fill(db, player.playerId, [{ itemSlug: "white_a" }, { itemSlug: "green_a" }, { itemSlug: "purple_a" }]);
      for (const [slug, source, overflow] of [["white_a", "wave:s1", false], ["blue_a", "wave:s1", false], ["purple_a", "drop:s1", true], ["green_a", "drop:s1", false]] as const) {
        const result = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, slug, 1, source, now, options({ overflow })));
        expect(result).toMatchObject({ added: 0, dropped: 1, reason: "BAG_FULL", decomposed: 0, enhanceExp: 0, freed: [] });
      }
      expect(await bagOf(db, player.playerId)).toEqual(["green_a", "purple_a", "white_a"]);
      const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, player.playerId));
      expect(state?.enhanceExp).toBe(0);
    });
  });

  it("grantEquipment returns skipped bag_full for stage_drop / boss_first / boss_repeat, while admin_grant / mail / event still overflow", async () => {
    await withDb(async (db) => {
      const { player } = await seed(db);
      await fill(db, player.playerId, [{ itemSlug: "white_a" }, { itemSlug: "green_a" }, { itemSlug: "purple_a" }]);
      const bag = { capacity: 3, skipSources: ["stage_drop", "boss_first", "boss_repeat"] };
      for (const source of ["stage_drop", "boss_first", "boss_repeat"] as const) {
        const result = await withTransaction(db, (tx) => grantEquipment(tx, { playerId: player.playerId, itemId: "blue_a", count: 1, source, requestId: `full-${source}`, bag }));
        expect(result).toHaveLength(0);
        expect(result.skipped).toBe("bag_full");
        expect(result.bagFull).toBe(true);
        expect(readGrantResult(result)).toEqual({ count: 0, skipped: "bag_full" });
      }
      // 被跳过的不写流水、不占单号
      expect(await db.select().from(equipmentGrants)).toEqual([]);
      for (const source of ["admin_grant", "mail", "event"] as const) {
        const result = await withTransaction(db, (tx) => grantEquipment(tx, { playerId: player.playerId, itemId: "blue_a", count: 1, source, requestId: `over-${source}`, bag }));
        expect(result).toHaveLength(1);
        expect(result.skipped).toBeUndefined();
      }
      expect((await bagOf(db, player.playerId)).length).toBe(6);
      // 不传 bag：按当前内容（bagCapacity 3 + bagBonus）和配置概览的来源现算
      const self = await withTransaction(db, (tx) => grantEquipment(tx, { playerId: player.playerId, itemId: "blue_a", count: 1, source: "stage_drop", requestId: "self-policy" }));
      expect(self.skipped).toBe("bag_full");
    });
  });

  it("the skip list comes from 配置概览 (tuning.bagFullSkipSources); old tuning with autoDecomposeQualities is still read", async () => {
    await withDb(async (db) => {
      const { player } = await seed(db);
      await db.update(contentGlobals).set({ tuning: { autoDecomposeQualities: ["white", "green"], bagFullSkipSources: ["boss_first"] } as never });
      const world = (await loadCurrentWorld(db))!;
      expect(tuningOf(world.globals.tuning).bagFullSkipSources).toEqual(["boss_first"]);
      await fill(db, player.playerId, [{ itemSlug: "white_a" }, { itemSlug: "green_a" }, { itemSlug: "purple_a" }]);
      const wave = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "blue_a", 1, "wave:s1", now, options()));
      expect(wave).toMatchObject({ added: 1, dropped: 0 });
      const first = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "blue_a", 1, "drop:s1", now, options({ overflow: true })));
      expect(first).toMatchObject({ added: 0, dropped: 1 });
      // 老数据只有 autoDecomposeQualities（没有新字段）：用默认三种来源
      await db.update(contentGlobals).set({ tuning: { autoDecomposeQualities: ["white"] } as never });
      expect(tuningOf((await loadCurrentWorld(db))!.globals.tuning).bagFullSkipSources).toEqual(["stage_drop", "boss_first", "boss_repeat"]);
    });
  });

  it("stackable materials join an existing stack and are never refused, even past the capacity", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "stone", 2, "test", now, options()));
      await fill(db, player.playerId, [{ itemSlug: "blue_a" }, { itemSlug: "blue_a" }]);
      const result = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "stone", 3, "test", now, options()));
      expect(result).toMatchObject({ added: 1, dropped: 0 });
      const [row] = await db.select().from(playerItems).where(eq(playerItems.itemSlug, "stone"));
      expect(row?.quantity).toBe(5);
    });
  });

  it("event sources (e.g. the starter kit) may temporarily exceed the capacity", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      await fill(db, player.playerId, [{ itemSlug: "blue_a" }, { itemSlug: "blue_a" }, { itemSlug: "purple_a" }]);
      const result = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "blue_a", 1, "starter", now, options({ overflow: true })));
      expect(result).toMatchObject({ added: 1, dropped: 0 });
      expect((await bagOf(db, player.playerId)).length).toBe(4);
    });
  });
});

describe("challenge with a full bag", () => {
  async function seedStage(db: TestDb) {
    const base = await seed(db);
    await db.insert(contentDropTables).values([{ slug: "d_boss", displayName: "x" }, { slug: "d_idle", displayName: "x" }, { slug: "d_first", displayName: "x" }]);
    await db.insert(contentStages).values({
      slug: "s1",
      displayName: "关一",
      sortOrder: 1,
      requiredRealmOrder: 1,
      nextStageSlug: null,
      bossName: "弱",
      bossAttack: 1,
      bossDefense: 0,
      bossHp: 10,
      bossInterval: 1.5,
      bosses: [{ name: "弱", attack: 1, defense: 0, hp: 10, interval: 1.5, drops: [] }],
      bossDropTableSlug: "d_boss",
      idleDropTableSlug: "d_idle",
      firstClearDropTableSlug: "d_first",
    });
    return { ...base, world: (await loadCurrentWorld(db))! };
  }

  it("full bag never refuses the challenge and the bag is left alone before the fight", async () => {
    await withDb(async (db) => {
      const { player, world } = await seedStage(db);
      await fill(db, player.playerId, [{ itemSlug: "white_a" }, { itemSlug: "blue_a" }, { itemSlug: "purple_a" }]);
      const result = await withTransaction(db, (tx) => challengeStage(tx, world, player.playerId, "s1", now, () => 0));
      expect(result.battle.win).toBe(true);
      expect(result).not.toHaveProperty("freedBeforeFight");
      expect((await bagOf(db, player.playerId)).sort()).toEqual(["blue_a", "purple_a", "white_a"]);
    });
  });

  it("full bag: still fights (no BAG_FULL refusal), with or without the old switch", async () => {
    await withDb(async (db) => {
      const { player, world } = await seedStage(db);
      await fill(db, player.playerId, [{ itemSlug: "blue_a" }, { itemSlug: "blue_a" }, { itemSlug: "purple_a" }]);
      const first = await withTransaction(db, (tx) => challengeStage(tx, world, player.playerId, "s1", now, () => 0));
      expect(first.battle.win).toBe(true);
      await db.delete(playerItems).where(eq(playerItems.itemSlug, "purple_a"));
      await fill(db, player.playerId, [{ itemSlug: "white_a" }]);
      await db.update(playerStates).set({ autoDecompose: false }).where(eq(playerStates.playerId, player.playerId));
      const second = await withTransaction(db, (tx) => challengeStage(tx, world, player.playerId, "s1", now, () => 0));
      expect(second.battle.win).toBe(true);
    });
  });
});
