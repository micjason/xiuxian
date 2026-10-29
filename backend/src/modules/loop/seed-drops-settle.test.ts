/**
 * 种子掉落入账：在线 settleWaves + 离线 settleOfflineSeedDrops。
 */
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentStages, playerItems, playerStates, players } from "../../db/schema.js";
import { applyPrototypeV12 } from "../content/prototype-v12.js";
import { loadDraftSnapshot } from "../content/snapshot.js";
import { DEFAULT_SEED_DROPS } from "../content/seed-drops.js";
import { withDb } from "../../test/db.js";
import { settleOfflineSeedDrops, settleWaves, setWaveRandom } from "./waves.js";
import { readGameRules } from "../content/rules.js";

const start = new Date("2026-10-29T04:00:00.000Z");

describe("seed drops in wave settle", () => {
  it("grants seeds online per kill from global defaults, and respects empty per-stage override", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      // migration stubs may not be applied in unit db — insert seeds
      for (const row of [
        { slug: "seed_lingcao", displayName: "灵草种子", kind: "material", quality: "green", stackable: true },
        { slug: "seed_qingxin", displayName: "清心草种子", kind: "material", quality: "blue", stackable: true },
      ]) {
        await db.insert(contentItems).values(row).onConflictDoNothing();
      }
      const [globals] = await db.select().from(contentGlobals);
      await db.update(contentGlobals).set({
        tuning: {
          ...(globals!.tuning as object),
          monsterDropChanceBp: 0,
          seedDrops: DEFAULT_SEED_DROPS.map((r) => ({ ...r, chanceBp: 10000 })),
        } as never,
      });
      // 清掉指定掉落，避免本测试走到装备发放
      await db.update(contentStages).set({ designatedDrops: [], monsterDrop: { chanceBp: 0, qualityWeights: { white: 1, green: 0, blue: 0, purple: 0, orange: 0 } } });
      // ensure column
      try {
        await db.execute(await (async () => {
          const { sql } = await import("drizzle-orm");
          return sql.raw(`ALTER TABLE "content_stages" ADD COLUMN IF NOT EXISTS "seed_drops" jsonb`);
        })());
      } catch { /* ignore */ }

      const world = await loadDraftSnapshot(db);
      const stage = world.stages.find((row) => row.slug === "lianqi_1");
      expect(stage).toBeTruthy();
      expect(stage!.seedDrops?.some((row) => row.itemSlug === "seed_lingcao")).toBe(true);

      const [player] = await db.insert(players).values({ username: "seed1", usernameLower: "seed1", passwordHash: "x" }).returning();
      await db.insert(playerStates).values({ playerId: player!.id, cultivation: 0, spiritStones: 0, realmSlug: "lianqi_1", lastSettledAt: start });

      setWaveRandom(() => 0); // always hit
      const tx = db as never;
      const rules = readGameRules(world);
      const result = await settleWaves(tx, world as never, player!.id, {
        rules,
        stage: stage as never,
        stats: { attack: 100, defense: 50, hp: 500, interval: 1 },
        progress: 0,
        deathsInRow: 0,
        consumedSeconds: 30,
        capacity: 50,
        now: start,
      });
      const seedDrops = result.drops.filter((row) => row.seed);
      expect(seedDrops.length).toBeGreaterThan(0);
      expect(seedDrops.every((row) => row.itemSlug.startsWith("seed_"))).toBe(true);
      const bag = await db.select().from(playerItems).where(eq(playerItems.playerId, player!.id));
      expect(bag.some((row) => row.itemSlug === "seed_lingcao" && row.isStack)).toBe(true);

      // empty override → no seeds
      await db.update(contentStages).set({ seedDrops: [] }).where(eq(contentStages.slug, "lianqi_1"));
      const world2 = await loadDraftSnapshot(db);
      const stage2 = world2.stages.find((row) => row.slug === "lianqi_1")!;
      expect(stage2.seedDrops).toEqual([]);
      await db.delete(playerItems).where(eq(playerItems.playerId, player!.id));
      const empty = await settleWaves(tx, world2 as never, player!.id, {
        rules,
        stage: stage2 as never,
        stats: { attack: 100, defense: 50, hp: 500, interval: 1 },
        progress: 0,
        deathsInRow: 0,
        consumedSeconds: 30,
        capacity: 50,
        now: start,
      });
      expect(empty.drops.filter((row) => row.seed)).toEqual([]);
    });
  });

  it("offline helper also grants seeds from estimated kills", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      for (const row of [
        { slug: "seed_lingcao", displayName: "灵草种子", kind: "material", quality: "green", stackable: true },
        { slug: "seed_qingxin", displayName: "清心草种子", kind: "material", quality: "blue", stackable: true },
      ]) {
        await db.insert(contentItems).values(row).onConflictDoNothing();
      }
      const [globals] = await db.select().from(contentGlobals);
      await db.update(contentGlobals).set({
        tuning: { ...(globals!.tuning as object), seedDrops: [{ itemSlug: "seed_lingcao", chanceBp: 10000, minCount: 1, maxCount: 1 }] } as never,
      });
      try {
        const { sql } = await import("drizzle-orm");
        await db.execute(sql.raw(`ALTER TABLE "content_stages" ADD COLUMN IF NOT EXISTS "seed_drops" jsonb`));
      } catch { /* ignore */ }

      const world = await loadDraftSnapshot(db);
      const stage = world.stages.find((row) => row.slug === "lianqi_1")!;
      const [player] = await db.insert(players).values({ username: "seed2", usernameLower: "seed2", passwordHash: "x" }).returning();
      await db.insert(playerStates).values({ playerId: player!.id, cultivation: 0, spiritStones: 0, realmSlug: "lianqi_1", lastSettledAt: start });
      setWaveRandom(() => 0);
      const drops = await settleOfflineSeedDrops(db as never, world as never, player!.id, {
        rules: readGameRules(world),
        stage: stage as never,
        stats: { attack: 100, defense: 50, hp: 500, interval: 1 },
        countedSeconds: 120,
        capacity: 50,
        now: start,
      });
      expect(drops.some((row) => row.seed && row.itemSlug === "seed_lingcao")).toBe(true);
      const bag = await db.select().from(playerItems).where(eq(playerItems.playerId, player!.id));
      expect(bag.find((row) => row.itemSlug === "seed_lingcao")?.quantity ?? 0).toBeGreaterThan(0);
    });
  });
});
