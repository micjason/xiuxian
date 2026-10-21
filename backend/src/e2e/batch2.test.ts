/* eslint-disable @typescript-eslint/no-explicit-any */
import { randomUUID } from "node:crypto";
import { and, eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentGearSets, contentGlobals, contentItems, contentRealms, contentStages, equipmentGrants, playerItems, players, playerSkills } from "../db/schema.js";
import { createAdmin } from "../modules/auth/service.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { listGear, syncGear } from "../modules/content/gear.js";
import { loadCurrentWorld } from "../modules/content/snapshot.js";
import { combatStats, explainPlayerPower } from "../modules/loop/actions.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-21T03:00:00.000Z");
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

async function boot(db: TestDb, opts: { chance?: number } = {}) {
  await applyPrototypeV12(db);
  let clock = start;
  const control = { chance: opts.chance ?? 9999 };
  const randomInt = (_min: number, max: number) => (max === 10000 ? control.chance : 0);
  const app = await buildApp(db, () => clock, { randomInt });
  await createAdmin(db, { username: "owner_b2", password: "correct-horse-battery" });
  const login = await app.inject({ method: "POST", url: "/api/v1/admin/auth/login", payload: { username: "owner_b2", password: "correct-horse-battery" } });
  const admin = { authorization: `Bearer ${login.json().token as string}` };
  const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "b2_player", password: "correct-horse" } });
  const headers = { authorization: `Bearer ${registered.json().token as string}` };
  const [player] = await db.select().from(players).where(eq(players.usernameLower, "b2_player"));
  const call = async (method: "GET" | "POST" | "PUT" | "DELETE", url: string, payload?: unknown, as = admin) => {
    const extra = as !== admin && method === "POST" ? { "idempotency-key": randomUUID() } : {};
    const res = await app.inject({ method, url: `/api/v1${url}`, headers: { ...as, ...extra }, ...(payload === undefined ? {} : { payload: payload as any }) });
    return { status: res.statusCode, body: res.json() as any };
  };
  const at = (seconds: number) => {
    clock = new Date(start.getTime() + seconds * 1000);
  };
  return { app, admin, headers, playerId: player!.id, call, at, control };
}

const firstOrder = 1;

async function makeSet(call: Awaited<ReturnType<typeof boot>>["call"]) {
  const blade = await call("POST", "/admin/draft/gear/manual", { displayName: "青云剑", iconKey: "eq_sword_qingyun", slot: "weapon", quality: "purple", requiredRealmOrder: firstOrder, attack: 40 });
  const crown = await call("POST", "/admin/draft/gear/manual", { displayName: "青云冠", iconKey: "eq_helmet_qingyun", slot: "helmet", quality: "purple", requiredRealmOrder: firstOrder, defense: 10, hp: 60 });
  expect(blade.status).toBe(200);
  expect(crown.status).toBe(200);
  const set = await call("POST", "/admin/draft/gear-sets", {
    slug: "set_qingyun",
    displayName: "青云套",
    tiers: [
      { pieces: 2, stats: [{ stat: "attack", mode: "pct", value: 10 }, { stat: "hp", mode: "flat", value: 100 }] },
      { pieces: 4, stats: [{ stat: "defense", mode: "pct", value: 20 }] },
    ],
    members: [blade.body.id, crown.body.id],
  });
  expect(set.status).toBe(200);
  return { blade: blade.body.id as string, crown: crown.body.id as string };
}

