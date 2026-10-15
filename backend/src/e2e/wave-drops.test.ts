import { and, eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { playerItems, playerStates, players } from "../db/schema.js";
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
    let last: Record<string, any> = {};
    while (elapsed < seconds) {
      elapsed = Math.min(seconds, elapsed + 5);
      last = await jump(elapsed);
      merged.kills += last.lastSettle.kills;
      merged.drops.push(...last.lastSettle.drops);
      merged.bagFull ||= last.lastSettle.bagFull;
    }
    return { ...last, lastSettle: { ...last.lastSettle, ...merged } };
  };
  const bag = async () => (await db.select().from(playerItems).where(eq(playerItems.playerId, player!.id))).filter((row) => !row.equippedSlot);
  const fill = async (slug: string, count: number, enhanceLevel = 0) => {
    for (let index = 0; index < count; index += 1) {
      await db.insert(playerItems).values({ playerId: player!.id, itemSlug: slug, isStack: false, quantity: 1, enhanceLevel, acquiredAt: new Date(start.getTime() - 1000 * (count - index)), source: "test" });
    }
  };
  return { app, control, state, jump, bag, fill, playerId: player!.id };
}

describe("monster kill drops (4% per kill, regional quality weights, equal 6-slot pick)", () => {
  it("every kill rolls the 4% chance; a hit drops one gear piece of the stage's tier with the rolled quality and slot", async () => {
    await withDb(async (db) => {
      const { app, control, state, bag } = await boot(db, "drop_a");
      control.chance = 399; // < 400 → 掉
      control.quality = 70000; // 70/25/5/0 ×1000：70000 起是绿
      control.slot = 2; // 头冠
      const result = await state(30);
      expect(result.lastSettle.kills).toBeGreaterThan(0);
      expect(result.lastSettle.drops).toHaveLength(result.lastSettle.kills);
      expect(result.lastSettle.drops[0]).toMatchObject({ itemSlug: "gear_major1_helmet_green", quality: "green", dropped: false, decomposed: false });
      const rows = await bag();
      expect(rows).toHaveLength(result.lastSettle.kills);
      expect(rows.every((row) => row.itemSlug === "gear_major1_helmet_green" && row.source === "wave:lianqi_1")).toBe(true);
      // 每次击杀：1 次“掉不掉”，掉了再掷品质和部位
      expect(control.calls.slice(0, 3)).toEqual(["chance", "quality", "slot"]);
      await app.close();
    });
  });

  it("chance roll at 400 (4.00 %) does not drop", async () => {
    await withDb(async (db) => {
      const { app, control, state, bag } = await boot(db, "drop_b");
      control.chance = 400;
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
      control.chance = 0;
      control.quality = 99999; // 50/35/13/2：最后一档是紫
      control.slot = 5;
      const result = await state(30);
      expect(result.wave.stageSlug).toBe("zhuji_1");
      expect(result.lastSettle.drops[0]).toMatchObject({ itemSlug: "gear_major4_accessory_purple", quality: "purple" });
      await app.close();
    });
  });

  it("full bag + auto-decompose ON: a new white/green is decomposed into enhance EXP and not stored", async () => {
    await withDb(async (db) => {
      const { app, control, state, bag, fill, playerId } = await boot(db, "drop_e");
      await fill("gear_major1_weapon_white", 20);
      control.chance = 0;
      control.quality = 0; // 白
      control.slot = 1;
      const before = (await db.select().from(playerStates).where(eq(playerStates.playerId, playerId)))[0]!.enhanceExp;
      const result = await state(30);
      const kills = result.lastSettle.kills;
      expect(kills).toBeGreaterThan(0);
      expect(result.lastSettle.drops.every((drop: { decomposed: boolean; dropped: boolean }) => drop.decomposed && !drop.dropped)).toBe(true);
      expect(result.lastSettle.bagFull).toBe(false);
      expect(await bag()).toHaveLength(20);
      expect(result.enhanceExp).toBeGreaterThan(before);
      await app.close();
    });
  });

  it("full bag + auto-decompose ON: a new blue frees one unenhanced white/green first; with nothing to free it does not drop and bagFull is reported", async () => {
    await withDb(async (db) => {
      const { app, control, state, bag, fill } = await boot(db, "drop_f");
      await fill("gear_major1_weapon_white", 19);
      await fill("gear_major1_weapon_purple", 1); // 紫不会被自动分解
      control.chance = 0;
      control.quality = 95000; // 蓝
      control.slot = 0;
      const first = await state(12);
      expect(first.lastSettle.kills).toBeGreaterThanOrEqual(1);
      const dropsWithFree = first.lastSettle.drops.filter((drop: { freed: unknown[] }) => drop.freed.length > 0);
      expect(dropsWithFree.length).toBeGreaterThan(0);
      expect(dropsWithFree[0]).toMatchObject({ itemSlug: "gear_major1_weapon_blue", dropped: false });
      const rows = await bag();
      expect(rows.filter((row) => row.itemSlug === "gear_major1_weapon_blue").length).toBeGreaterThan(0);
      expect(rows).toHaveLength(20);
      // 把包换成：全是蓝（不能自动分解）→ 再来一个蓝：不掉，提示行囊已满
      await db.delete(playerItems);
      await fill("gear_major1_weapon_blue", 20);
      const second = await state(80);
      expect(second.lastSettle.kills).toBeGreaterThan(0);
      expect(second.lastSettle.drops.every((drop: { dropped: boolean }) => drop.dropped)).toBe(true);
      expect(second.lastSettle.bagFull).toBe(true);
      expect(await bag()).toHaveLength(20);
      await app.close();
    });
  });

  it("enhanced white/green are protected from auto-decompose; with the switch OFF a full bag drops nothing and says so", async () => {
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
