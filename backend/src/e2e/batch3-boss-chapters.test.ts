/**
 * 第三批：章节 / 每关首领（精英 + 章末）/ 首领规则 / 解锁链 / 自动挑战 / 后台接口。
 */
import { and, eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentStages, equipmentGrants, playerItems, playerStageProgress, playerStates, players } from "../db/schema.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { bossBattleId, grantBossEquipment } from "../modules/loop/boss-rewards.js";
import { withTransaction } from "../db/tx.js";
import { loadDraftSnapshot } from "../modules/content/snapshot.js";
import { validateContent } from "../modules/content/validate.js";
import { testAdmin } from "../test/admin.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z");
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

/** 掷骰：10000 = 掉不掉（0 = 必中），6 = 部位（0 = 武器），min≥1 = 数量取最小，其余 = 品质（0 = 最低一档有概率的品质）。 */
const randomInt = (min: number, max: number) => (max === 10000 ? 0 : max === 6 ? 0 : min >= 1 ? min : 0);

async function boot(db: TestDb, name: string, realmSlug = "lianqi_3") {
  await applyPrototypeV12(db);
  await testAdmin(db, "b3_admin");
  let clock = start;
  const app = await buildApp(db, () => clock, { randomInt });
  const login = await app.inject({ method: "POST", url: "/admin/auth/login", payload: { username: "b3_admin", password: "admin-secret" } });
  const admin = { authorization: `Bearer ${login.json().token as string}` };
  const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: name, password: "correct-horse" } });
  const headers = { authorization: `Bearer ${registered.json().token as string}` };
  const [player] = await db.select().from(players).where(eq(players.usernameLower, name));
  const playerId = player!.id;
  await db.update(playerStates).set({ realmSlug }).where(eq(playerStates.playerId, playerId));
  let n = 0;
  const challenge = (stage: string) =>
    app.inject({ method: "POST", url: `/api/v1/me/stages/${stage}/challenge`, headers: { ...headers, "idempotency-key": `b3-key-${name}-${(n += 1)}-pad` }, payload: {} });
  const state = async () => (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json();
  const at = (seconds: number) => {
    clock = new Date(start.getTime() + seconds * 1000);
  };
  /** 把某关的普通怪改弱 / 改强（精英按普通怪 × 倍率自动算）。 */
  const monster = async (slug: string, patch: { hp?: number; attack?: number; defense?: number }) => {
    const [row] = await db.select().from(contentStages).where(eq(contentStages.slug, slug));
    await db
      .update(contentStages)
      .set({ monsters: row!.monsters!.map((m, index) => (index === 0 ? { ...m, ...patch } : m)) })
      .where(eq(contentStages.slug, slug));
  };
  const progress = async (slug: string) =>
    (await db.select().from(playerStageProgress).where(and(eq(playerStageProgress.playerId, playerId), eq(playerStageProgress.stageSlug, slug))))[0];
  return { app, admin, headers, playerId, challenge, state, at, monster, progress };
}

