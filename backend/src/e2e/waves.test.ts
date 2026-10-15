import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { playerItems, playerStates, players } from "../db/schema.js";
import { advanceWaves, waveCycle } from "../modules/combat/wave.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z");
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

async function boot(db: TestDb, name: string, randomInt: (min: number, max: number) => number = () => 9999) {
  await applyPrototypeV12(db);
  let clock = start;
  const app = await buildApp(db, () => clock, { randomInt });
  const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: name, password: "correct-horse" } });
  const headers = { authorization: `Bearer ${registered.json().token as string}` };
  const [player] = await db.select().from(players).where(eq(players.usernameLower, name));
  const at = (seconds: number) => {
    clock = new Date(start.getTime() + seconds * 1000);
  };
  const state = async () => (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json();
  return { app, headers, playerId: player!.id, at, state };
}

const rules = { waveSize: 3, transitionSeconds: 2, reviveSeconds: 3, defenseConstant: 1 };
const wolf = { hp: 110, attack: 24, defense: 14, interval: 1.5 };

describe("normal-monster waves (server-deterministic, online only)", () => {
  it("3 s polls for 15 minutes: kills and kill cultivation match the pure wave model exactly (passive 1/s + 3 per kill)", async () => {
    await withDb(async (db) => {
      const { app, at, state } = await boot(db, "wave_a");
      const first = await state();
      const cycle = waveCycle({ hp: first.hp, attack: first.attack, defense: first.defense, interval: first.interval }, wolf, rules);
      expect(first.wave).toMatchObject({ available: true, stageSlug: "lianqi_1", monster: { name: "青鬃狼", killCultivation: 3 }, waveSize: 3 });
      expect(first.wave.cycleSeconds).toBeCloseTo(cycle.cycleSeconds, 3);
      let kills = 0;
      let last = first;
      for (let poll = 1; poll <= 300; poll += 1) {
        at(poll * 3);
        last = await state();
        expect(last.lastSettle.online).toBe(true);
        kills += last.lastSettle.kills;
      }
      const expected = advanceWaves(0, 900, cycle).kills;
      expect(kills).toBe(expected);
      expect(kills).toBeGreaterThan(80); // 没穿装备，约 8 秒一只
      expect(last.cultivation).toBe(900 + expected * 3);
      expect(last.wave.progress).toBeCloseTo(advanceWaves(0, 900, cycle).progress, 2);
      await app.close();
    });
  }, 120_000);

  it("a gap longer than 15 s is one offline segment: only the passive cultivation, no kills, wave progress reset", async () => {
    await withDb(async (db) => {
      const { app, at, state, playerId } = await boot(db, "wave_b");
      at(6);
      const online = await state();
      expect(online.lastSettle).toMatchObject({ online: true, passiveGained: 6 });
      await db.update(playerStates).set({ waveProgress: 5, waveDeathsInRow: 2 }).where(eq(playerStates.playerId, playerId));
      at(6 + 16); // 16 秒 > 15 秒
      const away = await state();
      expect(away.lastSettle).toMatchObject({ online: false, seconds: 16, passiveGained: 16, kills: 0, killCultivation: 0 });
      expect(away.cultivation).toBe(online.cultivation + 16);
      expect(away.wave.progress).toBe(0);
      expect(away.wave.deathsInRow).toBe(0);
      at(6 + 16 + 2 * 3600);
      const long = await state();
      expect(long.lastSettle).toMatchObject({ online: false, passiveGained: 7200, kills: 0 });
      expect(long.cultivation).toBe(away.cultivation + 7200);
      // 重新回到前台：下一次 3 秒轮询又算在线
      at(6 + 16 + 2 * 3600 + 3);
      expect((await state()).lastSettle.online).toBe(true);
      await app.close();
    });
  });

  it("exactly 15 s counts as online (the boundary)", async () => {
    await withDb(async (db) => {
      const { app, at, state } = await boot(db, "wave_c");
      at(15);
      const result = await state();
      expect(result.lastSettle).toMatchObject({ online: true, passiveGained: 15 });
      expect(result.lastSettle.kills).toBeGreaterThan(0);
      await app.close();
    });
  });

  it("concurrent polls do not double count (row lock + advancing lastSettledAt)", async () => {
    await withDb(async (db) => {
      const { app, at, state } = await boot(db, "wave_d");
      at(12);
      const results = await Promise.all([state(), state(), state(), state(), state()]);
      const total = results.reduce((sum, row) => sum + row.lastSettle.kills, 0);
      const cycle = waveCycle({ hp: results[0].hp, attack: results[0].attack, defense: results[0].defense, interval: results[0].interval }, wolf, rules);
      expect(total).toBe(advanceWaves(0, 12, cycle).kills);
      expect(Math.max(...results.map((row) => row.cultivation))).toBe(12 + total * 3);
      await app.close();
    });
  });

  it("default stage is the highest one the realm reaches; POST /me/idle-stage switches (idempotent) and rejects locked or unknown stages", async () => {
    await withDb(async (db) => {
      const { app, headers, playerId, state } = await boot(db, "wave_e");
      expect((await state()).wave).toMatchObject({ stageSlug: "lianqi_1", chosenStageSlug: null });
      await db.update(playerStates).set({ realmSlug: "lianqi_3" }).where(eq(playerStates.playerId, playerId));
      const high = await state();
      expect(high.wave.stageSlug).toBe("lianqi_3");
      expect(high.wave.selectable.map((row: { slug: string }) => row.slug)).toEqual(["lianqi_1", "lianqi_2", "lianqi_3"]);
      const post = (stageSlug: unknown, key: string) => app.inject({ method: "POST", url: "/api/v1/me/idle-stage", headers: { ...headers, "idempotency-key": key }, payload: { stageSlug } });
      const switched = await post("lianqi_2", "idle-key-0001");
      expect(switched.statusCode).toBe(200);
      expect(switched.json().wave).toMatchObject({ stageSlug: "lianqi_2", chosenStageSlug: "lianqi_2", progress: 0 });
      expect((await post("lianqi_2", "idle-key-0001")).json().wave.stageSlug).toBe("lianqi_2");
      expect((await post("zhuji_1", "idle-key-0002")).statusCode).toBe(400);
      expect((await post("nope", "idle-key-0003")).statusCode).toBe(400);
      expect((await post(5, "idle-key-0004")).statusCode).toBe(400);
      const back = await post(null, "idle-key-0005");
      expect(back.json().wave).toMatchObject({ stageSlug: "lianqi_3", chosenStageSlug: null });
      await app.close();
    });
  });

  it("breakthrough auto-switches the farming stage to the new layer's stage", async () => {
    await withDb(async (db) => {
      const { app, headers, playerId, state } = await boot(db, "wave_f");
      await db.update(playerStates).set({ cultivation: 100000, idleStageSlug: "lianqi_1" }).where(eq(playerStates.playerId, playerId));
      const response = await app.inject({ method: "POST", url: "/api/v1/me/breakthrough", headers: { ...headers, "idempotency-key": "break-key-0001" }, payload: {} });
      expect(response.json().result.success).toBe(true);
      const after = await state();
      expect(after.realmSlug).toBe("lianqi_2");
      expect(after.wave).toMatchObject({ stageSlug: "lianqi_2", chosenStageSlug: null });
      await app.close();
    });
  });

  it("deaths: a monster the player cannot beat gives revive time, zero kills and a death streak", async () => {
    await withDb(async (db) => {
      const { app, at, state, playerId } = await boot(db, "wave_g");
      // 把玩家放到筑基一层关卡，但面板只有炼气一层 → 打不过游魂（攻击 100）
      await db.update(playerStates).set({ idleStageSlug: null }).where(eq(playerStates.playerId, playerId));
      const { contentStages } = await import("../db/schema.js");
      await db.update(contentStages).set({ monsters: [{ name: "铁傀", attack: 5000, defense: 5000, hp: 1e9, interval: 1, killCultivation: 3 }] }).where(eq(contentStages.slug, "lianqi_1"));
      let deaths = 0;
      let kills = 0;
      let last = await state();
      for (let poll = 1; poll <= 20; poll += 1) {
        at(poll * 3);
        last = await state();
        deaths += last.lastSettle.deaths;
        kills += last.lastSettle.kills;
      }
      expect(kills).toBe(0);
      expect(deaths).toBeGreaterThanOrEqual(3);
      expect(last.wave.deathsInRow).toBe(deaths);
      expect(last.cultivation).toBe(60); // 只有挂机修为 1/秒，没有击杀修为
      expect(last.wave.killsPerWave).toBe(0);
      expect(last.wave.deathsPerWave).toBe(3);
      await app.close();
    });
  });

  it("a world without monsters keeps the old behaviour (no waves, passive cultivation only)", async () => {
    await withDb(async (db) => {
      const { app, at, state } = await boot(db, "wave_h");
      const { contentStages } = await import("../db/schema.js");
      await db.update(contentStages).set({ monsters: [] });
      at(30);
      const result = await state();
      expect(result.wave).toMatchObject({ available: false, stageSlug: null });
      expect(result.cultivation).toBe(30);
      await app.close();
    });
  });
});
