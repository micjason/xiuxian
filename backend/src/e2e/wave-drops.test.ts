/* eslint-disable @typescript-eslint/no-explicit-any */
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { equipmentGrants, playerItems, playerStageProgress, playerStates, players } from "../db/schema.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z");
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

/** 可控的随机：按 randomInt 的上限区分是哪一次掷骰（10000 = 掉不掉，6 = 部位，其余 = 品质）。 */
function dice() {
  const control = { chance: 0, slot: 0, quality: 0, calls: [] as string[] };
  const randomInt = (_min: number, max: number) => {
    if (max === 10000) {
      control.calls.push("chance");
      return control.chance;
    }
    if (max === 6) {
      control.calls.push("slot");
      return control.slot;
    }
    control.calls.push("quality");
    return control.quality;
  };
  return { control, randomInt };
}

async function boot(db: TestDb, name: string) {
  await applyPrototypeV12(db);
  const { control, randomInt } = dice();
  let clock = start;
  const app = await buildApp(db, () => clock, { randomInt });
  const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: name, password: "correct-horse" } });
  const headers = { authorization: `Bearer ${registered.json().token as string}` };
  const [player] = await db.select().from(players).where(eq(players.usernameLower, name));
  const jump = async (seconds: number) => {
    clock = new Date(start.getTime() + seconds * 1000);
    return (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json();
  };
  // 前台在线：每 5 秒一次轮询走到目标时间，把每次的击杀/掉落合并起来
  let elapsed = 0;
  const state = async (seconds: number) => {
    const merged = { kills: 0, drops: [] as Record<string, unknown>[], bagFull: false };
    let last: Record<string, any> = { lastSettle: {} };
    while (elapsed < seconds) {
      elapsed = Math.min(seconds, elapsed + 5);
      last = await jump(elapsed);
      merged.kills += last.lastSettle.kills;
      merged.drops.push(...last.lastSettle.drops);
      merged.bagFull ||= last.lastSettle.bagFull;
    }
    return { ...last, lastSettle: { ...last.lastSettle, ...merged } } as Record<string, any>;
  };
  const bag = async () => (await db.select().from(playerItems).where(eq(playerItems.playerId, player!.id))).filter((row) => !row.equippedSlot);
  const fill = async (slug: string, count: number, enhanceLevel = 0) => {
    for (let index = 0; index < count; index += 1) {
      await db.insert(playerItems).values({ playerId: player!.id, itemSlug: slug, isStack: false, quantity: 1, enhanceLevel, acquiredAt: new Date(start.getTime() - 1000 * (count - index)), source: "test" });
    }
  };
  return { app, control, state, jump, bag, fill, playerId: player!.id };
}

