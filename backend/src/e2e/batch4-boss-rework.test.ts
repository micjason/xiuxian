/**
 * 第四批：首领玩法改版——一套规则、挂机每 N 波刷首领（在线 + 离线）、全局每日首领挑战总次数、首次挑战不算、挂机首领算不算次数的开关。
 */
import { and, eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentStages, equipmentGrants, playerStageProgress, playerStates, players } from "../db/schema.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { readGrantResult } from "../modules/loop/boss-rewards.js";
import { testAdmin } from "../test/admin.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z"); // 北京 10-08 11:00
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

/** 掷骰：10000 = 掉不掉（0 = 必中），6 = 部位（0 = 武器），min≥1 = 数量取最小，其余 = 品质（0 = 最低一档有概率的品质）。 */
const randomInt = (min: number, max: number) => (max === 10000 ? 0 : max === 6 ? 0 : min >= 1 ? min : 0);

async function boot(db: TestDb, name: string) {
  await applyPrototypeV12(db);
  await testAdmin(db, "b4_admin");
  let clock = start;
  const app = await buildApp(db, () => clock, { randomInt });
  const login = await app.inject({ method: "POST", url: "/admin/auth/login", payload: { username: "b4_admin", password: "admin-secret" } });
  const admin = { authorization: `Bearer ${login.json().token as string}` };
  const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: name, password: "correct-horse" } });
  const headers = { authorization: `Bearer ${registered.json().token as string}` };
  const [player] = await db.select().from(players).where(eq(players.usernameLower, name));
  const playerId = player!.id;
  // 行囊放大：第五批起满包时关卡掉落 / 首领装备不发（这里测的是刷首领本身，不让行囊满干扰）
  await db.update(playerStates).set({ realmSlug: "lianqi_1", bagBonus: 100000 }).where(eq(playerStates.playerId, playerId));
  // 本关小怪很弱（首领 = 小怪 × 倍率，也很弱）
  const [row] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_1"));
  await db.update(contentStages).set({ monsters: row!.monsters!.map((m) => ({ ...m, hp: 2, attack: 1, defense: 0 })) }).where(eq(contentStages.slug, "lianqi_1"));
  let n = 0;
  const challenge = () =>
    app.inject({ method: "POST", url: "/api/v1/me/stages/lianqi_1/challenge", headers: { ...headers, "idempotency-key": `b4-key-${name}-${(n += 1)}-pad` }, payload: {} });
  const state = async () => (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json();
  const at = (seconds: number) => {
    clock = new Date(start.getTime() + seconds * 1000);
  };
  const rules = async (payload: Record<string, unknown>) => {
    const saved = await app.inject({ method: "PUT", url: "/admin/draft/boss-rules", headers: admin, payload });
    expect(saved.statusCode).toBe(200);
  };
  const cleared = async () => {
    await db.insert(playerStageProgress).values({ playerId, stageSlug: "lianqi_1", unlockedAt: start, firstClearedAt: start, clearCount: 1 }).onConflictDoUpdate({ target: [playerStageProgress.playerId, playerStageProgress.stageSlug], set: { firstClearedAt: start, clearCount: 1 } });
  };
  const progress = async () => (await db.select().from(playerStageProgress).where(and(eq(playerStageProgress.playerId, playerId), eq(playerStageProgress.stageSlug, "lianqi_1"))))[0];
  const repeatGrants = async () => (await db.select().from(equipmentGrants).where(and(eq(equipmentGrants.playerId, playerId), eq(equipmentGrants.source, "boss_repeat"))));
  const daily = async () => (await db.select().from(playerStates).where(eq(playerStates.playerId, playerId)))[0]!;
  return { app, admin, headers, playerId, challenge, state, at, rules, cleared, progress, repeatGrants, daily };
}

