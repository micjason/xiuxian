import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentDropTables, contentGlobals, contentItems, contentRealms, contentStages, playerItems, playerStates } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { STARTING_ENHANCE_RULES } from "../content/enhance.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { challengeStage } from "./actions.js";
import { grantItem } from "./bag.js";

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
const options = (patch: Partial<Parameters<typeof grantItem>[7]> = {}) => ({ autoDecompose: true, capacity: 3, ...patch });

describe("bag capacity and auto-decompose (table 2.6 / 3.7)", () => {
  it("new players have the switch on by default", async () => {
    await withDb(async (db) => {
      const { player } = await seed(db);
      const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, player.playerId));
      expect(state?.autoDecompose).toBe(true);
    });
  });

  it("puts the item in the bag while there is a free slot", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      const result = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "blue_a", 1, "test", now, options()));
      expect(result).toMatchObject({ added: 1, decomposed: 0, dropped: 0 });
      expect(await bagOf(db, player.playerId)).toEqual(["blue_a"]);
    });
  });

  it("full bag, switch on: a new white/green piece is decomposed straight into enhancement exp", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      await fill(db, player.playerId, [{ itemSlug: "blue_a" }, { itemSlug: "blue_a" }, { itemSlug: "purple_a" }]);
      const white = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "white_a", 1, "test", now, options()));
      expect(white).toMatchObject({ added: 0, decomposed: 1, dropped: 0, enhanceExp: 30 });
      const green = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "green_a", 1, "test", now, options()));
      expect(green).toMatchObject({ decomposed: 1, enhanceExp: 60 });
      expect((await bagOf(db, player.playerId)).length).toBe(3);
      const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, player.playerId));
      expect(state?.enhanceExp).toBe(90);
    });
  });

  it("full bag, switch on: a new blue/purple piece decomposes one unenhanced white to free a slot", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      await fill(db, player.playerId, [{ itemSlug: "green_a" }, { itemSlug: "white_a" }, { itemSlug: "purple_a" }]);
      const result = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "blue_a", 1, "test", now, options()));
      expect(result).toMatchObject({ added: 1, dropped: 0, decomposed: 0, enhanceExp: 30 });
      expect(result.freed).toEqual([{ itemSlug: "white_a", enhanceExp: 30 }]);
      // 先白后绿：白的被分解，绿的还在
      expect(await bagOf(db, player.playerId)).toEqual(["blue_a", "green_a", "purple_a"]);
    });
  });

  it("full bag: never decomposes blue, purple, worn or enhanced pieces; the new drop is lost with a prompt", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      await fill(db, player.playerId, [{ itemSlug: "blue_a" }, { itemSlug: "purple_a" }, { itemSlug: "white_a", enhanceLevel: 2 }, { itemSlug: "white_b", equippedSlot: "helmet" }]);
      const result = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "purple_a", 1, "test", now, options()));
      expect(result).toMatchObject({ added: 0, dropped: 1, reason: "BAG_FULL", enhanceExp: 0 });
      expect((await bagOf(db, player.playerId)).length).toBe(4);
    });
  });

  it("full bag, switch off: nothing is dropped into the bag and nothing is decomposed", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      await fill(db, player.playerId, [{ itemSlug: "white_a" }, { itemSlug: "white_b" }, { itemSlug: "green_a" }]);
      const result = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "blue_a", 1, "test", now, options({ autoDecompose: false })));
      expect(result).toMatchObject({ added: 0, dropped: 1, reason: "BAG_FULL", enhanceExp: 0 });
      const white = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "white_a", 1, "test", now, options({ autoDecompose: false })));
      expect(white).toMatchObject({ dropped: 1, decomposed: 0 });
      expect((await bagOf(db, player.playerId)).length).toBe(3);
    });
  });

  it("stackable materials join an existing stack without needing a slot", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "stone", 2, "test", now, options()));
      await fill(db, player.playerId, [{ itemSlug: "blue_a" }, { itemSlug: "blue_a" }]);
      const result = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "stone", 3, "test", now, options({ autoDecompose: false })));
      expect(result).toMatchObject({ added: 1, dropped: 0 });
      const [row] = await db.select().from(playerItems).where(eq(playerItems.itemSlug, "stone"));
      expect(row?.quantity).toBe(5);
    });
  });

  it("first-clear rewards may temporarily exceed the capacity", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      await fill(db, player.playerId, [{ itemSlug: "blue_a" }, { itemSlug: "blue_a" }, { itemSlug: "purple_a" }]);
      const result = await withTransaction(db, (tx) => grantItem(tx, world, player.playerId, "blue_a", 1, "test", now, options({ overflow: true })));
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

  it("switch on: frees one slot by decomposing a white piece and fights", async () => {
    await withDb(async (db) => {
      const { player, world } = await seedStage(db);
      await fill(db, player.playerId, [{ itemSlug: "white_a" }, { itemSlug: "blue_a" }, { itemSlug: "purple_a" }]);
      const result = await withTransaction(db, (tx) => challengeStage(tx, world, player.playerId, "s1", now, () => 0));
      expect(result.battle.win).toBe(true);
      expect(result.freedBeforeFight).toEqual([{ itemSlug: "white_a", enhanceExp: 30 }]);
      expect(await bagOf(db, player.playerId)).toEqual(["blue_a", "purple_a"]);
    });
  });

  it("switch on but nothing to decompose, or switch off: refuses with BAG_FULL", async () => {
    await withDb(async (db) => {
      const { player, world } = await seedStage(db);
      await fill(db, player.playerId, [{ itemSlug: "blue_a" }, { itemSlug: "blue_a" }, { itemSlug: "purple_a" }]);
      await expect(withTransaction(db, (tx) => challengeStage(tx, world, player.playerId, "s1", now, () => 0))).rejects.toMatchObject({ code: "BAG_FULL" });
      await db.delete(playerItems).where(eq(playerItems.itemSlug, "purple_a"));
      await fill(db, player.playerId, [{ itemSlug: "white_a" }]);
      await db.update(playerStates).set({ autoDecompose: false }).where(eq(playerStates.playerId, player.playerId));
      await expect(withTransaction(db, (tx) => challengeStage(tx, world, player.playerId, "s1", now, () => 0))).rejects.toMatchObject({ code: "BAG_FULL" });
    });
  });
});