describe("batch ② manual gear", () => {
  it("creates gear_m_0001…, default off random drop, survives formula regeneration, validates input", async () => {
    await withDb(async (db) => {
      const { call } = await boot(db);
      const first = await call("POST", "/admin/draft/gear/manual", { displayName: "青云剑", iconKey: "eq_sword_qingyun", slot: "weapon", quality: "purple", requiredRealmOrder: firstOrder, attack: 40, description: "演示" });
      const second = await call("POST", "/admin/draft/gear/manual", { displayName: "青云冠", iconKey: "eq_helmet_qingyun", slot: "helmet", quality: "blue", requiredRealmOrder: firstOrder, hp: 50, randomDrop: true, dropMult: 2 });
      expect([first.body.id, second.body.id]).toEqual(["gear_m_0001", "gear_m_0002"]);
      const [row] = await db.select().from(contentItems).where(eq(contentItems.slug, "gear_m_0001"));
      expect(row).toMatchObject({ origin: "manual", kind: "equipment", stackable: false, randomDrop: false, attack: 40, quality: "purple", iconKey: "eq_sword_qingyun", description: "演示" });
      // 重新生成 90 件公式装备不碰手动装备
      await syncGear(db, null);
      const [after] = await db.select().from(contentItems).where(eq(contentItems.slug, "gear_m_0001"));
      expect(after).toMatchObject({ attack: 40, displayName: "青云剑" });
      // 装备配置页：90 件公式 + 手动列表
      const gear = await listGear(db);
      expect(gear.manual.map((item: any) => item.id)).toEqual(["gear_m_0001", "gear_m_0002"]);
      expect(gear.manual[1]).toMatchObject({ randomDrop: true, dropMult: 2 });
      expect(gear.nextManualId).toBe("gear_m_0003");
      // 校验
      expect((await call("POST", "/admin/draft/gear/manual", { displayName: "", iconKey: "x", slot: "weapon", quality: "white", requiredRealmOrder: 1, attack: 1 })).status).toBe(400);
      expect((await call("POST", "/admin/draft/gear/manual", { displayName: "红", iconKey: "x", slot: "weapon", quality: "red", requiredRealmOrder: 1, attack: 1 })).status).toBe(400);
      expect((await call("POST", "/admin/draft/gear/manual", { displayName: "空", iconKey: "x", slot: "weapon", quality: "white", requiredRealmOrder: 1 })).status).toBe(400);
      expect((await call("POST", "/admin/draft/gear/manual", { displayName: "x", iconKey: "x", slot: "ring", quality: "white", requiredRealmOrder: 1, attack: 1 })).status).toBe(400);
      // 修改
      const updated = await call("PUT", "/admin/draft/gear/manual/gear_m_0001", { displayName: "青云剑·改", iconKey: "eq_sword_qingyun", slot: "weapon", quality: "orange", requiredRealmOrder: firstOrder, attack: 55 });
      expect(updated.status).toBe(200);
      const [edited] = await db.select().from(contentItems).where(eq(contentItems.slug, "gear_m_0001"));
      expect(edited).toMatchObject({ displayName: "青云剑·改", quality: "orange", attack: 55 });
      expect((await call("PUT", "/admin/draft/gear/manual/gear_major1_weapon_white", { displayName: "x", iconKey: "x", slot: "weapon", quality: "white", requiredRealmOrder: 1, attack: 1 })).status).toBe(404);
    });
  });

  it("random-drop switch: only manual gear switched on joins the major × quality random pool", async () => {
    await withDb(async (db) => {
      const { call } = await boot(db);
      await call("POST", "/admin/draft/gear/manual", { displayName: "关", iconKey: "eq_a", slot: "weapon", quality: "white", requiredRealmOrder: firstOrder, attack: 3 });
      await call("POST", "/admin/draft/gear/manual", { displayName: "开", iconKey: "eq_b", slot: "weapon", quality: "white", requiredRealmOrder: firstOrder, attack: 3, randomDrop: true, dropMult: 5 });
      const world = (await loadCurrentWorld(db))!;
      const { dropMultsOf } = await import("../modules/content/monster-drops.js");
      const mults = dropMultsOf(world.items, world.realms);
      const pool = mults.manual?.(world.realms.find((row) => row.sortOrder === firstOrder)!.majorKey!, "white") ?? [];
      expect(pool.map((row: any) => row.slug)).toEqual(["gear_m_0002"]);
    });
  });
});