describe("第三批：章节与每关首领", () => {
  it("the snapshot exposes chapters (bgKey, bossFx, chief stage) and per-stage tier / boss artKey; the chief can be moved by the admin", async () => {
    await withDb(async (db) => {
      const { app, admin } = await boot(db, "b3_snap");
      const world = await loadDraftSnapshot(db);
      expect(world.chapters?.find((row) => row.slug === "chiyan")).toMatchObject({ bossFx: "chiyan", bgKey: "chiyan", battleBgKey: "chiyan", chiefStageSlug: "jindan_3", chiefStageSlugSetting: null });
      expect(world.stages).toHaveLength(24);
      expect(world.chapters).toHaveLength(8);
      expect(world.stages.slice(0, 9).map((row) => [row.slug, row.chapterSlug, row.tier, row.bosses?.[0]?.artKey])).toEqual([
        ["lianqi_1", "heifeng", "elite", "boss_wolf"],
        ["lianqi_2", "heifeng", "elite", "boss_fox"],
        ["lianqi_3", "heifeng", "chief", "boss_bear"],
        ["zhuji_1", "youming", "elite", "boss_ghost"],
        ["zhuji_2", "youming", "elite", "boss_bone_golem"],
        ["zhuji_3", "youming", "chief", "boss_ghost_elder"],
        ["jindan_1", "chiyan", "elite", "boss_lava_lizard"],
        ["jindan_2", "chiyan", "elite", "boss_fire_crow"],
        ["jindan_3", "chiyan", "chief", "boss_fire_jiao"],
      ]);
      expect(world.stages.filter((row) => row.tier === "chief").map((row) => row.slug)).toEqual([
        "lianqi_3", "zhuji_3", "jindan_3", "yuanying_3", "huashen_3", "lianxu_3", "heti_3", "dacheng_3",
      ]);
      // 后台手动指定章末关：只能选本章的关卡
      expect((await app.inject({ method: "PUT", url: "/admin/draft/chapters/heifeng", headers: admin, payload: { chiefStageSlug: "zhuji_1" } })).statusCode).toBe(400);
      expect((await app.inject({ method: "PUT", url: "/admin/draft/chapters/heifeng", headers: admin, payload: { chiefStageSlug: "lianqi_2" } })).statusCode).toBe(200);
      const moved = await loadDraftSnapshot(db);
      expect(moved.stages.filter((row) => row.chapterSlug === "heifeng").map((row) => row.tier)).toEqual(["elite", "chief", "elite"]);
      // 改回自动
      expect((await app.inject({ method: "PUT", url: "/admin/draft/chapters/heifeng", headers: admin, payload: { chiefStageSlug: null } })).statusCode).toBe(200);
      expect((await loadDraftSnapshot(db)).stages.find((row) => row.slug === "lianqi_3")?.tier).toBe("chief");
      await app.close();
    });
  });

  it("publish validation: every enabled stage needs a chapter, exactly one boss, valid art keys; bossFx only default | chiyan", async () => {
    await withDb(async (db) => {
      const { app } = await boot(db, "b3_valid");
      expect(validateContent(await loadDraftSnapshot(db)).errors).toEqual([]);
      const [wolfStage] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_1"));
      await db
        .update(contentStages)
        .set({ chapterSlug: null, monsters: [{ ...wolfStage!.monsters![0]!, artKey: "dragon" }] })
        .where(eq(contentStages.slug, "lianqi_1"));
      await db.update(contentStages).set({ bosses: [], bossHp: 0, bossName: "" }).where(eq(contentStages.slug, "lianqi_2"));
      const errors = validateContent(await loadDraftSnapshot(db)).errors;
      expect(errors.some((row) => row.slug === "lianqi_1" && row.field === "chapterSlug")).toBe(true);
      expect(errors.some((row) => row.slug === "lianqi_1" && row.message.includes("dragon"))).toBe(true);
      expect(errors.some((row) => row.slug === "lianqi_2" && row.message.includes("每个关卡都要有首领"))).toBe(true);
      await app.close();
    });
  });

  it("unlock chain: the next stage needs the previous boss beaten (and the realm); elite first clear = spirit stones + low stone + 1 gear rolled at 0/70/25/5/0; a repeat win now gives the repeat reward and uses the daily total (第四批)", async () => {
    await withDb(async (db) => {
      const { challenge, state, monster, app } = await boot(db, "b3_unlock");
      const before = await state();
      expect(before.stageAccess).toHaveLength(24);
      expect(before.stageAccess.slice(0, 9).map((row: { slug: string; playable: boolean }) => [row.slug, row.playable])).toEqual([
        ["lianqi_1", true],
        ["lianqi_2", false],
        ["lianqi_3", false],
        ["zhuji_1", false],
        ["zhuji_2", false],
        ["zhuji_3", false],
        ["jindan_1", false],
        ["jindan_2", false],
        ["jindan_3", false],
      ]);
      expect(before.stageAccess.slice(9).every((row: { playable: boolean }) => row.playable === false)).toBe(true);
      expect(before.stageAccess[1]).toMatchObject({ tier: "elite", chapterSlug: "heifeng", needs: { bossWin: { stageSlug: "lianqi_1", bossName: "青鬃狼王", tier: "elite", met: false }, realm: { order: 2, met: true } } });
      const locked = await challenge("lianqi_2");
      expect(locked.statusCode).toBe(409);
      expect(locked.json().error.code).toBe("STAGE_LOCKED");
      await monster("lianqi_1", { hp: 2, attack: 1, defense: 0 });
      const won = await challenge("lianqi_1");
      expect(won.statusCode).toBe(200);
      const body = won.json();
      expect(body.battle.win).toBe(true);
      expect(body.reward).toMatchObject({ firstClear: true, spiritStones: 50 });
      const slugs = body.drops.map((row: { itemSlug: string }) => row.itemSlug);
      expect(slugs).toContain("enh_stone_low");
      expect(slugs.filter((slug: string) => slug.startsWith("gear_"))).toEqual(["gear_major1_weapon_green"]); // 掷 0 = 精英最低一档有概率的品质（白 0%）= 绿
      expect(body.state.spiritStones).toBe(before.spiritStones + 50);
      expect(body.state.stageAccess.find((row: { slug: string }) => row.slug === "lianqi_2")).toMatchObject({ unlocked: true, playable: true });
      // 第四批：一套规则，重打有重复奖励（1 件装备按 0/50/35/13/2 + 70% 突破石·下品），消耗 1 次每日首领挑战总次数
      const again = (await challenge("lianqi_1")).json();
      expect(again.battle.win).toBe(true);
      expect(again.reward).toMatchObject({ firstClear: false, rewarded: true, countedDaily: true, dailyRewardCount: 1, dailyRewardLimit: 5 });
      expect(again.drops.map((row: { itemSlug: string }) => row.itemSlug)).toEqual(["gear_major1_weapon_green", "enh_stone_low"]);
      await app.close();
    });
  });

  it("the realm still gates: an unlocked stage above the player's realm is not playable (REALM_TOO_LOW)", async () => {
    await withDb(async (db) => {
      const { challenge, monster, app, state } = await boot(db, "b3_realm", "lianqi_1");
      await monster("lianqi_1", { hp: 2, attack: 1, defense: 0 });
      await db.update(contentStages).set({ recommendedPower: 1_000_000 }).where(eq(contentStages.slug, "lianqi_1")); // 不让结算里自动打
      expect((await challenge("lianqi_1")).json().battle.win).toBe(true);
      const access = (await state()).stageAccess.find((row: { slug: string }) => row.slug === "lianqi_2");
      expect(access).toMatchObject({ unlocked: true, realmOk: false, playable: false });
      const response = await challenge("lianqi_2");
      expect(response.statusCode).toBe(409);
      expect(response.json().error.code).toBe("REALM_TOO_LOW");
      await app.close();
    });
  });

  it("BOSS_REPEAT_DISABLED when the rules forbid repeats; a per-stage override can turn auto-challenge off for one boss", async () => {
    await withDb(async (db) => {
      const { app, admin, challenge, monster, at, state, playerId } = await boot(db, "b3_repeat");
      await monster("lianqi_1", { hp: 2, attack: 1, defense: 0 });
      expect((await challenge("lianqi_1")).json().battle.win).toBe(true);
      const saved = await app.inject({ method: "PUT", url: "/admin/draft/boss-rules", headers: admin, payload: { allowRepeat: false } });
      expect(saved.statusCode).toBe(200);
      const refused = await challenge("lianqi_1");
      expect(refused.statusCode).toBe(409);
      expect(refused.json().error.code).toBe("BOSS_REPEAT_DISABLED");
      // 第四批：章末首领默认也自动挑战；这一关单独关掉自动挑战后，再弱也不会在结算里自动打
      await db.insert(playerStageProgress).values({ playerId, stageSlug: "lianqi_2", unlockedAt: start, firstClearedAt: start, clearCount: 1 }).onConflictDoUpdate({ target: [playerStageProgress.playerId, playerStageProgress.stageSlug], set: { firstClearedAt: start, clearCount: 1 } });
      const [bear] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_3"));
      await db.update(contentStages).set({ bosses: [{ ...bear!.bosses![0]!, hp: 2, attack: 1, rules: { ...bear!.bosses![0]!.rules, autoChallenge: false } }], recommendedPower: 1 }).where(eq(contentStages.slug, "lianqi_3"));
      at(3);
      const polled = await state();
      expect(polled.wave.stageSlug).toBe("lianqi_3");
      expect(polled.lastSettle.autoChallenge).toBeNull();
      await app.close();
    });
  });

  it("auto-challenge in the settle: an elite is fought when power ≥ recommended × pct; a loss waits autoChallengeRetrySeconds before the next try", async () => {
    await withDb(async (db) => {
      // 炼气首关关掉了自动挑战（教学关）；用二关验证自动挑战
      const { app, state, at, monster, playerId } = await boot(db, "b3_auto", "lianqi_2");
      await db.insert(playerStageProgress).values([
        { playerId, stageSlug: "lianqi_1", unlockedAt: start, firstClearedAt: start, clearCount: 1 },
        { playerId, stageSlug: "lianqi_2", unlockedAt: start, firstClearedAt: null, clearCount: 0 },
      ]).onConflictDoNothing();
      await db.update(playerStates).set({ idleStageSlug: "lianqi_2" }).where(eq(playerStates.playerId, playerId));
      await monster("lianqi_2", { hp: 2, attack: 1, defense: 0 });
      at(3);
      const first = await state();
      expect(first.lastSettle.autoChallenge).toMatchObject({ stageSlug: "lianqi_2", tier: "elite", win: true, reward: { firstClear: true, spiritStones: 50 } });
      expect(first.stageAccess.find((row: { slug: string }) => row.slug === "lianqi_3")).toMatchObject({ unlocked: true, realmOk: false });
      at(6);
      expect((await state()).lastSettle.autoChallenge).toBeNull(); // 已经打过了
      await app.close();
    });
    await withDb(async (db) => {
      const { app, admin, state, at, monster, progress, playerId } = await boot(db, "b3_auto2", "lianqi_2");
      await db.insert(playerStageProgress).values([
        { playerId, stageSlug: "lianqi_1", unlockedAt: start, firstClearedAt: start, clearCount: 1 },
        { playerId, stageSlug: "lianqi_2", unlockedAt: start, firstClearedAt: null, clearCount: 0 },
      ]).onConflictDoNothing();
      await db.update(playerStates).set({ idleStageSlug: "lianqi_2" }).where(eq(playerStates.playerId, playerId));
      // 2) 门槛改成 1%，精英打不过：输了记下时间，60 秒内不再自动打
      await monster("lianqi_2", { hp: 3000, attack: 1, defense: 0 }); // 精英血很厚，20 秒打不完
      expect((await app.inject({ method: "PUT", url: "/admin/draft/boss-rules", headers: admin, payload: { autoChallengePowerPct: 1 } })).statusCode).toBe(200);
      at(3);
      const lost = await state();
      expect(lost.lastSettle.autoChallenge).toMatchObject({ stageSlug: "lianqi_2", win: false });
      expect((await progress("lianqi_2"))?.autoChallengeAt?.getTime()).toBe(start.getTime() + 3000);
      for (const seconds of [10, 20, 30, 40, 50, 60]) {
        at(seconds);
        expect((await state()).lastSettle.autoChallenge).toBeNull();
      }
      at(63);
      expect((await state()).lastSettle.autoChallenge).toMatchObject({ win: false });
      // 3) 关掉自动挑战：不再打
      expect((await app.inject({ method: "PUT", url: "/admin/draft/boss-rules", headers: admin, payload: { autoChallenge: false } })).statusCode).toBe(200);
      at(140);
      at(150);
      expect((await state()).lastSettle.autoChallenge).toBeNull();
      await app.close();
    });
  });
});

