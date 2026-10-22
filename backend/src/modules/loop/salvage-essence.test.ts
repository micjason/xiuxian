/**
 * 第五批：玩家自选分解 → 炼器精粹；强化消耗精粹；强化经验一次性换成精粹（SPEC_Q §17.2 / 17.3）。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../../app.js";
import { contentGlobals, contentItems, contentRealms, enhanceExpMigrations, playerItems, playerStates, players } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { testAdmin } from "../../test/admin.js";
import { registerPlayer } from "../auth/service.js";
import {
  DEFAULT_REALM_YIELD_MULT,
  ENHANCE_QUALITIES,
  enhanceCost,
  enhanceRulesFromInput,
  essenceCost,
  essenceYield,
  migratedEssence,
  minSafeMigrationRatioBp,
  STARTING_ENHANCE_RULES,
  STARTING_ESSENCE_RULES,
  type EnhanceRules,
} from "../content/enhance.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { decomposeItems, readState } from "./actions.js";
import { migrateAllEnhanceExp, migratePlayerEnhanceExp } from "./essence-migration.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const now = new Date("2026-10-10T12:00:00.000Z");

describe("炼器精粹 rules", () => {
  const rules = enhanceRulesFromInput(STARTING_ENHANCE_RULES);

  it("金丹档一口价：白20/绿60/蓝150/紫400/橙1000，返还每级 40", () => {
    expect(ENHANCE_QUALITIES.map((q) => essenceYield(rules, q.key, "weapon", 0, "core"))).toEqual([20, 60, 150, 400, 1000]);
    expect(essenceYield(rules, "purple", "shoes", 3, "core")).toBe(400 + 3 * 40);
    expect(essenceYield(rules, "orange", "accessory", 5, "core")).toBe(1000 + 200);
  });

  it("按大境界倍率分档：炼气白+10=105；未强化金丹紫=400", () => {
    expect(essenceYield(rules, "white", "weapon", 10, "qi")).toBe(105);
    expect(essenceYield(rules, "purple", "weapon", 0, "core")).toBe(400);
    expect(essenceYield(rules, "green", "weapon", 0, "foundation")).toBe(27);
    expect(essenceYield(rules, "white", "weapon", 0, "qi")).toBe(5);
    // 缺 major → 炼气
    expect(essenceYield(rules, "white", "weapon", 0, null)).toBe(5);
    expect(essenceYield(rules, "white", "weapon", 0, "unknown")).toBe(5);
  });

  it("金丹匹配精粹/时 ≥ 刷筑基一约 1.1×、≥ 刷炼气一约 3×（固定装/时×权重 EV 夹具）", () => {
    // 决策稿 §1–2：装/时与件均 EV（一口价×倍率后的期望）
    const gearPerHour = { coreMatch: 46.7, coreFarmFoundation1: 122.9, coreFarmQi1: 122.9 };
    const weightsEv = {
      qi: 0.7 * 20 + 0.25 * 60 + 0.05 * 150 + 0 * 400, // 36.5
      foundation: 0.5 * 20 + 0.35 * 60 + 0.13 * 150 + 0.02 * 400, // 58.5
      core: 0.35 * 20 + 0.4 * 60 + 0.2 * 150 + 0.05 * 400, // 81
    };
    const m = DEFAULT_REALM_YIELD_MULT;
    const coreMatch = gearPerHour.coreMatch * weightsEv.core * m.core;
    const farmF = gearPerHour.coreFarmFoundation1 * weightsEv.foundation * m.foundation;
    const farmQ = gearPerHour.coreFarmQi1 * weightsEv.qi * m.qi;
    expect(coreMatch / farmF).toBeGreaterThanOrEqual(1.1);
    expect(coreMatch / farmQ).toBeGreaterThanOrEqual(3);
  });

  it("旧存档缺 realmYieldMult 时读入默认倍率", () => {
    const { realmYieldMult: _drop, ...without } = STARTING_ESSENCE_RULES;
    const parsed = enhanceRulesFromInput({ ...STARTING_ENHANCE_RULES, essence: without });
    expect(parsed.essence?.realmYieldMult).toEqual(DEFAULT_REALM_YIELD_MULT);
  });

  it("per-slot multiplier and per quality+slot override are read from config", () => {
    const edited = enhanceRulesFromInput({ ...STARTING_ENHANCE_RULES, essence: { ...STARTING_ESSENCE_RULES, slotMultBp: { weapon: 15000 }, slotOverrides: { blue: { shoes: 999 } } } });
    // 倍率用金丹档，与改前一口价行为一致
    expect(essenceYield(edited, "white", "weapon", 0, "core")).toBe(30);
    expect(essenceYield(edited, "white", "helmet", 0, "core")).toBe(20);
    expect(essenceYield(edited, "blue", "shoes", 2, "core")).toBe(999 + 80);
    expect(essenceYield(edited, "blue", "weapon", 0, "core")).toBe(225);
    // 炼气：白×0.25×1.5 部位 = round(7.5)=8；返还 round(40×0.25)=10
    expect(essenceYield(edited, "white", "weapon", 2, "qi")).toBe(8 + 20);
  });

  it("enhance cost = round(40 × 1.25^level × quality costMult), with an optional per-level table", () => {
    expect([0, 1, 2, 3, 4].map((level) => essenceCost(rules, "white", level))).toEqual([40, 50, 63, 78, 98]);
    expect(essenceCost(rules, "blue", 2)).toBe(Math.round(40 * 1.25 ** 2 * 1.25));
    const table = enhanceRulesFromInput({ ...STARTING_ENHANCE_RULES, essence: { ...STARTING_ESSENCE_RULES, costTable: { white: [5, null, 7] } } });
    expect([0, 1, 2, 3].map((level) => essenceCost(table, "white", level))).toEqual([5, 50, 7, 78]);
  });

  it("validates the config (no negative yields, growth ≥ 1, an item is required)", () => {
    const bad = (essence: Record<string, unknown>) => () => enhanceRulesFromInput({ ...STARTING_ENHANCE_RULES, essence: { ...STARTING_ESSENCE_RULES, ...essence } });
    expect(bad({ yields: { ...STARTING_ESSENCE_RULES.yields, white: -1 } })).toThrow(/白/);
    expect(bad({ costGrowth: 0.9 })).toThrow(/增长倍数/);
    expect(bad({ itemSlug: "" })).toThrow(/炼器精粹对应的物品/);
    expect(bad({ costTable: { white: [0] } })).toThrow(/每级精粹消耗/);
  });

  it("the default migration ratio (7000) is above the worst essence/old-exp cost ratio, so nobody gets weaker", () => {
    const worst = minSafeMigrationRatioBp(rules);
    expect(worst).toBeGreaterThan(6600);
    expect(worst).toBeLessThanOrEqual(STARTING_ESSENCE_RULES.migrationRatioBp);
    // 暴力验证：任意经验池、任意品质、从任意等级起，旧经验能升到的等级，换成精粹后一定也能升到
    const levelsWith = (pool: number, cost: (level: number) => number, from: number, cap: number) => {
      let level = from;
      while (level < cap && pool >= cost(level)) {
        pool -= cost(level);
        level += 1;
      }
      return level;
    };
    for (const quality of ENHANCE_QUALITIES) {
      const cap = rules.qualities[quality.key]!.cap;
      for (let from = 0; from < cap; from += 1) {
        for (let exp = 0; exp <= 20000; exp += 37) {
          const before = levelsWith(exp, (level) => enhanceCost(rules, quality.key, level), from, cap);
          const after = levelsWith(migratedEssence(rules, exp), (level) => essenceCost(rules, quality.key, level), from, cap);
          expect(after).toBeGreaterThanOrEqual(before);
        }
      }
    }
  });

  it("migration rounds up and uses the configured ratio", () => {
    expect(migratedEssence(rules, 0)).toBe(0);
    expect(migratedEssence(rules, 1)).toBe(1);
    expect(migratedEssence(rules, 100)).toBe(70);
    expect(migratedEssence(rules, 101)).toBe(71);
    const half = enhanceRulesFromInput({ ...STARTING_ENHANCE_RULES, essence: { ...STARTING_ESSENCE_RULES, migrationRatioBp: 5000 } });
    expect(migratedEssence(half, 101)).toBe(51);
  });
});

async function seed(db: TestDb, enhance: EnhanceRules | Record<string, unknown> = STARTING_ENHANCE_RULES) {
  // 金丹档：集成测沿用一口价绝对数；分档单测见上面「按大境界倍率分档」
  await db.insert(contentRealms).values({ slug: "1", displayName: "凡人", majorName: "金丹", majorKey: "core", sortOrder: 1, nextRealmSlug: null, baseAttack: 10, baseInterval: 1.5, gainPerTick: 1 });
  await db.insert(contentGlobals).values({
    id: 1,
    offlineCapSeconds: 3600,
    bagCapacity: 20,
    enhance: enhance as never,
    powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
    combat: { minInterval: 0.5, defenseConstant: 1, recommendedPowerMargin: 1.05, challengeCooldownSeconds: 0, timeLimitSeconds: 20, speedBase: 100 },
  });
  const gear = (slug: string, quality: string, slot: string) => ({ slug, displayName: slug, kind: "equipment", slot, quality, requiredRealmOrder: 1, attack: 5, defense: 0, hp: 0, speed: 0 });
  await db.insert(contentItems).values([
    gear("w", "white", "weapon"),
    gear("g", "green", "helmet"),
    gear("b", "blue", "gloves"),
    gear("p", "purple", "shoes"),
    gear("o", "orange", "accessory"),
    { slug: "refine_essence", displayName: "炼器精粹", kind: "material", quality: "orange", stackable: true },
    { slug: "stone", displayName: "石", kind: "material", quality: "green", stackable: true },
  ]);
  const player = await registerPlayer(db, { username: "salvager", password: "correct-horse", now });
  return { player, world: (await loadCurrentWorld(db))! };
}

async function give(db: TestDb, playerId: string, itemSlug: string, enhanceLevel = 0, equippedSlot: string | null = null) {
  const [row] = await db.insert(playerItems).values({ playerId, itemSlug, isStack: false, quantity: 1, enhanceLevel, equippedSlot, source: "test", acquiredAt: now }).returning();
  return row!;
}

const essenceOf = async (db: TestDb, playerId: string) =>
  (await db.select().from(playerItems).where(eq(playerItems.playerId, playerId))).filter((row) => row.itemSlug === "refine_essence").reduce((sum, row) => sum + row.quantity, 0);

describe("player-selected decompose", () => {
  it("decomposes exactly the chosen pieces into one essence stack (Σ quality yield + Σ level × 40)", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      const picked = [await give(db, player.playerId, "w"), await give(db, player.playerId, "g", 1), await give(db, player.playerId, "p", 2), await give(db, player.playerId, "o")];
      const kept = await give(db, player.playerId, "b");
      const result = await withTransaction(db, (tx) => decomposeItems(tx, world, player.playerId, picked.map((row) => row.id), now));
      expect(result.gainedEssence).toBe(20 + (60 + 40) + (400 + 80) + 1000);
      expect(result.decomposed.map((row) => row.essence)).toEqual(expect.arrayContaining([20, 100, 480, 1000]));
      expect(result.state.essence).toEqual({ itemSlug: "refine_essence", count: 1600 });
      const left = await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId));
      expect(left.map((row) => row.itemSlug).sort()).toEqual(["b", "refine_essence"]);
      expect(left.find((row) => row.itemSlug === "b")!.id).toBe(kept.id);
      // 再分解一次：并进同一堆
      const again = await withTransaction(db, (tx) => decomposeItems(tx, world, player.playerId, [kept.id], now));
      expect(again.gainedEssence).toBe(150);
      expect((await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId))).filter((row) => row.itemSlug === "refine_essence")).toHaveLength(1);
      expect(await essenceOf(db, player.playerId)).toBe(1750);
    });
  });

  it("refuses worn gear, non-gear, someone else's or missing pieces, and an empty selection — and changes nothing", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      const worn = await give(db, player.playerId, "b", 0, "gloves");
      const loose = await give(db, player.playerId, "w");
      const [stone] = await db.insert(playerItems).values({ playerId: player.playerId, itemSlug: "stone", isStack: true, quantity: 3, source: "test", acquiredAt: now }).returning();
      await expect(withTransaction(db, (tx) => decomposeItems(tx, world, player.playerId, [loose.id, worn.id], now))).rejects.toMatchObject({ code: "EQUIPPED_CANNOT_DECOMPOSE" });
      await expect(withTransaction(db, (tx) => decomposeItems(tx, world, player.playerId, [stone!.id], now))).rejects.toMatchObject({ code: "NOT_EQUIPMENT" });
      await expect(withTransaction(db, (tx) => decomposeItems(tx, world, player.playerId, [], now))).rejects.toThrow(/请先选择装备/);
      await expect(withTransaction(db, (tx) => decomposeItems(tx, world, player.playerId, ["00000000-0000-0000-0000-000000000000"], now))).rejects.toMatchObject({ code: "NOT_FOUND" });
      const other = await registerPlayer(db, { username: "other_one", password: "correct-horse", now });
      await expect(withTransaction(db, (tx) => decomposeItems(tx, world, other.playerId, [loose.id], now))).rejects.toMatchObject({ code: "NOT_FOUND" });
      expect((await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId))).length).toBe(3);
      expect(await essenceOf(db, player.playerId)).toBe(0);
    });
  });

  it("POST /me/items/decompose takes the selection and is idempotent per key", async () => {
    await withDb(async (db) => {
      const { player } = await seed(db);
      const app = await buildApp(db, () => now);
      const login = await app.inject({ method: "POST", url: "/api/v1/auth/login", payload: { username: "salvager", password: "correct-horse" } });
      const headers = { authorization: `Bearer ${login.json().token as string}`, "idempotency-key": "salvage-batch-0001" };
      const a = await give(db, player.playerId, "w");
      const b = await give(db, player.playerId, "g");
      const first = await app.inject({ method: "POST", url: "/api/v1/me/items/decompose", headers, payload: { itemIds: [a.id, b.id] } });
      expect(first.statusCode).toBe(200);
      expect(first.json()).toMatchObject({ gainedEssence: 80, essenceItemSlug: "refine_essence" });
      const replay = await app.inject({ method: "POST", url: "/api/v1/me/items/decompose", headers, payload: { itemIds: [a.id, b.id] } });
      expect(replay.json().gainedEssence).toBe(80);
      expect(await essenceOf(db, player.playerId)).toBe(80);
      const empty = await app.inject({ method: "POST", url: "/api/v1/me/items/decompose", headers: { ...headers, "idempotency-key": "salvage-batch-0002" }, payload: { itemIds: [] } });
      expect(empty.statusCode).toBe(400);
      await app.close();
    });
  });
});

describe("强化经验 → 炼器精粹 one-time migration", () => {
  it("converts on the next settle with the configured ratio, logs it once, and never pays twice", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      const sword = await give(db, player.playerId, "w", 3, "weapon");
      await db.update(playerStates).set({ enhanceExp: 1001 }).where(eq(playerStates.playerId, player.playerId));
      const state = await readState(db, player.playerId, now);
      expect(state.essence).toEqual({ itemSlug: "refine_essence", count: 701 });
      expect(state.enhanceExp).toBe(0);
      const [log] = await db.select().from(enhanceExpMigrations);
      expect(log).toMatchObject({ playerId: player.playerId, enhanceExp: 1001, essence: 701, ratioBp: 7000, itemSlug: "refine_essence" });
      // 已强化装备的等级不动
      expect((await db.select().from(playerItems).where(eq(playerItems.id, sword.id)))[0]!.enhanceLevel).toBe(3);
      // 再结算 / 再调一次：不重复
      await readState(db, player.playerId, now);
      await db.update(playerStates).set({ enhanceExp: 500 }).where(eq(playerStates.playerId, player.playerId));
      expect(await withTransaction(db, (tx) => migratePlayerEnhanceExp(tx, world, player.playerId, { enhanceExp: 500 }, now))).toBeNull();
      expect(await essenceOf(db, player.playerId)).toBe(701);
      expect(await db.select().from(enhanceExpMigrations)).toHaveLength(1);
    });
  });

  it("waits while the essence rules are missing (old snapshot), then converts once they are configured", async () => {
    await withDb(async (db) => {
      const { essence: _essence, ...old } = STARTING_ENHANCE_RULES;
      const { player } = await seed(db, old);
      await db.update(playerStates).set({ enhanceExp: 200 }).where(eq(playerStates.playerId, player.playerId));
      const before = await readState(db, player.playerId, now);
      expect(before.enhanceExp).toBe(200);
      expect(before.essence).toBeNull();
      await db.update(contentGlobals).set({ enhance: { ...old, essence: { ...STARTING_ESSENCE_RULES, migrationRatioBp: 10000 } } as never });
      expect((await readState(db, player.playerId, now)).essence).toEqual({ itemSlug: "refine_essence", count: 200 });
    });
  });

  it("the admin can run it for everyone at once (idempotent) and see the status", async () => {
    await withDb(async (db) => {
      const { player, world } = await seed(db);
      const second = await registerPlayer(db, { username: "second_one", password: "correct-horse", now });
      await registerPlayer(db, { username: "zero_exp", password: "correct-horse", now });
      await db.update(playerStates).set({ enhanceExp: 100 }).where(eq(playerStates.playerId, player.playerId));
      await db.update(playerStates).set({ enhanceExp: 10 }).where(eq(playerStates.playerId, second.playerId));
      const done = await migrateAllEnhanceExp(db, world, now);
      expect(done).toMatchObject({ migrated: 2, migratedPlayers: 2, migratedEnhanceExp: 110, migratedEssence: 70 + 7, pendingPlayers: 0 });
      expect(await migrateAllEnhanceExp(db, world, now)).toMatchObject({ migrated: 0, migratedPlayers: 2 });
      await testAdmin(db, "pb_admin");
      const app = await buildApp(db, () => now);
      const login = await app.inject({ method: "POST", url: "/admin/auth/login", payload: { username: "pb_admin", password: "admin-secret" } });
      const admin = { authorization: `Bearer ${login.json().token as string}` };
      const view = await app.inject({ method: "GET", url: "/admin/draft/enhance", headers: admin });
      expect(view.json()).toMatchObject({ migration: { migratedPlayers: 2, pendingPlayers: 0 }, minSafeRatioBp: expect.any(Number) });
      const run = await app.inject({ method: "POST", url: "/admin/draft/enhance/migrate-exp", headers: admin });
      expect(run.statusCode).toBe(200);
      expect(run.json()).toMatchObject({ migrated: 0, migratedPlayers: 2 });
      expect((await db.select().from(players)).length).toBe(3);
      await app.close();
    });
  });
});

describe("migration 0050", () => {
  const statements = () =>
    readFileSync(new URL("../../../drizzle/0050_refine_essence.sql", import.meta.url), "utf8")
      .split("--> statement-breakpoint")
      .map((part) => part.trim())
      .filter((part) => part.length > 0);

  it("seeds the essence item + rules and swaps the auto-decompose tuning, without touching admin edits; re-running is a no-op", async () => {
    await withDb(async (db) => {
      const { essence: _essence, ...old } = STARTING_ENHANCE_RULES;
      await db.insert(contentGlobals).values({ id: 1, enhance: { ...old, expBase: 77 } as never, tuning: { autoDecomposeQualities: ["white", "green"], gearBudgetRatio: 0.6 } as never });
      for (let round = 0; round < 2; round += 1) {
        for (const statement of statements()) {
          await db.execute(sql.raw(statement));
        }
      }
      const [row] = await db.select().from(contentGlobals);
      const parsed = enhanceRulesFromInput(row!.enhance);
      expect(parsed.expBase).toBe(77);
      expect(parsed.essence).toEqual(STARTING_ESSENCE_RULES);
      expect(row!.tuning).toEqual({ gearBudgetRatio: 0.6, bagFullSkipSources: ["stage_drop", "boss_first", "boss_repeat"] });
      const [item] = await db.select().from(contentItems).where(eq(contentItems.slug, "refine_essence"));
      expect(item).toMatchObject({ displayName: "炼器精粹", kind: "material", quality: "orange", stackable: true, iconKey: "refine_essence" });
      // 后台已经改过的精粹规则不覆盖
      await db.update(contentGlobals).set({ enhance: { ...old, essence: { ...STARTING_ESSENCE_RULES, refundPerLevel: 5 } } as never });
      for (const statement of statements()) {
        await db.execute(sql.raw(statement));
      }
      expect(enhanceRulesFromInput((await db.select().from(contentGlobals))[0]!.enhance).essence?.refundPerLevel).toBe(5);
    });
  });
});