describe("batch ② sets", () => {
  it("set rules: manual only, one per slot, same major, members exclusive; delete clears membership", async () => {
    await withDb(async (db) => {
      const { call } = await boot(db);
      const { blade, crown } = await makeSet(call);
      const members = await db.select().from(contentItems).where(eq(contentItems.setSlug, "set_qingyun"));
      expect(members.map((row) => row.slug).sort()).toEqual([blade, crown].sort());
      // 公式装备不能进套装
      const formula = await call("PUT", "/admin/draft/gear-sets/set_qingyun", { displayName: "青云套", tiers: [{ pieces: 2, stats: [{ stat: "attack", mode: "pct", value: 5 }] }], members: [blade, "gear_major1_clothes_white"] });
      expect(formula.status).toBe(400);
      expect(formula.body.error.message).toContain("公式装备");
      // 同部位重复
      const blade2 = (await call("POST", "/admin/draft/gear/manual", { displayName: "青云剑二", iconKey: "eq_x", slot: "weapon", quality: "purple", requiredRealmOrder: firstOrder, attack: 1 })).body.id;
      expect((await call("PUT", "/admin/draft/gear-sets/set_qingyun", { displayName: "青云套", tiers: [{ pieces: 2, stats: [{ stat: "attack", mode: "pct", value: 5 }] }], members: [blade, blade2] })).status).toBe(400);
      // 不同大境界
      const zhuji = await db.select().from(contentRealms).where(eq(contentRealms.slug, "zhuji_1"));
      const boots = (await call("POST", "/admin/draft/gear/manual", { displayName: "筑基靴", iconKey: "eq_y", slot: "shoes", quality: "purple", requiredRealmOrder: zhuji[0]!.sortOrder, speed: 3 })).body.id;
      const mixed = await call("PUT", "/admin/draft/gear-sets/set_qingyun", { displayName: "青云套", tiers: [{ pieces: 2, stats: [{ stat: "attack", mode: "pct", value: 5 }] }], members: [blade, boots] });
      expect(mixed.status).toBe(400);
      expect(mixed.body.error.message).toContain("大境界");
      // 档位校验
      expect((await call("POST", "/admin/draft/gear-sets", { displayName: "坏", tiers: [{ pieces: 1, stats: [{ stat: "attack", mode: "pct", value: 5 }] }] })).status).toBe(400);
      expect((await call("POST", "/admin/draft/gear-sets", { displayName: "坏", tiers: [{ pieces: 2, stats: [{ stat: "attack", mode: "pct", value: 5 }] }, { pieces: 2, stats: [{ stat: "hp", mode: "flat", value: 5 }] }] })).status).toBe(400);
      // 已经在别的套装里
      const other = await call("POST", "/admin/draft/gear-sets", { displayName: "别的", tiers: [{ pieces: 2, stats: [{ stat: "attack", mode: "pct", value: 5 }] }], members: [crown] });
      expect(other.status).toBe(400);
      // 列表
      const gear = await listGear(db);
      expect(gear.sets[0]).toMatchObject({ id: "set_qingyun", displayName: "青云套", quality: "purple" });
      expect(gear.sets[0].members).toHaveLength(2);
      // 删除
      expect((await call("DELETE", "/admin/draft/gear-sets/set_qingyun")).status).toBe(200);
      expect(await db.select().from(contentItems).where(eq(contentItems.setSlug, "set_qingyun"))).toEqual([]);
      expect(await db.select().from(contentGearSets)).toEqual([]);
    });
  });

  it("set bonus counts in battle stats and power (pct on total stats, then flat), and shows as a 套装 line in the power breakdown", async () => {
    await withDb(async (db) => {
      const { call, headers, playerId } = await boot(db);
      const { blade, crown } = await makeSet(call);
      const world = (await loadCurrentWorld(db))!;
      const one = combatStats(world, "lianqi_1", [blade], []);
      const two = combatStats(world, "lianqi_1", [blade, crown], []);
      const base = combatStats(world, "lianqi_1", [], []);
      // 2 件：攻击 +10%（按总攻击），气血 +100 固定
      expect(two.attack).toBeCloseTo((base.attack + 40) * 1.1, 6);
      expect(two.hp).toBeCloseTo(base.hp + 60 + 100, 6);
      expect(two.defense).toBeCloseTo(base.defense + 10, 6); // 4 件档没生效
      expect(one.attack).toBeCloseTo(base.attack + 40, 6);
      expect(two.power).toBeGreaterThan(combatStats(world, "lianqi_1", [blade], []).power);

      // 发给玩家、穿上：/me/state 的属性 / 战力带上套装；activeSets 显示 2 件、2 件档生效
      for (const itemId of [blade, crown]) {
        const res = await call("POST", "/admin/grants", { playerId, itemId, count: 1, reason: "测试", requestId: randomUUID() });
        expect(res.status).toBe(200);
      }
      const bag = await db.select().from(playerItems).where(eq(playerItems.playerId, playerId));
      for (const row of bag.filter((item) => item.itemSlug === blade || item.itemSlug === crown)) {
        const equipped = await call("POST", `/me/items/${row.id}/equip`, {}, headers);
        expect(JSON.stringify(equipped.body.error ?? null)).toBe("null");
      }
      const state = (await call("GET", "/me/state", undefined, headers)).body;
      expect(state.attack).toBeCloseTo(two.attack, 6);
      expect(state.power).toBe(two.power);
      expect(state.activeSets).toEqual([{ setSlug: "set_qingyun", displayName: "青云套", worn: 2, activePieces: [2] }]);
      const items = await db.select().from(playerItems).where(eq(playerItems.playerId, playerId));
      const explained = explainPlayerPower(world, "lianqi_1", items, []);
      expect(explained.power).toBe(two.power);
      expect(explained.lines.some((line) => line.group === "套装")).toBe(true);
      // /content/current 带套装定义、部位表、品质表（白→橙 5 档，没有红）
      const content = (await call("GET", "/content/current", undefined, headers)).body;
      expect(content.gearSets[0]).toMatchObject({ slug: "set_qingyun", displayName: "青云套" });
      expect(content.globals.qualities.map((row: any) => row.key)).toEqual(["white", "green", "blue", "purple", "orange"]);
      expect(content.globals.slots.map((row: any) => row.key)).toHaveLength(6);
      expect(content.items.find((row: any) => row.slug === blade)).toMatchObject({ origin: "manual", setSlug: "set_qingyun", randomDrop: false });
    });
  });
});