describe("monster kill drops (5% per kill, regional quality weights, equal 6-slot pick)", () => {
  it("every kill rolls the 5% chance; a hit drops one gear piece of the stage's tier with the rolled quality and slot", async () => {
    await withDb(async (db) => {
      const { app, control, state, bag } = await boot(db, "drop_a");
      control.chance = 499; // < 500 → 掉
      control.quality = 70000; // 70/25/5/0 ×1000：70000 起是绿
      control.slot = 2; // 头冠
      const result = await state(30);
      expect(result.lastSettle.kills).toBeGreaterThan(0);
      expect(result.lastSettle.drops).toHaveLength(result.lastSettle.kills);
      expect(result.lastSettle.drops[0]).toMatchObject({ itemSlug: "gear_major1_helmet_green", quality: "green", dropped: false, decomposed: false });
      const rows = await bag();
      expect(rows).toHaveLength(result.lastSettle.kills);
      expect(rows.every((row) => row.itemSlug === "gear_major1_helmet_green" && row.source === "stage_drop")).toBe(true);
      // 每次击杀：1 次“掉不掉”，掉了再掷品质和部位
      expect(control.calls.slice(0, 3)).toEqual(["chance", "quality", "slot"]);
      await app.close();
    });
  });

  it("chance roll at 500 (5.00 %) does not drop", async () => {
    await withDb(async (db) => {
      const { app, control, state, bag } = await boot(db, "drop_b");
      control.chance = 500;
      const result = await state(30);
      expect(result.lastSettle.kills).toBeGreaterThan(0);
      expect(result.lastSettle.drops).toEqual([]);
      expect(await bag()).toHaveLength(0);
      await app.close();
    });
  });

  it("offline gaps never drop gear, even with a guaranteed roll", async () => {
    await withDb(async (db) => {
      const { app, control, jump, bag } = await boot(db, "drop_c");
      control.chance = 0;
      const result = await jump(3600);
      expect(result.lastSettle).toMatchObject({ online: false, kills: 0 });
      expect(await bag()).toHaveLength(0);
      await app.close();
    });
  });

  it("the drop tier follows the stage: 筑基 stage drops major4 gear", async () => {
    await withDb(async (db) => {
      const { app, control, state, playerId } = await boot(db, "drop_d");
      await db.update(playerStates).set({ realmSlug: "zhuji_1" }).where(eq(playerStates.playerId, playerId));
      // 第三批：要先打赢炼气三关的首领才解锁筑基一关
      for (const stageSlug of ["lianqi_1", "lianqi_2", "lianqi_3"]) {
        await db.insert(playerStageProgress).values({ playerId, stageSlug, unlockedAt: start, firstClearedAt: start, clearCount: 1 }).onConflictDoUpdate({ target: [playerStageProgress.playerId, playerStageProgress.stageSlug], set: { firstClearedAt: start, clearCount: 1 } });
      }
      control.chance = 0;
      control.quality = 99999; // 50/35/13/2：最后一档是紫
      control.slot = 5;
      const result = await state(30);
      expect(result.wave.stageSlug).toBe("zhuji_1");
      expect(result.lastSettle.drops[0]).toMatchObject({ itemSlug: "gear_major4_accessory_purple", quality: "purple" });
      await app.close();
    });
  });

  it("full bag (第五批): no gear drops at all, whatever the quality — nothing is decomposed, no grant is written, bagFull is reported; freeing a slot lets drops resume", async () => {
    await withDb(async (db) => {
      const { app, control, state, bag, fill, playerId } = await boot(db, "drop_e");
      await fill("gear_major1_weapon_white", 20);
      control.chance = 0;
      for (const quality of [0, 95000]) {
        control.quality = quality; // 白 / 蓝
        const result = await state(quality === 0 ? 30 : 60);
        expect(result.lastSettle.kills).toBeGreaterThan(0);
        expect(result.lastSettle.drops.length).toBeGreaterThan(0);
        expect(result.lastSettle.drops.every((drop: { decomposed: boolean; dropped: boolean; freed: unknown[] }) => drop.dropped && !drop.decomposed && drop.freed.length === 0)).toBe(true);
        expect(result.lastSettle.bagFull).toBe(true);
        expect(result.enhanceExp).toBe(0);
        expect(result.bagUsed).toBe(20);
        expect(await bag()).toHaveLength(20);
      }
      expect(await db.select().from(equipmentGrants).where(eq(equipmentGrants.playerId, playerId))).toEqual([]);
      // 玩家自己分解一件 → 有空格了，下一件照常掉
      const [one] = await bag();
      await db.delete(playerItems).where(eq(playerItems.id, one!.id));
      const resumed = await state(90);
      expect(resumed.lastSettle.drops.some((drop: { dropped: boolean }) => !drop.dropped)).toBe(true);
      expect(await bag()).toHaveLength(20);
      await app.close();
    });
  });

  it("a full bag drops nothing and says so, with or without the old auto-decompose switch; enhanced gear is never touched", async () => {
    await withDb(async (db) => {
      const { app, control, state, bag, fill, playerId } = await boot(db, "drop_g");
      await fill("gear_major1_weapon_white", 20, 1); // 全部强化过
      control.chance = 0;
      control.quality = 95000; // 蓝
      const protectedRun = await state(10);
      expect(protectedRun.lastSettle.kills).toBeGreaterThan(0);
      expect(protectedRun.lastSettle.bagFull).toBe(true);
      expect((await bag()).every((row) => row.enhanceLevel === 1)).toBe(true);
      await db.delete(playerItems);
      await fill("gear_major1_weapon_white", 20);
      await db.update(playerStates).set({ autoDecompose: false }).where(eq(playerStates.playerId, playerId));
      control.quality = 0; // 白：开关关闭时也不能分解
      const off = await state(30);
      expect(off.lastSettle.bagFull).toBe(true);
      expect(off.lastSettle.drops.every((drop: { dropped: boolean; decomposed: boolean }) => drop.dropped && !drop.decomposed)).toBe(true);
      expect(await bag()).toHaveLength(20);
      await app.close();
    });
  });
});
