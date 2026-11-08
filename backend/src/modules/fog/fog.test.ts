/**
 * 迷雾秘境 P0：移动扣点、阻挡、开箱、开战、回图进度。
 */
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import {
  contentGlobals,
  contentItems,
  contentRealms,
  contentSkills,
  playerFogRuns,
  playerItems,
  playerStates,
} from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { DEFAULT_FOG, isBlocked } from "./config.js";
import { startCombat } from "../combat/sessions.js";
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
    {
      slug: "herb_lingcao",
      displayName: "灵草",
      kind: "material",
      quality: "green",
      stackable: true,
    },
    {
      slug: "herb_qingxin",
      displayName: "清心草",
      kind: "material",
      quality: "blue",
      stackable: true,
    },
  ] as never);
}

describe("fog p0 问心谷", () => {
  it("spawns at (3,10), reveals neighbors, move costs travel, 0 blocks with 明日再来", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-11-05T12:00:00+08:00");
      const player = await registerPlayer(db, {
        username: "fogwalker",
        password: "correct-horse",
        now,
      });
      const world = (await loadCurrentWorld(db))!;
      const first = await withTransaction(db, (tx) =>
        readFogState(tx, world, player.playerId, undefined, now),
      );
      expect(first.fog.mapId).toBe("fog_wenxin_valley");
      expect(first.fog.pos).toEqual({ x: 3, y: 10 });
      expect(first.fog.travelPoints).toBe(200);
      expect(first.fog.revealed).toContain("3,10");
      expect(first.fog.revealed).toContain("3,9");
      expect(first.fog.collect.chestsTotal).toBe(3);
      expect(first.fog.collect.monstersTotal).toBe(2);

      const moved = await withTransaction(db, (tx) =>
        moveFog(
          tx,
          world,
          player.playerId,
          "fog_wenxin_valley",
          { x: 3, y: 9 },
          now,
        ),
      );
      expect(moved.fog.pos).toEqual({ x: 3, y: 9 });
      expect(moved.fog.travelPoints).toBe(199);

      await withTransaction(db, async (tx) => {
        await tx
          .update(playerFogRuns)
          .set({ travelPoints: 0 })
          .where(eq(playerFogRuns.playerId, player.playerId));
      });
      await expect(
        withTransaction(db, (tx) =>
          moveFog(
            tx,
            world,
            player.playerId,
            "fog_wenxin_valley",
            { x: 3, y: 8 },
            now,
          ),
        ),
      ).rejects.toMatchObject({
        code: "FOG_TRAVEL_EMPTY",
        message: expect.stringContaining("明日再来"),
      });
    });
  });

  it("opens c_near for herbs and marks opened", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-11-05T12:00:00+08:00");
      const player = await registerPlayer(db, {
        username: "fogchest",
        password: "correct-horse",
        now,
      });
      const world = (await loadCurrentWorld(db))!;
      await withTransaction(db, (tx) =>
        readFogState(tx, world, player.playerId, "fog_wenxin_valley", now),
      );
      // teleport beside chest
      await db
        .update(playerFogRuns)
        .set({
          posC: 4,
          posR: 9,
          revealed: ["4,9", "3,9", "4,8", "4,10", "5,9"],
          travelPoints: 20,
        })
        .where(eq(playerFogRuns.playerId, player.playerId));
      const opened = await withTransaction(db, (tx) =>
        interactFog(
          tx,
          world,
          player.playerId,
          "fog_wenxin_valley",
          { objectId: "c_near" },
          now,
        ),
      );
      expect(opened.kind).toBe("chest");
      expect(
        opened.gained?.some(
          (g) => g.itemSlug === "herb_lingcao" && g.quantity === 3,
        ),
      ).toBe(true);
      expect(opened.fog.collect.chestsOpened).toBe(1);
      const items = await db
        .select()
        .from(playerItems)
        .where(eq(playerItems.playerId, player.playerId));
      expect(
        items.some((i) => i.itemSlug === "herb_lingcao" && i.quantity >= 3),
      ).toBe(true);
      await expect(
        withTransaction(db, (tx) =>
          interactFog(
            tx,
            world,
            player.playerId,
            "fog_wenxin_valley",
            { objectId: "c_near" },
            now,
          ),
        ),
      ).rejects.toMatchObject({ code: "FOG_OBJECT_GONE" });
    });
  });

  it("battles m_slime and keeps fog progress", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-11-05T12:00:00+08:00");
      const player = await registerPlayer(db, {
        username: "fogfighter",
        password: "correct-horse",
        now,
      });
      await db
        .update(playerStates)
        .set({ cultivation: 0 })
        .where(eq(playerStates.playerId, player.playerId));
      const world = (await loadCurrentWorld(db))!;
      await withTransaction(db, (tx) =>
        readFogState(tx, world, player.playerId, "fog_wenxin_valley", now),
      );
      await db
        .update(playerFogRuns)
        .set({
          posC: 2,
          posR: 8,
          revealed: ["2,8", "2,7", "2,9", "1,8", "3,8"],
          travelPoints: 15,
        })
        .where(eq(playerFogRuns.playerId, player.playerId));
      const fight = await withTransaction(db, (tx) =>
        battleFog(
          tx,
          world,
          player.playerId,
          "fog_wenxin_valley",
          { objectId: "m_slime" },
          now,
        ),
      );
      expect(fight.log.length).toBeGreaterThan(0);
      expect(fight.fog.pos).toEqual({ x: 2, y: 8 });
      if (fight.win) {
        expect(fight.fog.collect.monstersDefeated).toBe(1);
        expect(
          fight.fog.objects.find((o) => o.id === "m_slime")?.defeated,
        ).toBe(true);
      }
      const again = await withTransaction(db, (tx) =>
        readFogState(tx, world, player.playerId, "fog_wenxin_valley", now),
      );
      expect(again.fog.pos).toEqual({ x: 2, y: 8 });
      expect(again.fog.travelPoints).toBe(15);
    });
  });
});

