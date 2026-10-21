import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentGlobals, contentRealms, contentStages, equipmentGrants, playerItems, playerStageProgress, playerStates, players } from "../db/schema.js";
import { simulateBossFight } from "../modules/combat/battle.js";
import { DEFAULT_BOSS_RULES, type BossRules } from "../modules/content/boss-rules.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z"); // 北京 10-08 11:00
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

/** 掷骰：10000 = 掉不掉（0 = 必中），6 = 部位，min≥1 = 数量取最小，其余 = 品质（0 = 最低一档）。 */
const randomInt = (min: number, max: number) => (max === 10000 ? 0 : max === 6 ? 0 : min >= 1 ? min : 0);

async function boot(db: TestDb, name: string, realmSlug = "lianqi_3") {
  await applyPrototypeV12(db);
  let clock = start;
  const app = await buildApp(db, () => clock, { randomInt });
  const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: name, password: "correct-horse" } });
  const headers = { authorization: `Bearer ${registered.json().token as string}` };
  const [player] = await db.select().from(players).where(eq(players.usernameLower, name));
  await db.update(playerStates).set({ realmSlug }).where(eq(playerStates.playerId, player!.id));
  // 第三批：下一关要先打赢上一关的首领才解锁。这里的用例都打黑风熊王（lianqi_3），先把前两关的精英记成已通关
  for (const stageSlug of ["lianqi_1", "lianqi_2"]) {
    await db.insert(playerStageProgress).values({ playerId: player!.id, stageSlug, unlockedAt: start, firstClearedAt: start, clearCount: 1 }).onConflictDoUpdate({ target: [playerStageProgress.playerId, playerStageProgress.stageSlug], set: { firstClearedAt: start, clearCount: 1 } });
  }
  let n = 0;
  const challenge = (stage: string, payload: Record<string, unknown> = {}) =>
    app.inject({ method: "POST", url: `/api/v1/me/stages/${stage}/challenge`, headers: { ...headers, "idempotency-key": `boss-key-${name}-${(n += 1)}-pad` }, payload });
  const state = async () => (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json();
  const setClock = (date: Date) => {
    clock = date;
  };
  const bag = async () => (await db.select().from(playerItems).where(eq(playerItems.playerId, player!.id))).filter((row) => !row.equippedSlot);
  const weakBear = async (hp = 5) =>
    db.update(contentStages).set({ bosses: [{ ...(await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_3")))[0]!.bosses[0]!, hp, attack: 1 }] }).where(eq(contentStages.slug, "lianqi_3"));
  return { app, headers, playerId: player!.id, challenge, state, setClock, bag, weakBear };
}

describe("boss first-clear fixed rewards", () => {
  it("first clear of 黑风熊王: +1,500 cultivation, 青元诀 book, a blue accessory of the qi tier, 3 low stones", async () => {
    await withDb(async (db) => {
      const { app, challenge, state, bag, weakBear } = await boot(db, "boss_a");
      await weakBear();
      const before = await state();
      const response = await challenge("lianqi_3");
      expect(response.statusCode).toBe(200);
      const body = response.json();
      expect(body.battle.win).toBe(true);
      expect(body.reward).toMatchObject({ firstClear: true, cultivation: 1500, rewarded: false });
      const slugs = body.drops.map((row: { itemSlug: string }) => row.itemSlug);
      expect(slugs).toContain("gear_major1_accessory_blue");
      expect(slugs).toContain("enh_stone_low");
      expect(body.drops.find((row: { itemSlug: string }) => row.itemSlug === "enh_stone_low").quantity).toBe(3);
      const rows = await bag();
      expect(rows.find((row) => row.itemSlug === "enh_stone_low")?.quantity).toBe(3);
      expect(rows.some((row) => row.itemSlug === "gear_major1_accessory_blue")).toBe(true);
      expect(rows.some((row) => row.itemSlug.startsWith("b") && row.itemSlug !== "gear_major1_accessory_blue")).toBe(true); // 青元诀功法书
      expect(body.state.cultivation).toBeGreaterThanOrEqual(before.cultivation + 1500);
      expect(body.state.cultivation).toBeLessThan(before.cultivation + 1500 + 60);
      // 第二次不再给首通奖励
      const again = (await challenge("lianqi_3")).json();
      expect(again.reward.firstClear).toBe(false);
      expect(again.drops.some((row: { itemSlug: string }) => row.itemSlug === "gear_major1_accessory_blue")).toBe(false);
      await app.close();
    });
  });

  it("a full bag never refuses a boss challenge; first-clear rewards may exceed capacity; boss gear is granted even when full (grantEquipment)", async () => {
    await withDb(async (db) => {
      const { app, challenge, bag, weakBear, playerId } = await boot(db, "boss_b");
      await weakBear();
      for (let index = 0; index < 20; index += 1) {
        await db.insert(playerItems).values({ playerId, itemSlug: "gear_major1_weapon_blue", isStack: false, quantity: 1, source: "test", acquiredAt: new Date(start.getTime() - 1000 * (index + 1)) });
      }
      // 20/20 且没有可自动分解的白/绿：以前会被拒绝，现在照常打
      const first = await challenge("lianqi_3");
      expect(first.statusCode).toBe(200);
      expect(first.json().battle.win).toBe(true);
      expect(first.json().freedBeforeFight).toBeUndefined();
      const afterFirst = await bag();
      expect(afterFirst.length).toBeGreaterThan(20); // 首通固定奖励允许超出容量
      expect(first.json().drops.some((row: { dropped?: boolean }) => row.dropped)).toBe(false);
      // 重复挑战：首领装备走统一发放接口 grantEquipment（ADMIN_SPEC §14）—— 行囊满照发、不自动分解，记一条 boss_repeat 流水
      await db.update(playerStates).set({ autoDecompose: true }).where(eq(playerStates.playerId, playerId));
      const again = await challenge("lianqi_3");
      expect(again.statusCode).toBe(200);
      const body = again.json();
      const gearBefore = afterFirst.filter((row) => row.itemSlug.startsWith("gear_")).length;
      const gearAfter = (await bag()).filter((row) => row.itemSlug.startsWith("gear_")).length;
      expect(gearAfter).toBe(gearBefore + 1);
      const gearDrops = body.drops.filter((row: { itemSlug: string }) => row.itemSlug.startsWith("gear_"));
      expect(gearDrops).toHaveLength(1);
      expect(gearDrops[0].dropped).toBeUndefined();
      expect(gearDrops[0].decomposed).toBeUndefined();
      const grants = await db.select().from(equipmentGrants).where(eq(equipmentGrants.playerId, playerId));
      // 批次②之后所有装备入包都记发放流水：首通的固定装备（饰品）记 boss_first，这次重打抽到的记 boss_repeat
      const rows = grants.filter((row) => row.sourceRef === "lianqi_3").map((row) => [row.source, row.sourceRef, row.itemSlug, row.count]);
      expect(rows).toEqual([
        ["boss_first", "lianqi_3", "gear_major1_accessory_blue", 1],
        ["boss_repeat", "lianqi_3", gearDrops[0].itemSlug, 1],
      ]);
      await app.close();
    });
    await withDb(async (db) => {
      const { app, challenge, weakBear, playerId } = await boot(db, "boss_c");
      await weakBear();
      for (let index = 0; index < 20; index += 1) {
        await db.insert(playerItems).values({ playerId, itemSlug: "gear_major1_weapon_white", isStack: false, quantity: 1, source: "test", acquiredAt: new Date(start.getTime() - 1000 * (index + 1)) });
      }
      // 自动分解开着也不再在挑战前腾格，也不拒绝
      const response = await challenge("lianqi_3");
      expect(response.statusCode).toBe(200);
      expect(response.json().freedBeforeFight).toBeUndefined();
      await app.close();
    });
  });

  it("materials (breakthrough stones) still land in a full bag", async () => {
    await withDb(async (db) => {
      const { app, challenge, bag, weakBear, playerId } = await boot(db, "boss_m");
      await weakBear();
      for (let index = 0; index < 20; index += 1) {
        await db.insert(playerItems).values({ playerId, itemSlug: "gear_major1_weapon_blue", isStack: false, quantity: 1, source: "test" });
      }
      const response = await challenge("lianqi_3");
      expect(response.statusCode).toBe(200);
      const stones = (await bag()).filter((row) => row.itemSlug === "enh_stone_low");
      expect(stones.reduce((sum, row) => sum + row.quantity, 0)).toBeGreaterThanOrEqual(3);
      await app.close();
    });
  });

  it("a stage without a boss refuses the challenge with a clear message", async () => {
    await withDb(async (db) => {
      const { app, challenge } = await boot(db, "boss_d");
      await db.update(contentStages).set({ bosses: [], bossHp: 0 }).where(eq(contentStages.slug, "lianqi_1")); // 第三批起每关都有首领，手动拿掉一个
      const response = await challenge("lianqi_1");
      expect(response.statusCode).toBe(400);
      expect(response.json().error.message).toContain("还没有首领");
      await app.close();
    });
  });
});

async function setBossRules(db: TestDb, patch: (rules: BossRules) => void) {
  const [globals] = await db.select().from(contentGlobals);
  const rules = structuredClone(DEFAULT_BOSS_RULES);
  patch(rules);
  await db.update(contentGlobals).set({ tuning: { ...(globals?.tuning ?? {}), bossRules: rules } });
}

describe("boss repeat rewards: gear quality follows 首领规则「重复奖励装备品质」(默认 0/50/35/13/2)", () => {
  it("the repeat gear quality is rolled from repeatGearQualityPct, and each slot follows the drop multipliers", async () => {
    await withDb(async (db) => {
      const { app, challenge, weakBear } = await boot(db, "boss_o");
      await weakBear();
      await challenge("lianqi_3"); // 首通
      const first = (await challenge("lianqi_3")).json();
      // 掷骰 0 = 最低一档有概率的品质：默认章末白 0% → 绿；部位等概率，掷 0 = 武器
      expect(first.drops.map((row: { itemSlug: string }) => row.itemSlug).filter((slug: string) => slug.startsWith("gear_"))).toEqual(["gear_major1_weapon_green"]);
      await setBossRules(db, (rules) => {
        rules.repeatGearQualityPct = { white: 0, green: 0, blue: 0, purple: 0, orange: 100 };
      });
      const body = (await challenge("lianqi_3")).json();
      expect(body.drops.map((row: { itemSlug: string }) => row.itemSlug).filter((slug: string) => slug.startsWith("gear_"))).toEqual(["gear_major1_weapon_orange"]);
      await app.close();
    });
  });
});

describe("boss repeat rewards: one global daily boss challenge total (Beijing time, day starts 05:00)", () => {
  it("first clear does not use the daily count; the next 5 wins reward gear (white → green) + stones; the 6th still wins but has no reward; it resets at 05:00 Beijing", async () => {
    await withDb(async (db) => {
      const { app, challenge, state, setClock, weakBear, playerId } = await boot(db, "boss_e");
      await weakBear();
      await challenge("lianqi_3"); // 首通
      const rewarded: boolean[] = [];
      const gear: string[] = [];
      for (let index = 0; index < 6; index += 1) {
        const body = (await challenge("lianqi_3")).json();
        expect(body.battle.win).toBe(true);
        rewarded.push(body.reward.rewarded);
        gear.push(...body.drops.map((row: { itemSlug: string }) => row.itemSlug).filter((slug: string) => slug.startsWith("gear_")));
        expect(body.reward.dailyRewardLimit).toBe(5);
      }
      expect(rewarded).toEqual([true, true, true, true, true, false]);
      // roll 0 = 最低一档有概率的品质：章末默认白 0%，所以是绿
      expect(gear).toEqual(Array(5).fill("gear_major1_weapon_green"));
      let daily = (await db.select().from(playerStates).where(eq(playerStates.playerId, playerId)))[0]!;
      expect(daily).toMatchObject({ bossDailyCount: 5, bossDailyDay: "2026-10-08" });
      expect((await state()).bossDailyTotal).toMatchObject({ used: 5, limit: 5 });
      // 老客户端的每关格式：每个已击败、有重复奖励的关都显示同一个全局次数
      expect((await state()).bossDaily).toEqual(["lianqi_1", "lianqi_2", "lianqi_3"].map((stageSlug) => ({ stageSlug, used: 5, limit: 5 })));
      // 北京 10-09 04:59:59（UTC 10-08 20:59:59）仍是同一天
      setClock(new Date("2026-10-08T20:59:59.000Z"));
      expect((await challenge("lianqi_3")).json().reward.rewarded).toBe(false);
      // 北京 05:00 换天
      setClock(new Date("2026-10-08T21:00:00.000Z"));
      const fresh = (await challenge("lianqi_3")).json();
      expect(fresh.reward).toMatchObject({ rewarded: true, dailyRewardCount: 1 });
      daily = (await db.select().from(playerStates).where(eq(playerStates.playerId, playerId)))[0]!;
      expect(daily).toMatchObject({ bossDailyCount: 1, bossDailyDay: "2026-10-09" });
      await app.close();
    });
  });

  it("the daily count and the reset hour are admin-configurable rules", async () => {
    await withDb(async (db) => {
      const { app, challenge, setClock, weakBear } = await boot(db, "boss_f");
      await weakBear();
      const [globals] = await db.select().from(contentGlobals);
      await db.update(contentGlobals).set({ combat: { ...globals!.combat!, dayStartHour: 0 } });
      await setBossRules(db, (rules) => {
        rules.dailyChallengeTotal = 1; // 第四批：全局每日首领挑战总次数
      });
      await challenge("lianqi_3");
      expect((await challenge("lianqi_3")).json().reward.rewarded).toBe(true);
      expect((await challenge("lianqi_3")).json().reward.rewarded).toBe(false);
      // 重置整点 0 点：北京 10-09 00:00 = UTC 10-08 16:00
      setClock(new Date("2026-10-08T15:59:59.000Z"));
      expect((await challenge("lianqi_3")).json().reward.rewarded).toBe(false);
      setClock(new Date("2026-10-08T16:00:00.000Z"));
      expect((await challenge("lianqi_3")).json().reward.rewarded).toBe(true);
      await app.close();
    });
  });

  it("a lost fight gives nothing and does not use the daily count", async () => {
    await withDb(async (db) => {
      const { app, challenge, weakBear, playerId } = await boot(db, "boss_g");
      await weakBear();
      await challenge("lianqi_3");
      await weakBear(1e12);
      const lost = (await challenge("lianqi_3")).json();
      expect(lost.battle.win).toBe(false);
      expect(lost.drops).toEqual([]);
      const [daily] = await db.select().from(playerStates).where(eq(playerStates.playerId, playerId));
      expect(daily?.bossDailyCount).toBe(0);
      await app.close();
    });
  });
});

describe("boss ultimate: fully automatic (第四批)", () => {
  async function tuned(db: TestDb, name: string) {
    const ctx = await boot(db, name);
    const state = await ctx.state();
    const fighter = { attack: state.attack, defense: state.defense, hp: state.hp, interval: state.interval };
    const ult = { multBp: 40000, cooldownSeconds: 20, firstCooldownSeconds: 8, autoCastWindowSeconds: 2 };
    expect(state.ult).toMatchObject({ name: "剑诀·破军", multBp: 40000, cooldownSeconds: 20, firstCooldownSeconds: 8, autoCastWindowSeconds: 2 });
    const config = { timeLimitSeconds: 45, defenseConstant: 1 };
    // 找到“带大招（全自动）刚好能赢、不带大招会超时”的最大气血
    const [boss0] = (await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_3")))[0]!.bosses;
    let low = 1;
    let high = 1_000_000;
    while (low < high) {
      const mid = Math.ceil((low + high) / 2);
      const result = simulateBossFight(fighter, { attack: 1, defense: boss0!.defense, hp: mid, interval: 1.5 }, config, ult, []);
      if (result.win) low = mid;
      else high = mid - 1;
    }
    const hp = low;
    expect(simulateBossFight(fighter, { attack: 1, defense: boss0!.defense, hp, interval: 1.5 }, config, null, []).win).toBe(false);
    await db.update(contentStages).set({ bosses: [{ ...boss0!, hp, attack: 1 }] }).where(eq(contentStages.slug, "lianqi_3"));
    return { ...ctx, fighter, ult, config, hp, boss: { attack: 1, defense: boss0!.defense, hp, interval: 1.5 } };
  }

  it("with the realm's ultimate the boss that times out without one can be beaten; the response lists the casts", async () => {
    await withDb(async (db) => {
      const { app, challenge, fighter, ult, config, boss } = await tuned(db, "ult_a");
      const response = (await challenge("lianqi_3")).json();
      expect(response.battle.win).toBe(true);
      expect(response.battle.ultCasts.length).toBeGreaterThanOrEqual(1);
      expect(response.battle.ultCasts[0]).toMatchObject({ t: 10, readyAt: 8, manual: false });
      expect(response.battle.ultCasts[0].damage).toBeGreaterThan(0);
      expect(response.battle.log.some((event: { kind?: string }) => event.kind === "ult")).toBe(true);
      expect(response.battle.durationSeconds).toBe(simulateBossFight(fighter, boss, config, ult, []).durationSeconds);
      await app.close();
    });
  });

  it("taps / waits sent by old clients are ignored: every cast is automatic (ready + auto-cast window)", async () => {
    await withDb(async (db) => {
      const { app, challenge } = await tuned(db, "ult_b");
      for (const payload of [{ ultTaps: [8.5] }, { ultTaps: [8] }, { ultTaps: "hacked" }, { ultWaits: [0.25] }, {}]) {
        const response = await challenge("lianqi_3", payload);
        expect(response.statusCode).toBe(200);
        expect(response.json().battle.ultCasts[0]).toMatchObject({ t: 10, readyAt: 8, manual: false });
      }
      await app.close();
    });
  });

  it("a realm without an ultimate (multiplier 0) fights exactly like before: the same boss is lost on timeout", async () => {
    await withDb(async (db) => {
      const { app, challenge } = await tuned(db, "ult_c");
      await db.update(contentRealms).set({ ultDamageMultBp: 0 });
      const response = (await challenge("lianqi_3", { ultTaps: [8] })).json();
      expect(response.battle.win).toBe(false);
      expect(response.battle.reason).toBe("timeout");
      expect(response.battle.ultCasts).toEqual([]);
      await app.close();
    });
  });

  it("the ultimate stats follow the realm: 筑基 uses ×5 / 18 s", async () => {
    await withDb(async (db) => {
      const { app, state, playerId } = await boot(db, "ult_d", "zhuji_2");
      expect(playerId).toBeTruthy();
      expect((await state()).ult).toMatchObject({ multBp: 50000, cooldownSeconds: 18, firstCooldownSeconds: 8 });
      await app.close();
    });
  });
});