describe("第四批：挂机每 N 波刷首领", () => {
  it("online: 3 s polls add up the completed waves; every N waves one boss fight with the repeat reward (boss_repeat grant), not counted toward the daily total by default", async () => {
    await withDb(async (db) => {
      const { app, state, at, rules, cleared, progress, repeatGrants, daily } = await boot(db, "b4_online");
      await cleared();
      await rules({ idleSpawnWaves: 2 });
      let spawns = 0;
      let wins = 0;
      let rewarded = 0;
      let cycle = 0;
      for (let poll = 1; poll <= 100; poll += 1) {
        at(poll * 3);
        const body = await state();
        cycle = body.wave.cycleSeconds;
        expect(body.wave.stageSlug).toBe("lianqi_1");
        const idle = body.lastSettle.idleBoss;
        if (idle) {
          expect(idle).toMatchObject({ stageSlug: "lianqi_1", every: 2, skipped: 0, countedDaily: 0 });
          spawns += idle.spawns;
          wins += idle.wins;
          rewarded += idle.rewarded;
        }
      }
      const totalWaves = Math.floor(300 / cycle);
      expect(totalWaves).toBeGreaterThanOrEqual(4);
      const counter = (await progress())!.idleWaves;
      expect(spawns * 2 + counter).toBe(totalWaves);
      expect(spawns).toBe(Math.floor(totalWaves / 2));
      expect(wins).toBe(spawns);
      expect(rewarded).toBe(spawns);
      // 每只赢了的首领 1 件重复奖励装备（来源 boss_repeat，sourceRef = 关卡，单号各不相同）
      const grants = await repeatGrants();
      expect(grants).toHaveLength(spawns);
      expect(new Set(grants.map((row) => row.requestId)).size).toBe(spawns);
      expect(grants.every((row) => row.sourceRef === "lianqi_1")).toBe(true);
      // 开关默认关 = 不算每日次数
      expect((await daily()).bossDailyCount).toBe(0);
      const total = (await state()).bossDailyTotal;
      expect(total).toMatchObject({ used: 0, limit: 5 });
      expect(total.idleWaves).toEqual([{ stageSlug: "lianqi_1", waves: counter, every: 2, countsDaily: false }]);
      await app.close();
    });
  });

  it("offline: the counted seconds are folded into waves (seconds ÷ one wave), spawns = waves ÷ N capped by idleSpawnMaxPerSettle, the remainder is kept; a replayed poll grants nothing new", async () => {
    await withDb(async (db) => {
      const { app, state, at, rules, cleared, progress, repeatGrants } = await boot(db, "b4_offline");
      await cleared();
      await rules({ idleSpawnWaves: 7, idleSpawnMaxPerSettle: 1000 });
      at(3);
      const cycle = (await state()).wave.cycleSeconds as number;
      const before = (await progress())!.idleWaves;
      at(3 + 7200);
      const body = await state();
      expect(body.lastSettle.online).toBe(false);
      const idle = body.lastSettle.idleBoss;
      const waves = Math.floor(7200 / cycle);
      expect(idle.waves).toBe(waves);
      expect(idle.spawns).toBe(Math.floor((before + waves) / 7));
      expect(idle).toMatchObject({ wins: idle.spawns, rewarded: idle.spawns, skipped: 0, idleWaves: (before + waves) % 7 });
      expect((await progress())!.idleWaves).toBe((before + waves) % 7);
      expect(await repeatGrants()).toHaveLength(idle.spawns);
      // 同一时刻再结算一次：没有新的时长，不再刷
      const again = await state();
      expect(again.lastSettle.idleBoss).toBeNull();
      expect(await repeatGrants()).toHaveLength(idle.spawns);
      // 一次最多 3 只：多出来的不补，计数只留余数
      await rules({ idleSpawnMaxPerSettle: 3 });
      const counter = (await progress())!.idleWaves;
      at(3 + 7200 + 7200);
      const capped = (await state()).lastSettle.idleBoss;
      const due = Math.floor((counter + Math.floor(7200 / cycle)) / 7);
      expect(capped).toMatchObject({ spawns: 3, wins: 3, skipped: due - 3 });
      await app.close();
    });
  });

  it("a boss not beaten yet gets no wave counter and no idle spawns (it is auto-challenged instead when the rules allow)", async () => {
    await withDb(async (db) => {
      const { app, state, at, rules, progress } = await boot(db, "b4_unbeaten");
      await rules({ idleSpawnWaves: 1, autoChallenge: false });
      at(3);
      await state();
      at(3 + 3600);
      const body = await state();
      expect(body.lastSettle.idleBoss).toBeNull();
      expect((await progress())?.idleWaves ?? 0).toBe(0);
      await app.close();
    });
  });

  it("idle spawn off for one stage (per-stage override): no counter, no fights", async () => {
    await withDb(async (db) => {
      const { app, state, at, rules, cleared, progress } = await boot(db, "b4_off");
      await cleared();
      await rules({ idleSpawnWaves: 1 });
      const [row] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_1"));
      await db.update(contentStages).set({ bosses: [{ ...row!.bosses[0]!, rules: { idleSpawn: false } }] }).where(eq(contentStages.slug, "lianqi_1"));
      at(3);
      await state();
      at(3 + 3600);
      expect((await state()).lastSettle.idleBoss).toBeNull();
      expect((await progress())!.idleWaves).toBe(0);
      await app.close();
    });
  });

  it("the boss fight is deterministic: if it is lost, every spawn of this settlement is a loss with no reward", async () => {
    await withDb(async (db) => {
      const { app, state, at, rules, cleared, repeatGrants } = await boot(db, "b4_loss");
      await cleared();
      await rules({ idleSpawnWaves: 5 });
      const [row] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_1"));
      await db.update(contentStages).set({ bosses: [{ ...row!.bosses[0]!, hp: 1e9, attack: 1e6, rules: { statMode: "manual" } }] }).where(eq(contentStages.slug, "lianqi_1"));
      at(3);
      await state();
      at(3 + 3600);
      const idle = (await state()).lastSettle.idleBoss;
      expect(idle.spawns).toBeGreaterThan(1);
      expect(idle).toMatchObject({ wins: 0, losses: idle.spawns, rewarded: 0, drops: [] });
      expect(await repeatGrants()).toHaveLength(0);
      await app.close();
    });
  });
});