describe("fog exit closure", () => {
  it("blocks incomplete exit via battle and combat/start; full exit preview, loss and win are authoritative", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-11-08T14:00:00+08:00");
      const player = await registerPlayer(db, {
        username: "exitwalker",
        password: "local-fixture-only",
        now,
      });
      const world = (await loadCurrentWorld(db))!;
      const id = player.playerId;
      const mapId = "fog_wenxin_valley";
      const read = () =>
        withTransaction(db, (tx) => readFogState(tx, world, id, mapId, now));
      const first = await read();
      expect(first.fog.collect.monstersTotal).toBe(2);
      expect(first.fog.objects.find((o) => o.id === "m_guard")).toMatchObject({
        kind: "exit",
        passed: false,
      });
      await db
        .update(playerFogRuns)
        .set({ posC: 4, posR: 2, revealed: ["4,2", "4,1"] })
        .where(eq(playerFogRuns.playerId, id));
      await expect(
        withTransaction(db, (tx) =>
          battleFog(tx, world, id, mapId, { objectId: "m_guard" }, now),
        ),
      ).rejects.toMatchObject({ message: expect.stringContaining("探索") });
      await expect(
        withTransaction(db, (tx) =>
          startCombat(
            tx,
            world,
            id,
            { source: "fog", mapId, objectId: "m_guard" },
            now,
            () => 0,
          ),
        ),
      ).rejects.toMatchObject({ message: expect.stringContaining("探索") });
      const all: string[] = [];
      const map = DEFAULT_FOG.maps[0]!;
      for (let y = 0; y < map.rows; y++)
        for (let x = 0; x < map.cols; x++)
          if (!isBlocked(map, x, y)) all.push(`${x},${y}`);
      await db
        .update(playerFogRuns)
        .set({ revealed: all })
        .where(eq(playerFogRuns.playerId, id));
      const preview = await withTransaction(db, (tx) =>
        battleFog(tx, world, id, mapId, { objectId: "m_guard" }, now, {
          preview: true,
        }),
      );
      expect(preview.fog.exploreFull).toBe(true);
      expect(preview.fog.objects.find((o) => o.id === "m_guard")?.passed).toBe(
        false,
      );
      const loss = await withTransaction(db, (tx) =>
        battleFog(tx, world, id, mapId, { objectId: "m_guard" }, now, {
          resolvedBattle: {
            win: false,
            reason: "defeated",
            durationSeconds: 1,
            log: [],
          },
        }),
      );
      expect(loss.fog.objects.find((o) => o.id === "m_guard")?.passed).toBe(
        false,
      );
      expect(loss.gained).toEqual([]);
      const win = await withTransaction(db, (tx) =>
        battleFog(tx, world, id, mapId, { objectId: "m_guard" }, now, {
          resolvedBattle: {
            win: true,
            reason: "win",
            durationSeconds: 1,
            log: [],
          },
        }),
      );
      expect(win.fog.objects.find((o) => o.id === "m_guard")?.passed).toBe(
        true,
      );
      expect(win.gained.length).toBeGreaterThan(0);
      expect(win.fog.pos).toEqual({ x: 4, y: 2 });
      expect(win.fog.collect.monstersDefeated).toBe(0);
      await expect(
        withTransaction(db, (tx) =>
          battleFog(tx, world, id, mapId, { objectId: "m_guard" }, now),
        ),
      ).rejects.toMatchObject({ code: "FOG_OBJECT_GONE" });
    });
  });
  it("refills legacy run budget once, retaining spent points and explored progress", async () => {
    await withDb(async (db) => {
      await seedWorld(db);
      const now = new Date("2026-11-08T14:00:00+08:00");
      const p = await registerPlayer(db, {
        username: "legacyfog",
        password: "local-fixture-only",
        now,
      });
      const world = (await loadCurrentWorld(db))!;
      await db
        .insert(playerFogRuns)
        .values({
          playerId: p.playerId,
          mapId: "fog_wenxin_valley",
          posC: 3,
          posR: 9,
          travelPoints: 12,
          travelDay: "2026-11-08",
          revealed: ["3,9"],
          objects: { c_near: { opened: true } },
        });
      const read = () =>
        withTransaction(db, (tx) =>
          readFogState(tx, world, p.playerId, undefined, now),
        );
      expect((await read()).fog.travelPoints).toBe(192);
      const second = (await read()).fog;
      expect(second.travelPoints).toBe(192);
      expect(second.collect.chestsOpened).toBe(1);
    });
  });
});