describe("batch ② designated drops", () => {
  it("a stage's designated monster drop rolls per kill on top of random drops and goes through grantEquipment (stage_drop)", async () => {
    await withDb(async (db) => {
      const { call, headers, playerId, at } = await boot(db, { chance: 9999 });
      const blade = (await call("POST", "/admin/draft/gear/manual", { displayName: "指定剑", iconKey: "eq_z", slot: "weapon", quality: "blue", requiredRealmOrder: firstOrder, attack: 5 })).body.id;
      // 后台关卡抽屉保存指定掉落
      const stageRes = await call("GET", "/admin/draft/stages");
      const stage = (stageRes.body.items ?? stageRes.body).find((row: any) => row.id === "lianqi_1");
      const saved = await call("PUT", "/admin/draft/stages/lianqi_1", { ...stage, designatedDrops: [{ itemId: blade, trigger: "monster", chancePercent: 100, count: 1 }] });
      expect(saved.status).toBe(200);
      const [row] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_1"));
      expect(row!.designatedDrops).toEqual([{ itemSlug: blade, trigger: "monster", chanceBp: 10000, count: 1 }]);
      // 保存关卡不会清掉顺序 / 下一关
      expect(row!.sortOrder).toBeGreaterThan(0);
      expect(row!.nextStageSlug).toBe("lianqi_2");
      // 普通掉落 9999 ≥ 500 不掉；指定掉落 100% → 每只怪 1 件
      // 前台在线：每 5 秒轮询一次
      let kills = 0;
      const drops: any[] = [];
      for (let seconds = 5; seconds <= 30; seconds += 5) {
        at(seconds);
        const state = (await call("GET", "/me/state", undefined, headers)).body;
        kills += state.lastSettle.kills;
        drops.push(...state.lastSettle.drops);
      }
      expect(kills).toBeGreaterThan(0);
      const state = { lastSettle: { kills } };
      expect(drops.every((drop: any) => drop.itemSlug === blade && drop.designated === true)).toBe(true);
      const bag = await db.select().from(playerItems).where(and(eq(playerItems.playerId, playerId), eq(playerItems.itemSlug, blade)));
      expect(bag.length).toBe(state.lastSettle.kills);
      const grants = await db.select().from(equipmentGrants).where(eq(equipmentGrants.playerId, playerId));
      expect(grants.length).toBe(state.lastSettle.kills);
      expect(grants.every((grant) => grant.source === "stage_drop" && grant.sourceRef === "lianqi_1")).toBe(true);
      // 用在指定掉落里的装备不能删
      expect((await call("DELETE", `/admin/draft/items/${blade}`)).status).toBe(400);
      // 校验
      expect((await call("PUT", "/admin/draft/stages/lianqi_1", { ...stage, designatedDrops: [{ itemId: "enh_stone_low", trigger: "monster", chancePercent: 5, count: 1 }] })).status).toBe(400);
      expect((await call("PUT", "/admin/draft/stages/lianqi_1", { ...stage, designatedDrops: [{ itemId: blade, trigger: "monster", chancePercent: 0, count: 1 }] })).status).toBe(400);
    });
  });
});