describe("第三批：首领装备走统一发放接口 grantEquipment", () => {
  it("elite first-clear gear is one boss_first grant (requestId = battle id + index, sourceRef = stage); replaying the same request grants nothing new", async () => {
    await withDb(async (db) => {
      const { app, headers, playerId, monster, progress } = await boot(db, "b3_grant");
      await monster("lianqi_1", { hp: 2, attack: 1, defense: 0 });
      const before = await progress("lianqi_1");
      const send = () => app.inject({ method: "POST", url: "/api/v1/me/stages/lianqi_1/challenge", headers: { ...headers, "idempotency-key": "b3-grant-replay-key-0001" }, payload: {} });
      const first = await send();
      expect(first.statusCode).toBe(200);
      const grants = await db.select().from(equipmentGrants).where(eq(equipmentGrants.playerId, playerId));
      expect(grants).toHaveLength(1);
      expect(grants[0]).toMatchObject({ source: "boss_first", sourceRef: "lianqi_1", itemSlug: "gear_major1_weapon_green", count: 1, requestId: `${bossBattleId(playerId, "lianqi_1", before!)}:0` });
      expect(grants[0]!.instanceIds).toHaveLength(1);
      const [instance] = await db.select().from(playerItems).where(eq(playerItems.id, grants[0]!.instanceIds[0]!));
      expect(instance).toMatchObject({ itemSlug: "gear_major1_weapon_green", source: "boss_first", isStack: false });
      // 同一个请求重放：返回同样的结果，不再发
      const replay = await send();
      expect(replay.json()).toEqual(first.json());
      expect(await db.select().from(equipmentGrants).where(eq(equipmentGrants.playerId, playerId))).toHaveLength(1);
      expect((await db.select().from(playerItems).where(eq(playerItems.playerId, playerId))).filter((row) => row.itemSlug.startsWith("gear_"))).toHaveLength(1);
      // 同一场胜利（同一个战斗报告 id + 序号）再调一次发放：返回原来的实例，不重复发
      const again = await withTransaction(db, (tx) => grantBossEquipment(tx, { playerId, itemSlug: "gear_major1_weapon_green", count: 1, source: "boss_first", stageSlug: "lianqi_1", battleId: bossBattleId(playerId, "lianqi_1", before!), index: 0 }));
      expect(again).toEqual({ count: grants[0]!.instanceIds.length, skipped: null });
      expect(await db.select().from(equipmentGrants)).toHaveLength(1);
      await app.close();
    });
  });

  it("after the admin wipes the player's progress the next first clear is a new battle id (no GRANT_REQUEST_CONFLICT)", async () => {
    await withDb(async (db) => {
      const { app, playerId, challenge, monster, at } = await boot(db, "b3_regrant");
      await monster("lianqi_1", { hp: 2, attack: 1, defense: 0 });
      expect((await challenge("lianqi_1")).statusCode).toBe(200);
      // 清空玩家（player/service.ts resetPlayer）会删进度记录；重新解锁时间不同
      await db.delete(playerStageProgress).where(eq(playerStageProgress.playerId, playerId));
      at(5);
      await db.insert(playerStageProgress).values({ playerId, stageSlug: "lianqi_1", unlockedAt: new Date(start.getTime() + 5000) });
      await db.update(contentStages).set({ recommendedPower: 1_000_000 }).where(eq(contentStages.slug, "lianqi_1")); // 不让结算里自动打
      const again = await challenge("lianqi_1");
      expect(again.statusCode).toBe(200);
      expect(again.json().reward.firstClear).toBe(true);
      // 只看首领首通的装备流水（批次②之后挂机掉落、新手物品也记流水）
      const grants = (await db.select().from(equipmentGrants).where(eq(equipmentGrants.playerId, playerId))).filter((row) => row.source === "boss_first");
      expect(grants).toHaveLength(2);
      expect(new Set(grants.map((row) => row.requestId)).size).toBe(2);
      await app.close();
    });
  });
});