it("full exploration can start an authoritative exit session", async () => {
  await withDb(async (db) => {
    await seedWorld(db);
    const now = new Date("2026-11-08T14:00:00+08:00");
    const p = await registerPlayer(db, {
      username: "exitstart",
      password: "local-fixture-only",
      now,
    });
    const world = (await loadCurrentWorld(db))!;
    const map = DEFAULT_FOG.maps[0]!;
    const all: string[] = [];
    for (let y = 0; y < map.rows; y++)
      for (let x = 0; x < map.cols; x++) all.push(`${x},${y}`);
    await db
      .insert(playerFogRuns)
      .values({
        playerId: p.playerId,
        mapId: map.id,
        posC: 4,
        posR: 2,
        travelPoints: 100,
        travelDay: "2026-11-08",
        revealed: all,
        objects: {},
      });
    const session = await withTransaction(db, (tx) =>
      startCombat(
        tx,
        world,
        p.playerId,
        { source: "fog", mapId: map.id, objectId: "m_guard" },
        now,
        () => 0,
      ),
    );
    expect(session.combatId).toBeTruthy();
    expect(session.source).toBe("fog");
    expect(session.playback).toMatchObject({ monster: { id: "m_guard" } });
  });
});
it("event exposes battle and leave choices, leave is persisted", async () => {
  await withDb(async (db) => {
    await seedWorld(db);
    const now = new Date("2026-11-08T14:00:00+08:00");
    const p = await registerPlayer(db, {
      username: "fogevent",
      password: "local-fixture-only",
      now,
    });
    const world = (await loadCurrentWorld(db))!;
    await db
      .insert(playerFogRuns)
      .values({
        playerId: p.playerId,
        mapId: "fog_wenxin_valley",
        posC: 3,
        posR: 5,
        travelPoints: 100,
        travelDay: "2026-11-08",
        revealed: ["3,4"],
        objects: {},
      });
    const act = (optionId?: string) =>
      withTransaction(db, (tx) =>
        interactFog(
          tx,
          world,
          p.playerId,
          "fog_wenxin_valley",
          { objectId: "e_herb", optionId },
          now,
        ),
      );
    expect((await act()).kind).toBe("event_prompt");
    expect((await act("A")).kind).toBe("event_battle");
    expect((await act("B")).kind).toBe("event_leave");
    await expect(act("B")).rejects.toMatchObject({ code: "FOG_OBJECT_GONE" });
  });
});

it("high chest grants an actual inventory skill book exactly once", async () => {
  await withDb(async (db) => {
    await seedWorld(db);
    await db
      .insert(contentSkills)
      .values({ slug: "skill_tuna", displayName: "吐纳" });
    const now = new Date("2026-11-08T14:00:00+08:00");
    const p = await registerPlayer(db, {
      username: "fogbook",
      password: "local-fixture-only",
      now,
    });
    const world = (await loadCurrentWorld(db))!;
    await db
      .insert(playerFogRuns)
      .values({
        playerId: p.playerId,
        mapId: "fog_wenxin_valley",
        posC: 6,
        posR: 4,
        travelPoints: 100,
        travelDay: "2026-11-08",
        revealed: ["6,3"],
        objects: {},
      });
    const open = () =>
      withTransaction(db, (tx) =>
        interactFog(
          tx,
          world,
          p.playerId,
          "fog_wenxin_valley",
          { objectId: "c_high" },
          now,
        ),
      );
    const got = await open();
    expect(got.gained?.some((g) => g.itemSlug === "book_fog_skill_tuna")).toBe(
      true,
    );
    const items = await db
      .select()
      .from(playerItems)
      .where(eq(playerItems.playerId, p.playerId));
    expect(
      items.some(
        (i) => i.itemSlug === "book_fog_skill_tuna" && i.quantity === 1,
      ),
    ).toBe(true);
    await expect(open()).rejects.toMatchObject({ code: "FOG_OBJECT_GONE" });
  });
});