describe("第四批：每日首领挑战总次数（全局）", () => {
  it("first challenge of a not-yet-beaten boss is free; manual repeats use the total; when it runs out the fight still happens without reward; switch OFF: idle bosses are still rewarded and never use it", async () => {
    await withDb(async (db) => {
      const { app, challenge, state, at, rules, repeatGrants, daily } = await boot(db, "b4_daily");
      await rules({ dailyChallengeTotal: 2, idleSpawnWaves: 1, idleSpawnMaxPerSettle: 3, autoChallenge: false });
      const first = (await challenge()).json();
      expect(first.battle.win).toBe(true);
      expect(first.reward).toMatchObject({ firstClear: true, countedDaily: false, dailyRewardCount: 0, dailyRewardLimit: 2 });
      expect((await daily()).bossDailyCount).toBe(0);
      const r1 = (await challenge()).json();
      const r2 = (await challenge()).json();
      const r3 = (await challenge()).json();
      expect([r1, r2, r3].map((row) => [row.battle.win, row.reward.rewarded, row.reward.countedDaily, row.reward.dailyRewardCount])).toEqual([
        [true, true, true, 1],
        [true, true, true, 2],
        [true, false, false, 2],
      ]);
      expect(r3.drops).toEqual([]);
      expect(await repeatGrants()).toHaveLength(2);
      // 次数用完了，挂机首领（开关关）照样有奖励、不消耗
      at(7200);
      const idle = (await state()).lastSettle.idleBoss;
      expect(idle).toMatchObject({ spawns: 3, wins: 3, rewarded: 3, countedDaily: 0 });
      expect(await repeatGrants()).toHaveLength(5);
      expect((await daily()).bossDailyCount).toBe(2);
      expect((await state()).bossDailyTotal).toMatchObject({ used: 2, limit: 2 });
      await app.close();
    });
  });

  it("switch ON: idle bosses use the daily total while it lasts; once it is used up they are still fought but give no reward", async () => {
    await withDb(async (db) => {
      const { app, state, at, rules, cleared, repeatGrants, daily } = await boot(db, "b4_switch");
      await cleared();
      await rules({ dailyChallengeTotal: 2, idleSpawnWaves: 1, idleSpawnMaxPerSettle: 3, idleSpawnCountsDaily: true });
      at(3);
      await state();
      at(3 + 7200);
      const idle = (await state()).lastSettle.idleBoss;
      expect(idle).toMatchObject({ spawns: 3, wins: 3, rewarded: 2, countedDaily: 2 });
      expect(await repeatGrants()).toHaveLength(2);
      expect((await daily()).bossDailyCount).toBe(2);
      // 换天（北京 05:00 = UTC 21:00）后重新有次数
      at((new Date("2026-10-08T21:00:00.000Z").getTime() - start.getTime()) / 1000);
      const next = (await state()).lastSettle.idleBoss;
      expect(next).toMatchObject({ spawns: 3, rewarded: 2, countedDaily: 2 });
      expect(await daily()).toMatchObject({ bossDailyCount: 2, bossDailyDay: "2026-10-09" });
      await app.close();
    });
  });
});

describe("第四批：装备发放的「行囊满」返回值（主程序 grantEquipment）", () => {
  it("reads the old array shape and the new skipped: bag_full shapes tolerantly", () => {
    expect(readGrantResult([{ id: "a" }])).toEqual({ count: 1, skipped: null });
    expect(readGrantResult(Object.assign([], { skipped: "bag_full" }))).toEqual({ count: 0, skipped: "bag_full" });
    expect(readGrantResult({ items: [], skipped: "bag_full" })).toEqual({ count: 0, skipped: "bag_full" });
    expect(readGrantResult({ granted: [{ id: "a" }, { id: "b" }] })).toEqual({ count: 2, skipped: null });
    expect(readGrantResult(undefined)).toEqual({ count: 0, skipped: null });
  });

  it("treats a missing / undefined skipped or bagFull as not skipped (the lead's bag-full check is not live yet)", () => {
    expect(readGrantResult(null)).toEqual({ count: 0, skipped: null });
    expect(readGrantResult(Object.assign([{ id: "a" }], { skipped: undefined, bagFull: undefined }))).toEqual({ count: 1, skipped: null });
    expect(readGrantResult({ items: [{ id: "a" }], skipped: undefined, bagFull: undefined })).toEqual({ count: 1, skipped: null });
    expect(readGrantResult({ items: [{ id: "a" }], skipped: null, bagFull: false })).toEqual({ count: 1, skipped: null });
    expect(readGrantResult({ items: [{ id: "a" }], skipped: "" })).toEqual({ count: 1, skipped: null });
    expect(readGrantResult({ items: [], bagFull: true })).toEqual({ count: 0, skipped: "bag_full" });
  });
});