describe("第三批后台接口", () => {
  it("chapters CRUD: list with the effective chief, create with defaults, bgKey / bossFx validated, delete refused while stages belong to it", async () => {
    await withDb(async (db) => {
      const { app, admin } = await boot(db, "b3_ch");
      const list = (await app.inject({ method: "GET", url: "/admin/draft/chapters", headers: admin })).json();
      expect(list.map((row: { id: string; effectiveChiefStageSlug: string; bossFx: string }) => [row.id, row.effectiveChiefStageSlug, row.bossFx])).toEqual([
        ["heifeng", "lianqi_3", "default"],
        ["youming", "zhuji_3", "default"],
        ["chiyan", "jindan_3", "chiyan"],
        ["zixiao", "yuanying_3", "default"],
        ["shenyou", "huashen_3", "default"],
        ["taixu", "lianxu_3", "default"],
        ["hedao", "heti_3", "chiyan"],
        ["daluo", "dacheng_3", "default"],
      ]);
      expect(list[0].stages.map((row: { id: string; chief: boolean }) => [row.id, row.chief])).toEqual([
        ["lianqi_1", false],
        ["lianqi_2", false],
        ["lianqi_3", true],
      ]);
      const post = (payload: Record<string, unknown>) => app.inject({ method: "POST", url: "/admin/draft/chapters", headers: admin, payload });
      expect((await post({ displayName: "新章", bgKey: "nope" })).statusCode).toBe(400);
      expect((await post({ displayName: "新章", bgKey: "heifeng", bossFx: "ice" })).statusCode).toBe(400);
      expect((await post({ displayName: "", bgKey: "heifeng" })).statusCode).toBe(400);
      const created = await post({ slug: "xinzhang", displayName: "新章", bgKey: "youming" });
      expect(created.statusCode).toBe(200);
      const after = (await app.inject({ method: "GET", url: "/admin/draft/chapters", headers: admin })).json();
      expect(after[8]).toMatchObject({ id: "xinzhang", sortOrder: 9, bossFx: "default", chiefStageSlug: null, effectiveChiefStageSlug: null, enabled: true });
      expect((await post({ slug: "xinzhang", displayName: "重复", bgKey: "youming" })).statusCode).toBe(400);
      // 关卡可以挪到新章（ops 关卡接口的 chapterSlug）
      const moved = await app.inject({ method: "PUT", url: "/admin/draft/stages/jindan_3", headers: admin, payload: { displayName: "赤炎火山·三", realmCode: 9, chapterSlug: "xinzhang" } });
      expect(moved.statusCode).toBe(200);
      expect((await app.inject({ method: "DELETE", url: "/admin/draft/chapters/xinzhang", headers: admin })).statusCode).toBe(400);
      expect((await app.inject({ method: "PUT", url: "/admin/draft/stages/jindan_3", headers: admin, payload: { displayName: "赤炎火山·三", realmCode: 9, chapterSlug: "chiyan" } })).statusCode).toBe(200);
      expect((await app.inject({ method: "DELETE", url: "/admin/draft/chapters/xinzhang", headers: admin })).statusCode).toBe(200);
      // 挪关卡没有把顺序清零（以前的 bug）
      const [stage] = await db.select().from(contentStages).where(eq(contentStages.slug, "jindan_3"));
      expect(stage?.sortOrder).toBe(9);
      await app.close();
    });
  });

  it("boss rules: GET returns the one rule set + usage; PUT merges and validates; per-stage override via the stage API and reset-boss-rule", async () => {
    await withDb(async (db) => {
      const { app, admin } = await boot(db, "b3_rules");
      const read = (await app.inject({ method: "GET", url: "/admin/draft/boss-rules", headers: admin })).json();
      expect(read.rules.dailyChallengeTotal).toBe(5);
      expect(read.rules.idleSpawnWaves).toBe(1000);
      // 原章末 3 关存了「属性 = 手填」
      expect(read.usage).toMatchObject({ stages: 24, customized: 9 }); // 8 章末手填 + 炼气首关手填/关自动挑战
      const put = (payload: Record<string, unknown>) => app.inject({ method: "PUT", url: "/admin/draft/boss-rules", headers: admin, payload });
      const saved = await put({ dailyChallengeTotal: 3, idleSpawnCountsDaily: true, repeatGearQualityPct: { green: 48, orange: 4 } });
      expect(saved.statusCode).toBe(200);
      expect(saved.json().rules).toMatchObject({ dailyChallengeTotal: 3, idleSpawnCountsDaily: true, repeatGearQualityPct: { white: 0, green: 48, blue: 35, purple: 13, orange: 4 } });
      expect(saved.json().rules.statMul).toEqual({ hp: 6.5, attack: 1.55, defense: 1.4 });
      const bad = await put({ gearQualityPct: { green: 90 } });
      expect(bad.statusCode).toBe(400);
      expect(bad.json().error.message).toContain("100%");
      // 单关覆盖：用仍走自动倍率的炼气二关（首关已是手填教学关）
      const stages = (await app.inject({ method: "GET", url: "/admin/draft/stages", headers: admin })).json();
      const foxStage = stages.find((row: { id: string }) => row.id === "lianqi_2");
      const boss = { ...foxStage.bosses[0], rules: { autoChallenge: false, statMul: { hp: 6, attack: 1.3 }, idleSpawnWaves: 300 } };
      const updated = await app.inject({ method: "PUT", url: "/admin/draft/stages/lianqi_2", headers: admin, payload: { displayName: foxStage.displayName, realmCode: 2, bosses: [boss] } });
      expect(updated.statusCode).toBe(200);
      let world = await loadDraftSnapshot(db);
      let elite = world.stages.find((row) => row.slug === "lianqi_2")!.bosses![0]!;
      expect(elite.ruleOverride).toEqual({ autoChallenge: false, statMul: { hp: 6, attack: 1.3 }, idleSpawnWaves: 300 });
      expect(elite).toMatchObject({ hp: 750, attack: 42 }); // 125×6 / 32×1.3
      expect(elite.rules).toMatchObject({ idleSpawnWaves: 300, idleSpawnCountsDaily: true });
      expect((await app.inject({ method: "GET", url: "/admin/draft/boss-rules", headers: admin })).json().usage).toMatchObject({ customized: 10 }); // 原 9 + 本关
      expect((await app.inject({ method: "GET", url: "/admin/draft/boss-rules", headers: admin })).json().usage.customizedStages).toContainEqual({ id: "lianqi_2", displayName: foxStage.displayName, customCount: 4 });
      // 只恢复一项
      const partial = await app.inject({ method: "POST", url: "/admin/draft/stages/lianqi_2/reset-boss-rule", headers: admin, payload: { keys: ["statMul"] } });
      expect(partial.json()).toEqual({ id: "lianqi_2", ruleOverride: { autoChallenge: false, idleSpawnWaves: 300 } });
      expect((await app.inject({ method: "POST", url: "/admin/draft/stages/lianqi_2/reset-boss-rule", headers: admin, payload: { keys: ["nope"] } })).statusCode).toBe(400);
      // 全部恢复
      const all = await app.inject({ method: "POST", url: "/admin/draft/stages/lianqi_2/reset-boss-rule", headers: admin, payload: {} });
      expect(all.json()).toEqual({ id: "lianqi_2", ruleOverride: null });
      world = await loadDraftSnapshot(db);
      elite = world.stages.find((row) => row.slug === "lianqi_2")!.bosses![0]!;
      expect(elite.ruleOverride ?? null).toBeNull();
      expect(elite.hp).toBe(813); // 125×6.5
      await app.close();
    });
  });

  it("art keys: the dropdown lists 12 monster sprites, 3 chapter backgrounds and 2 boss fx; admin only", async () => {
    await withDb(async (db) => {
      const { app, admin, headers } = await boot(db, "b3_art");
      const body = (await app.inject({ method: "GET", url: "/admin/draft/art-keys", headers: admin })).json();
      expect(body.monsters).toHaveLength(12);
      expect(body.monsters[0]).toEqual({ key: "wolf", name: "青鬃狼", sprite: "sprites/mon_wolf.png" });
      expect(body.chapterBackgrounds.map((row: { key: string }) => row.key)).toEqual(["heifeng", "youming", "chiyan"]);
      // 第四批：统一首领立绘 9 张、章节战斗背景 3 张
      expect(body.bosses.map((row: { key: string }) => row.key)).toHaveLength(9);
      expect(body.bosses[0]).toEqual({ key: "boss_wolf", name: "首领·青鬃狼", sprite: "sprites/boss_wolf.png" });
      expect(body.battleBackgrounds.map((row: { image: string }) => row.image)).toEqual(["bg/bg_battle_heifeng_1080x1640.webp", "bg/bg_battle_youming_1080x1640.webp", "bg/bg_battle_chiyan_1080x1640.webp"]);
      expect(body.bossFx.map((row: { key: string }) => row.key)).toEqual(["default", "chiyan"]);
      expect((await app.inject({ method: "GET", url: "/admin/draft/art-keys", headers })).statusCode).toBeGreaterThanOrEqual(401);
      await app.close();
    });
  });
});