describe("batch ② admin reissue", () => {
  it("grants via admin_grant, is idempotent on the request id, needs a reason, and the log filters by source", async () => {
    await withDb(async (db) => {
      const { call, playerId, app } = await boot(db);
      const found = await call("GET", "/admin/grants/players?q=b2_");
      expect(found.body[0]).toMatchObject({ id: playerId, username: "b2_player" });
      const requestId = randomUUID();
      const input = { playerId, itemId: "gear_major1_weapon_purple", count: 2, reason: "补偿 · 服务器故障", note: "工单 7", requestId };
      const first = await call("POST", "/admin/grants", input);
      expect(first.status).toBe(200);
      expect(first.body.granted).toHaveLength(2);
      const again = await call("POST", "/admin/grants", input);
      expect(again.body.granted.map((row: any) => row.id)).toEqual(first.body.granted.map((row: any) => row.id));
      expect(await db.select().from(playerItems).where(eq(playerItems.playerId, playerId))).toHaveLength(2);
      expect((await call("POST", "/admin/grants", { ...input, count: 3 })).status).toBe(409);
      expect((await call("POST", "/admin/grants", { ...input, requestId: randomUUID(), reason: "" })).status).toBe(400);
      expect((await call("POST", "/admin/grants", { ...input, requestId: randomUUID(), itemId: "enh_stone_low" })).status).toBe(400);
      expect((await call("POST", "/admin/grants", { ...input, requestId: randomUUID(), count: 21 })).status).toBe(400);
      const log = await call("GET", "/admin/grants?source=admin_grant");
      expect(log.body.total).toBe(1);
      expect(log.body.rows[0]).toMatchObject({ username: "b2_player", itemSlug: "gear_major1_weapon_purple", count: 2, source: "admin_grant", operator: "owner_b2", reason: "补偿 · 服务器故障", note: "工单 7" });
      expect((await call("GET", "/admin/grants?source=stage_drop")).body.total).toBe(0);
      expect((await call("GET", "/admin/grants?source=nope")).status).toBe(400);

      // 补发抽屉：多人 × 多件，一个补发单号；重复提交不多发；备注必填
      await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "b2_other", password: "correct-horse" } });
      const [other] = await db.select().from(players).where(eq(players.usernameLower, "b2_other"));
      const batch = { playerIds: [playerId, other!.id], items: [{ itemId: "gear_major1_weapon_blue", count: 1 }, { itemId: "gear_major1_helmet_blue", count: 2 }], reason: "补偿 · 奖励未到账", note: "工单 #2031", batchId: "batch_test_0001" };
      const sent = await call("POST", "/admin/grants/batch", batch);
      expect(sent.body).toMatchObject({ players: 2, granted: 6 });
      await call("POST", "/admin/grants/batch", batch);
      expect(await db.select().from(playerItems).where(eq(playerItems.playerId, other!.id))).toHaveLength(3);
      const batchLog = await call("GET", "/admin/grants?source=admin_grant");
      expect(batchLog.body.total).toBe(5);
      expect(batchLog.body.rows.filter((row: any) => row.sourceRef === "batch_test_0001")).toHaveLength(4);
      expect((await call("POST", "/admin/grants/batch", { ...batch, batchId: "batch_test_0002", note: "" })).status).toBe(400);
      expect((await call("POST", "/admin/grants/batch", { ...batch, batchId: "batch_test_0003", playerIds: [randomUUID()] })).status).toBe(400);
    });
  });
});

