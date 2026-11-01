/**
 * 阵法日游 complete：通 / 未通 / 日清重复。
 */
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentRealms, playerItems } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { AppError } from "../../shared/errors.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { DEFAULT_ARRAY_DAILY, DEFAULT_DONGFU } from "./config.js";
import { completeArrayDaily, readDongfuState } from "./actions.js";
import { pickPuzzleForDay, shanghaiDayKey } from "./array-daily.js";

const VEIN_01 = DEFAULT_ARRAY_DAILY.puzzles.find((p) => p.puzzleId === "vein_01")!;
const VEIN_01_SOLUTION = [
  { r: 0, c: 1, rot: 1 },
  { r: 0, c: 2, rot: 2 },
  { r: 1, c: 0, rot: 1 },
  { r: 1, c: 1, rot: 1 },
  { r: 1, c: 2, rot: 3 },
  { r: 2, c: 0, rot: 0 },
  { r: 2, c: 1, rot: 1 },
];

const ITEMS = [
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
  { slug: "wood_lingmu", displayName: "灵木", kind: "material", quality: "green", stackable: true },
  { slug: "array_shard", displayName: "阵纹残片", kind: "material", quality: "blue", stackable: true },
] as const;

async function seedWorld(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
  const dongfu = {
    ...DEFAULT_DONGFU,
    arrayDaily: {
      ...DEFAULT_ARRAY_DAILY,
      puzzles: [VEIN_01],
    },
  };
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
  await db.insert(contentItems).values([...ITEMS] as never);
}

describe("dongfu array daily complete", () => {
  const now = new Date("2026-10-31T16:30:00.000Z"); // Shanghai 2026-11-01
  const dayKey = shanghaiDayKey(now);

  it("success grants xp + array_shard and marks clearedToday", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const player = await registerPlayer(db, { username: "array_ok", password: "correct-horse", now });
      const world = await loadCurrentWorld(db);
      expect(world).toBeTruthy();
      const opened = await withTransaction(db, (tx) => readDongfuState(tx, world!, player.playerId, now));
      expect(opened.arrayDaily.enabled).toBe(true);
      expect(opened.arrayDaily.clearedToday).toBe(false);
      expect(opened.arrayDaily.dayKey).toBe(dayKey);
      expect(opened.arrayDaily.puzzle?.puzzleId).toBe("vein_01");
      expect(pickPuzzleForDay([VEIN_01], dayKey).puzzleId).toBe("vein_01");

      const result = await withTransaction(db, (tx) =>
        completeArrayDaily(
          tx,
          world!,
          player.playerId,
          { puzzleId: "vein_01", dayKey, rots: VEIN_01_SOLUTION },
          now,
        ),
      );
      expect(result.arrayXpGained).toBe(20);
      expect(result.gained).toEqual([{ itemSlug: "array_shard", qty: 5 }]);
      expect(result.dongfu.arrayDaily.clearedToday).toBe(true);
      expect(result.dongfu.arrayDaily.arrayXp).toBe(20);
      expect(result.dongfu.arrayDaily.puzzle).toBeUndefined();

      const bags = await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId));
      const shard = bags.find((row) => row.itemSlug === "array_shard");
      expect(shard?.quantity).toBe(5);
    });
  });

  it("NOT_CONNECTED when pipes do not link", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const player = await registerPlayer(db, { username: "array_bad", password: "correct-horse", now });
      const world = await loadCurrentWorld(db);
      const bad = VEIN_01.tiles.map((t) => ({ r: t.r, c: t.c, rot: t.rot }));
      await expect(
        withTransaction(db, (tx) =>
          completeArrayDaily(tx, world!, player.playerId, { puzzleId: "vein_01", dayKey, rots: bad }, now),
        ),
      ).rejects.toMatchObject({ code: "NOT_CONNECTED", message: "灵脉未通，再试试" } satisfies Partial<AppError>);
    });
  });

  it("ALREADY_CLEARED on second success same day", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const player = await registerPlayer(db, { username: "array_twice", password: "correct-horse", now });
      const world = await loadCurrentWorld(db);
      await withTransaction(db, (tx) =>
        completeArrayDaily(
          tx,
          world!,
          player.playerId,
          { puzzleId: "vein_01", dayKey, rots: VEIN_01_SOLUTION },
          now,
        ),
      );
      await expect(
        withTransaction(db, (tx) =>
          completeArrayDaily(
            tx,
            world!,
            player.playerId,
            { puzzleId: "vein_01", dayKey, rots: VEIN_01_SOLUTION },
            now,
          ),
        ),
      ).rejects.toMatchObject({ code: "ALREADY_CLEARED", message: "今日灵脉已接引" } satisfies Partial<AppError>);
    });
  });
});
