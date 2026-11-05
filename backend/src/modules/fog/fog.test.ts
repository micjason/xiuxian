/**
 * 迷雾秘境 P0：移动扣点、阻挡、开箱、开战、回图进度。
 */
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentRealms, playerFogRuns, playerItems, playerStates } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { DEFAULT_FOG } from "./config.js";
import { battleFog, interactFog, moveFog, readFogState } from "./actions.js";

async function seedWorld(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
  await db.insert(contentRealms).values({
    slug: "1",
    displayName: "凡人",
    majorName: "炼气",
    majorKey: "qi",
    sortOrder: 0,
    nextRealmSlug: null,
    baseAttack: 20,
    baseDefense: 5,
    baseHp: 200,
    baseSpeed: 10,
    baseInterval: 1.2,
    gainPerTick: 1,
  });
  await db.insert(contentGlobals).values({
    id: 1,
    startingRealmSlug: "1",
    offlineCapSeconds: 3600,
    bagCapacity: 40,
    fog: DEFAULT_FOG,
    powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
    combat: {
      minInterval: 0.5,
      defenseConstant: 1,
      recommendedPowerMargin: 1.05,
      challengeCooldownSeconds: 0,
      timeLimitSeconds: 30,
      speedBase: 100,
    },
  });
  await db.insert(contentItems).values([
    { slug: "herb_lingcao", displayName: "灵草", kind: "material", quality: "green", stackable: true },
    { slug: "herb_qingxin", displayName: "清心草", kind: "material", quality: "blue", stackable: true },
  ] as never);
}

describe("fog p0 问心谷", () => {
  it("spawns at (3,10), reveals neighbors, move costs travel, 0 blocks with 明日再来", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-11-05T12:00:00+08:00");
      const player = await registerPlayer(db, { username: "fogwalker", password: "correct-horse", now });
      const world = (await loadCurrentWorld(db))!;
      const first = await withTransaction(db, (tx) => readFogState(tx, world, player.playerId, undefined, now));
      expect(first.fog.mapId).toBe("fog_wenxin_valley");
      expect(first.fog.pos).toEqual({ x: 3, y: 10 });
      expect(first.fog.travelPoints).toBe(20);
      expect(first.fog.revealed).toContain("3,10");
      expect(first.fog.revealed).toContain("3,9");
      expect(first.fog.collect.chestsTotal).toBe(3);
      expect(first.fog.collect.monstersTotal).toBe(3);

      const moved = await withTransaction(db, (tx) => moveFog(tx, world, player.playerId, "fog_wenxin_valley", { x: 3, y: 9 }, now));
      expect(moved.fog.pos).toEqual({ x: 3, y: 9 });
      expect(moved.fog.travelPoints).toBe(19);

      await withTransaction(db, async (tx) => {
        await tx
          .update(playerFogRuns)
          .set({ travelPoints: 0 })
          .where(eq(playerFogRuns.playerId, player.playerId));
      });
      await expect(
        withTransaction(db, (tx) => moveFog(tx, world, player.playerId, "fog_wenxin_valley", { x: 3, y: 8 }, now)),
      ).rejects.toMatchObject({ code: "FOG_TRAVEL_EMPTY", message: expect.stringContaining("明日再来") });
    });
  });

  it("opens c_near for herbs and marks opened", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-11-05T12:00:00+08:00");
      const player = await registerPlayer(db, { username: "fogchest", password: "correct-horse", now });
      const world = (await loadCurrentWorld(db))!;
      await withTransaction(db, (tx) => readFogState(tx, world, player.playerId, "fog_wenxin_valley", now));
      // teleport beside chest
      await db
        .update(playerFogRuns)
        .set({ posC: 4, posR: 9, revealed: ["4,9", "3,9", "4,8", "4,10", "5,9"], travelPoints: 20 })
        .where(eq(playerFogRuns.playerId, player.playerId));
      const opened = await withTransaction(db, (tx) =>
        interactFog(tx, world, player.playerId, "fog_wenxin_valley", { objectId: "c_near" }, now),
      );
      expect(opened.kind).toBe("chest");
      expect(opened.gained?.some((g) => g.itemSlug === "herb_lingcao" && g.quantity === 3)).toBe(true);
      expect(opened.fog.collect.chestsOpened).toBe(1);
      const items = await db.select().from(playerItems).where(eq(playerItems.playerId, player.playerId));
      expect(items.some((i) => i.itemSlug === "herb_lingcao" && i.quantity >= 3)).toBe(true);
    });
  });

  it("battles m_slime and keeps fog progress", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-11-05T12:00:00+08:00");
      const player = await registerPlayer(db, { username: "fogfighter", password: "correct-horse", now });
      await db.update(playerStates).set({ cultivation: 0 }).where(eq(playerStates.playerId, player.playerId));
      const world = (await loadCurrentWorld(db))!;
      await withTransaction(db, (tx) => readFogState(tx, world, player.playerId, "fog_wenxin_valley", now));
      await db
        .update(playerFogRuns)
        .set({ posC: 2, posR: 8, revealed: ["2,8", "2,7", "2,9", "1,8", "3,8"], travelPoints: 15 })
        .where(eq(playerFogRuns.playerId, player.playerId));
      const fight = await withTransaction(db, (tx) =>
        battleFog(tx, world, player.playerId, "fog_wenxin_valley", { objectId: "m_slime" }, now),
      );
      expect(fight.log.length).toBeGreaterThan(0);
      expect(fight.fog.pos).toEqual({ x: 2, y: 8 });
      if (fight.win) {
        expect(fight.fog.collect.monstersDefeated).toBe(1);
        expect(fight.fog.objects.find((o) => o.id === "m_slime")?.defeated).toBe(true);
      }
      const again = await withTransaction(db, (tx) => readFogState(tx, world, player.playerId, "fog_wenxin_valley", now));
      expect(again.fog.pos).toEqual({ x: 2, y: 8 });
      expect(again.fog.travelPoints).toBe(15);
    });
  });
});