describe("batch ② config overview: newbie + skill slots", () => {
  it("saves starting realm and starter items; new players get them", async () => {
    await withDb(async (db) => {
      const { call, app } = await boot(db);
      const saved = await call("PUT", "/admin/draft/config-overview", { newbie: { startingRealmSlug: "lianqi_2", starterItems: [{ itemSlug: "gear_major1_weapon_white", quantity: 1 }, { itemSlug: "enh_stone_low", quantity: 5 }] } });
      expect(saved.status).toBe(200);
      expect(saved.body.newbie).toMatchObject({ startingRealmSlug: "lianqi_2", starterItems: [{ itemSlug: "gear_major1_weapon_white", quantity: 1 }, { itemSlug: "enh_stone_low", quantity: 5 }] });
      expect((await call("PUT", "/admin/draft/config-overview", { newbie: { startingRealmSlug: "nope" } })).status).toBe(400);
      expect((await call("PUT", "/admin/draft/config-overview", { newbie: { starterItems: [{ itemSlug: "nope", quantity: 1 }] } })).status).toBe(400);
      expect((await call("PUT", "/admin/draft/config-overview", { newbie: { starterItems: [{ itemSlug: "enh_stone_low", quantity: 0 }] } })).status).toBe(400);
      const res = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "newbie_b2", password: "correct-horse" } });
      const headers = { authorization: `Bearer ${res.json().token as string}` };
      const state = (await call("GET", "/me/state", undefined, headers)).body;
      expect(state.realmSlug).toBe("lianqi_2");
      const [player] = await db.select().from(players).where(eq(players.usernameLower, "newbie_b2"));
      const bag = await db.select().from(playerItems).where(eq(playerItems.playerId, player!.id));
      expect(bag.find((row) => row.itemSlug === "gear_major1_weapon_white")).toBeTruthy();
      expect(bag.find((row) => row.itemSlug === "enh_stone_low")?.quantity).toBe(5);
    });
  });

  it("skill slots open by realm: configurable rules, the server enforces the open count, extra running skills stop counting", async () => {
    await withDb(async (db) => {
      const { call, headers, playerId } = await boot(db);
      const before = (await call("GET", "/admin/draft/config-overview")).body;
      expect(before.skillSlots.rules).toEqual([{ minRealmOrder: 0, slots: 3 }]);
      // 炼气一层 1 个、筑基一层 2 个、金丹一层 3 个
      const orders = Object.fromEntries((await db.select().from(contentRealms)).map((row) => [row.slug, row.sortOrder]));
      const rules = [{ minRealmOrder: orders.lianqi_1, slots: 1 }, { minRealmOrder: orders.zhuji_1, slots: 2 }, { minRealmOrder: orders.jindan_1, slots: 3 }];
      const saved = await call("PUT", "/admin/draft/config-overview", { skillSlots: { rules } });
      expect(saved.status).toBe(200);
      expect(saved.body.skillSlots.rules).toEqual(rules);
      expect((await call("PUT", "/admin/draft/config-overview", { skillSlots: { rules: [{ minRealmOrder: orders.lianqi_1, slots: 2 }, { minRealmOrder: orders.zhuji_1, slots: 1 }] } })).status).toBe(400);
      expect((await call("PUT", "/admin/draft/config-overview", { skillSlots: { rules: [{ minRealmOrder: 999, slots: 1 }] } })).status).toBe(400);
      const state = (await call("GET", "/me/state", undefined, headers)).body;
      expect(state.skillSlots).toEqual({ open: 1, max: 3, next: { slots: 2, realmOrder: orders.zhuji_1, realmName: "筑基一层" } });
      // 学两门，第二门运转被拒
      await db.insert(playerSkills).values([
        { playerId, skillSlug: "skill_tuna", level: 1 },
        { playerId, skillSlug: "skill_qingyuan", level: 1 },
      ]);
      expect(JSON.stringify((await call("POST", "/me/skills/skill_tuna/run", { slot: "run_1" }, headers)).body.error ?? null)).toBe("null");
      const second = await call("POST", "/me/skills/skill_qingyuan/run", { slot: "run_2" }, headers);
      expect(second.status).toBe(409);
      expect(second.body.error.message).toContain("筑基一层");
      // 以前开在 run_2 的不算属性
      await db.update(playerSkills).set({ runningSlot: "run_2" }).where(and(eq(playerSkills.playerId, playerId), eq(playerSkills.skillSlug, "skill_qingyuan")));
      const world = (await loadCurrentWorld(db))!;
      const skills = await db.select().from(playerSkills).where(eq(playerSkills.playerId, playerId));
      const explained = explainPlayerPower(world, "lianqi_1", [], skills);
      expect(explained.lines.filter((line) => line.group === "功法" && line.note === "没有运转，不算战力")).toHaveLength(1);
      const [globals] = await db.select().from(contentGlobals);
      expect(globals!.artSlotRules).toEqual(rules);
    });
  });
});
