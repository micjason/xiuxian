// 后台演示用的假后端：不连数据库，数据放内存，格式与真实接口一致。
// 用途：截图、没有后端时点一遍页面流程。运行：npm run build && node mock/server.mjs  然后打开 http://127.0.0.1:5199 ，任意账号密码登录。
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const DIST = path.join(here, "..", "dist");
const PORT = Number(process.env.PORT ?? 5199);
const now = Date.now();
const iso = (msAgo) => new Date(now - msAgo).toISOString();
const clone = (value) => JSON.parse(JSON.stringify(value));
let seq = 100;
const uid = (p) => `${p}${++seq}`;

// ---------- 种子数据 ----------
const realmRows = [
  ["凡人", "凡人", 1, 5, 2, 360, 10, 8, 120, 10, 1.5],
  ["炼气初期", "炼气", 2, 5, 3.5, 1260, 14, 11, 180, 12, 1.5],
  ["炼气中期", "炼气", 3, 5, 6, 2880, 20, 15, 260, 14, 1.5],
  ["炼气后期", "炼气", 4, 5, 9, 6200, 28, 21, 360, 16, 1.5],
  ["筑基初期", "筑基", 5, 5, 14, 14000, 40, 30, 520, 18, 1.4],
  ["筑基中期", "筑基", 6, 5, 20, 31000, 56, 42, 740, 20, 1.4],
  ["筑基后期", "筑基", 7, 5, 28, 64000, 78, 58, 1020, 22, 1.4],
  ["金丹初期", "金丹", 8, 5, 40, 0, 110, 80, 1500, 25, null],
];
let realms = realmRows.map(([displayName, majorName, code, tickSeconds, gainPerTick, breakthroughCost, attack, defense, hp, speed, interval]) => ({ code, displayName, majorName, tickSeconds, gainPerTick, breakthroughCost, attack, defense, hp, speed, interval }));

const slots = ["武器", "头冠", "衣袍", "护手", "鞋履", "玉佩"];
const qualities = ["白", "绿", "蓝", "紫", "橙"];
const names = { 武器: "青锋", 头冠: "素木冠", 衣袍: "云纹袍", 护手: "银丝护手", 鞋履: "踏云靴", 玉佩: "凝玉佩" };
const suffix = ["·凡", "·良", "·精", "·珍", "·绝"];
const factor = [1, 1.15, 1.3, 1.5, 1.8];
const majors = ["炼气", "筑基"].map((majorName, mi) => ({
  majorName,
  majorKey: mi === 0 ? "qi" : "foundation",
  requiredRealmOrder: mi === 0 ? 2 : 5,
  pieces: slots.flatMap((slotName) =>
    qualities.map((qualityName, qi) => ({
      id: `${majorName}${slotName}${qualityName}`,
      displayName: `${mi === 1 ? "玄" : ""}${names[slotName]}${suffix[qi]}`,
      description: "",
      iconKey: "",
      slotName,
      qualityName,
      attack: slotName === "武器" ? Math.round((20 + mi * 30) * factor[qi]) : 0,
      defense: slotName === "衣袍" ? Math.round((16 + mi * 24) * factor[qi]) : Math.round(4 * factor[qi]),
      hp: Math.round((60 + mi * 90) * factor[qi]),
      speed: slotName === "鞋履" ? Math.round((4 + mi * 3) * factor[qi]) : 0,
      power: Math.round((120 + mi * 160) * factor[qi]),
    })),
  ),
}));
const STARTING_ENHANCE = {
  expBase: 60, expGrowth: 1.25, statGrowthBp: 600, refundBp: 8000,
  qualities: {
    white: { cap: 5, costMult: 1, decomposeExp: 30, breakthroughs: [] },
    green: { cap: 8, costMult: 1.1, decomposeExp: 60, breakthroughs: [{ level: 5, materials: [{ itemSlug: "enh_stone_low", count: 3 }] }] },
    blue: { cap: 10, costMult: 1.25, decomposeExp: 120, breakthroughs: [{ level: 5, materials: [{ itemSlug: "enh_stone_low", count: 5 }] }] },
    purple: { cap: 12, costMult: 1.4, decomposeExp: 240, breakthroughs: [{ level: 5, materials: [{ itemSlug: "enh_stone_low", count: 8 }] }, { level: 10, materials: [{ itemSlug: "enh_stone_mid", count: 3 }] }] },
    orange: { cap: 15, costMult: 1.6, decomposeExp: 480, breakthroughs: [{ level: 5, materials: [{ itemSlug: "enh_stone_low", count: 10 }] }, { level: 10, materials: [{ itemSlug: "enh_stone_mid", count: 6 }] }] },
    red: { cap: 18, costMult: 2, decomposeExp: 960, breakthroughs: [{ level: 5, materials: [{ itemSlug: "enh_stone_low", count: 15 }] }, { level: 10, materials: [{ itemSlug: "enh_stone_mid", count: 10 }] }, { level: 15, materials: [{ itemSlug: "enh_stone_high", count: 5 }] }] },
  },
};
const STARTING_MATERIALS = [
  { slug: "enh_stone_low", displayName: "突破石·下品" },
  { slug: "enh_stone_mid", displayName: "突破石·中品" },
  { slug: "enh_stone_high", displayName: "突破石·上品" },
];
let enhance = process.env.MOCK_NO_ENHANCE ? null : clone(STARTING_ENHANCE);
let factors = { white: 1, green: 1.15, blue: 1.3, purple: 1.5, orange: 1.8 };

let items = [
  { id: "i-qi", displayName: "聚气丹", description: "服用后获得少量修为" },
  { id: "i-back", displayName: "回灵丹", description: "恢复少量灵力" },
  { id: "i-stone", displayName: "灵石", description: "通用货币材料" },
  { id: "i-herb", displayName: "凝露草", description: "炼丹材料" },
  { id: "i-ore", displayName: "玄铁矿", description: "锻造材料" },
  { id: "i-break", displayName: "突破丹", description: "突破时提高成功率" },
  { id: "enh_stone_low", displayName: "突破石·下品", description: "装备强化到突破节点时消耗的材料。" },
  { id: "enh_stone_mid", displayName: "突破石·中品", description: "装备强化到较高突破节点时消耗的材料。" },
  { id: "enh_stone_high", displayName: "突破石·上品", description: "装备强化到高阶突破节点时消耗的材料。" },
];
let skillCategories = [{ id: "c1", displayName: "心法" }, { id: "c2", displayName: "剑诀" }, { id: "c3", displayName: "身法" }];
let skills = [
  { id: "k1", displayName: "养气诀", description: "基础吐纳心法", categoryId: "c1", categoryName: "心法", categoryMissing: false, attack: 5, defense: 0, hp: 40, speed: 0, cultivateBonus: 500 },
  { id: "k2", displayName: "青云剑诀", description: "入门剑法", categoryId: "c2", categoryName: "剑诀", categoryMissing: false, attack: 12, defense: 0, hp: 0, speed: 0, cultivateBonus: 0 },
  { id: "k3", displayName: "踏雪无痕", description: "轻身功夫", categoryId: "c3", categoryName: "身法", categoryMissing: false, attack: 0, defense: 0, hp: 0, speed: 6, cultivateBonus: 0 },
  { id: "k4", displayName: "金钟罩", description: "护体神功", categoryId: "c1", categoryName: "心法", categoryMissing: false, attack: 0, defense: 18, hp: 100, speed: 0, cultivateBonus: 0 },
];
const boss = (name, a, d, h, i, drops) => ({ name, attack: a, defense: d, hp: h, interval: i, drops });
let stages = [
  { id: "s1", displayName: "青岚山·枯木林", realmCode: 1, bosses: [boss("枯木妖", 30, 20, 1200, 1.5, [{ itemId: "i-qi", chancePercent: 60 }, { itemId: "炼气武器白", chancePercent: 15 }])] },
  { id: "s2", displayName: "青岚山·寒潭", realmCode: 2, bosses: [boss("寒潭蛟", 45, 30, 3600, 1.5, [{ itemId: "i-herb", chancePercent: 50 }, { itemId: "k2", chancePercent: 5 }])] },
  { id: "s3", displayName: "落霞谷", realmCode: 3, bosses: [boss("赤练蛇王", 70, 48, 6400, 1.4, [])] },
  { id: "s4", displayName: "黑风洞", realmCode: 5, bosses: [boss("黑风老妖", 120, 80, 14000, 1.3, [{ itemId: "i-ore", chancePercent: 40 }, { itemId: "筑基武器紫", chancePercent: 3 }])] },
  { id: "s9", displayName: "试炼塔（待配置）", realmCode: 99, bosses: [] },
];
let rules = {
  defenseConstant: 1, speedBase: 100, minInterval: 0.5, attackWeight: 4.7, defenseWeight: 1.6, hpWeight: 0.95, speedWeight: 2.6,
  challengeCooldownSeconds: 0, timeLimitSeconds: 20, recommendedPowerMargin: 1.05, bagCapacity: 100, offlineCapSeconds: 28800, idleKillCap: 200, minClientVersionCode: 20,
};
let puppets = [
  { id: "pp1", displayName: "炼气中期·青锋良", kind: "configured", kindName: "按配置", realmCode: 3, realmName: "炼气中期", realmMissing: false, weapons: [{ id: "炼气武器绿", displayName: "青锋·良" }], skills: [{ id: "k1", displayName: "养气诀" }], attack: 63, defense: 49, hp: 428, speed: 14, interval: 1.32, power: 1024, powerDetail: null, tendency: "均衡", tendencyNote: null, problem: null },
  { id: "pp2", displayName: "偏攻击标准人", kind: "manual", kindName: "手填", realmCode: null, realmName: "", realmMissing: false, weapons: [], skills: [], attack: 150, defense: 70, hp: 250, speed: 16, interval: 1.5, power: 1210, powerDetail: null, tendency: "偏攻击", tendencyNote: "攻击占比高于标准", problem: null },
];
const baseGlobals = { startingRealmSlug: "凡人", starterItems: "聚气丹×3", artSlotRules: "炼气1/筑基2/金丹3" };

let announcements = [
  { id: "a1", title: "新版本 0.6.7 上线", body: "修复若干问题，优化修炼结算。", enabled: true },
  { id: "a2", title: "周末维护通知", body: "周日 02:00–03:00 停服维护。", enabled: false },
];
let popupTypes = [
  { slug: "announcement", template: "text_dialog", priority: 1, enabled: true },
  { slug: "update_notice", template: "update_dialog", priority: 2, enabled: true },
  { slug: "daily_gift", template: "reward_dialog", priority: 3, enabled: false },
];
let buildings = [{ slug: "spirit_field", displayName: "灵田", maxLevel: 10, laborBonus: 0.1, cultivateBonusPerLevel: 0.05 }];
let releases = [
  { id: "r3", versionName: "0.6.7", versionCode: 24, forceUpdate: false, isCurrent: true, sha256: "9f2c1d7a5be04a6c8d33e0a1c2f4b7d9a0e51c3b6f8a2d4e7c9b1a3d5f7e9c2b" },
  { id: "r2", versionName: "0.6.3", versionCode: 20, forceUpdate: true, isCurrent: false, sha256: "3a7bd9e12c4f5a60b8d1e3f7a9c2b4d6e8f0a1b3c5d7e9f1a3b5c7d9e1f3a5b7" },
];

const realmNameOf = (code) => realms.find((r) => r.code === code)?.displayName ?? "";
const bd = (power) => ({
  power, error: power === null ? "规则里的战力权重还没填，算不出战力。" : null, attack: 104, defense: 96, hp: 3300, speed: 21,
  lines: [
    { group: "境界", name: "炼气中期", attack: 20, defense: 15, hp: 260, speed: 14, counted: true, note: "" },
    { group: "武器", name: "青锋·良", attack: 23, defense: 4, hp: 69, speed: 0, counted: true, note: "" },
    { group: "功法", name: "养气诀", attack: 5, defense: 0, hp: 40, speed: 0, counted: false, note: "没有运转，不计入战力" },
  ],
  steps: power === null ? [] : [`战力 = 104×4.7 + 96×1.6 + 3300×0.95 + 21×2.6 = ${power}`],
});
const playerNames = ["tester01", "tester02", "linfeng", "yunxi", "moyan", "qingshan", "ahu", "xiaotao", "laozhang", "wuming", "chenmo", "sunyue"];
const players = playerNames.map((username, i) => {
  const realm = realms[Math.min(i % 6, 5)];
  const power = username === "tester02" ? null : 400 + i * 130;
  return { username, realmName: realm.displayName, cultivation: 100 + i * 900, power, lastSettledAt: iso((i + 1) * 3600e3 * 1.7), breakdown: bd(power) };
});
const ops = [];
const actions = ["login", "settle", "breakthrough", "settle", "login"];
for (let i = 0; i < 40; i++) {
  const who = playerNames[i % playerNames.length];
  const action = actions[i % actions.length];
  ops.push({ at: iso(i * 17 * 60e3 + 30e3), actorName: who, action, result: i % 13 === 7 ? "denied" : "success", reason: i % 13 === 7 ? "密码错误" : null, summary: action === "breakthrough" ? { from: "炼气初期", to: "炼气中期", success: true } : action === "settle" ? { gained: 120 + i, offlineSeconds: 900 } : {} });
}
ops.splice(2, 0, { at: iso(40 * 60e3), actorName: "admin", action: "publish", result: "success", reason: null, summary: { version: 7, note: "调整炼气期修炼速度" } });

// ---------- 发布版本 / diff ----------
const collections = () => ({
  realm: Object.fromEntries(realms.map((r) => [String(r.code), r])),
  stage: Object.fromEntries(stages.map((s) => [s.id, s])),
  item: Object.fromEntries(items.map((s) => [s.id, s])),
  skill: Object.fromEntries(skills.map((s) => [s.id, s])),
  globals: { rules },
});
const nameOf = (kind, key, row) => (kind === "globals" ? "战斗与全局参数" : row.displayName ?? row.name ?? key);
const stripDerived = (row) => {
  const copy = { ...row };
  for (const k of ["realmName", "realmMissing", "recommendedPower", "powerProblem", "categoryName", "categoryMissing"]) delete copy[k];
  return copy;
};
function diff(before, after) {
  const changes = [];
  for (const kind of Object.keys(after)) {
    const a = before?.[kind] ?? {};
    const b = after[kind];
    for (const key of new Set([...Object.keys(a), ...Object.keys(b)])) {
      if (!(key in a)) changes.push({ kind, slug: key, name: nameOf(kind, key, b[key]), type: "added", fields: [] });
      else if (!(key in b)) changes.push({ kind, slug: key, name: nameOf(kind, key, a[key]), type: "removed", fields: [] });
      else {
        const x = stripDerived(a[key]);
        const y = stripDerived(b[key]);
        const fields = [];
        for (const f of new Set([...Object.keys(x), ...Object.keys(y)])) {
          if (JSON.stringify(x[f]) !== JSON.stringify(y[f])) fields.push({ field: f, before: x[f] ?? null, after: y[f] ?? null });
        }
        if (fields.length) changes.push({ kind, slug: key, name: nameOf(kind, key, b[key]), type: "changed", fields });
      }
    }
  }
  return { total: changes.length, added: changes.filter((c) => c.type === "added").length, removed: changes.filter((c) => c.type === "removed").length, changed: changes.filter((c) => c.type === "changed").length, changes };
}
const published = [];
function publish(note, ago) {
  const version = (published.at(-1)?.version ?? 0) + 1;
  published.push({ version, checksum: Math.random().toString(16).slice(2).padEnd(16, "0") + "abcdef0123456789", note, publishedBy: "admin-1", publishedAt: iso(ago), sourceVersion: published.at(-1)?.version ?? null, snapshot: clone(collections()) });
}
// 先造 3 个旧版本（用较早的数据），再改出几处未发布的草稿改动
const origRules = clone(rules);
const origRealm3 = clone(realms[2]);
realms[2].gainPerTick = 4.5; publish("初版内容", 20 * 86400e3);
realms[2].gainPerTick = 5; rules.attackWeight = 4.5; publish("上调炼气期修炼速度", 9 * 86400e3);
realms[2] = origRealm3; rules = origRules; publish("调整战力权重与首领掉落", 2 * 86400e3);
// 草稿改动：修改境界、技能、规则，新增物品，删除一个关卡
realms[3].gainPerTick = 10; realms[3].breakthroughCost = 6800;
skills[1].attack = 14;
rules.minInterval = 0.45;
items.push({ id: "i-new", displayName: "养魂木", description: "新增的炼器材料" });
stages = stages.filter((s) => s.id !== "s3").concat([{ id: "s3", displayName: "落霞谷", realmCode: 3, bosses: [boss("赤练蛇王", 70, 48, 6400, 1.4, [])] }]);

const enrichStage = (s) => ({
  ...s,
  realmName: realmNameOf(s.realmCode),
  realmMissing: !realms.some((r) => r.code === s.realmCode),
  recommendedPower: s.id === "s3" ? null : 800 + s.realmCode * 330,
  powerProblem: s.id === "s3" ? "这个关卡的首领没有填掉落，推荐战力暂时算不出。" : null,
});

// ---------- 公式预览（按当前规则现算） ----------
function preview(body) {
  const r = { ...rules, ...(body ?? {}) };
  const k = r.defenseConstant || 1;
  const dmg = (a, d, kk) => (a * a) / (a + kk * d);
  const attack = 100;
  const defense = 100;
  const raisedK = k * 1.5;
  const interval = (speed, base) => Math.max(r.minInterval, (1.5 * base) / (base + speed));
  const mk = (name, a, d, h, s) => ({ name, attack: a, defense: d, hp: h, speed: s, interval: interval(s, r.speedBase), power: Math.round(a * r.attackWeight + d * r.defenseWeight + h * r.hpWeight + s * r.speedWeight), lines: [["attack", "攻击", a, r.attackWeight], ["defense", "防御", d, r.defenseWeight], ["hp", "气血", h, r.hpWeight], ["speed", "速度", s, r.speedWeight]].map(([key, label, stat, weight]) => ({ key, label, stat, weight, amount: stat * weight })) });
  const pv = [mk("均衡", 100, 100, 333, 20), mk("偏攻击", 150, 70, 250, 16), mk("偏速度", 80, 80, 280, 80)];
  const total = 100 * r.attackWeight + 100 * r.defenseWeight + 333 * r.hpWeight + 20 * r.speedWeight;
  return {
    evenDamage: dmg(attack, defense, k), fightSeconds: 12, raisedK: { k: raisedK, damage: dmg(attack, defense, raisedK), durationSeconds: 18 },
    damageCurve: Array.from({ length: 11 }, (_, i) => ({ defense: i * 40, damage: dmg(attack, i * 40, k), raisedDamage: dmg(attack, i * 40, raisedK) })),
    kCurve: Array.from({ length: 8 }, (_, i) => ({ k: 0.5 + i * 0.5, damage: dmg(attack, defense, 0.5 + i * 0.5), durationSeconds: 8 + i * 4 })),
    defenseConstant: k, intervalAt20: interval(20, r.speedBase), minInterval: r.minInterval,
    raisedSpeedBase: { speedBase: r.speedBase * 1.5, intervalAt20: interval(20, r.speedBase * 1.5) },
    intervalCurve: Array.from({ length: 11 }, (_, i) => ({ speed: i * 20, interval: interval(i * 20, r.speedBase), raisedInterval: interval(i * 20, r.speedBase * 1.5) })),
    standardPower: Math.round(total),
    shares: [["attack", "攻击", 100 * r.attackWeight], ["defense", "防御", 100 * r.defenseWeight], ["hp", "气血", 333 * r.hpWeight], ["speed", "速度", 20 * r.speedWeight]].map(([key, label, amount]) => ({ key, label, amount: Math.round(amount), ratio: amount / total })),
    puppets: pv, speedWeightDoubled: { weight: r.speedWeight * 2, puppets: pv },
  };
}

// ---------- 路由 ----------
const omitSnapshot = (entry) => { const copy = { ...entry }; delete copy.snapshot; return copy; };
const json = (res, body, status = 200) => { res.writeHead(status, { "content-type": "application/json; charset=utf-8" }); res.end(JSON.stringify(body)); };
const readBody = (req) => new Promise((resolve) => { let data = ""; req.on("data", (c) => (data += c)); req.on("end", () => { try { resolve(data && req.headers["content-type"]?.includes("json") ? JSON.parse(data) : {}); } catch { resolve({}); } }); });

function crud(list, set, idKey, make) {
  return {
    list: () => list(),
    create: (b) => { const row = make(b); set([...list(), row]); return row; },
    update: (id, b) => { set(list().map((r) => (String(r[idKey]) === id ? { ...r, ...make({ ...r, ...b, [idKey]: r[idKey] }) } : r))); return {}; },
    remove: (id) => { set(list().filter((r) => String(r[idKey]) !== id)); return {}; },
  };
}
const stageBody = (b) => ({ id: b.id ?? uid("s"), displayName: b.displayName, realmCode: Number(b.realmCode), bosses: b.bosses ?? [] });
const handlers = {
  realms: crud(() => realms, (v) => (realms = v), "code", (b) => ({ code: Number(b.code), displayName: b.displayName, majorName: b.majorName, tickSeconds: b.tickSeconds, gainPerTick: b.gainPerTick, breakthroughCost: b.breakthroughCost, attack: b.attack, defense: b.defense, hp: b.hp, speed: b.speed, interval: b.interval ?? null })),
  items: crud(() => items, (v) => (items = v), "id", (b) => ({ id: b.id ?? uid("i-"), displayName: b.displayName, description: b.description ?? "" })),
  skills: crud(() => skills, (v) => (skills = v), "id", (b) => ({ id: b.id ?? uid("k"), displayName: b.displayName, description: b.description ?? "", categoryId: b.categoryId, categoryName: skillCategories.find((c) => c.id === b.categoryId)?.displayName ?? "", categoryMissing: false, attack: b.attack ?? 0, defense: b.defense ?? 0, hp: b.hp ?? 0, speed: b.speed ?? 0, cultivateBonus: b.cultivateBonus ?? 0 })),
  "skill-categories": crud(() => skillCategories, (v) => (skillCategories = v), "id", (b) => ({ id: b.id ?? uid("c"), displayName: b.displayName })),
  stages: crud(() => stages, (v) => (stages = v), "id", stageBody),
  puppets: crud(() => puppets, (v) => (puppets = v), "id", (b) => ({ ...b, id: b.id ?? uid("pp") })),
};

async function api(req, res, url) {
  const p = url.pathname;
  const m = req.method;
  const body = ["POST", "PUT", "PATCH", "DELETE"].includes(m) ? await readBody(req) : {};
  if (p === "/healthz") return json(res, { ok: true, version: "dev", contentVersion: published.at(-1).version });
  if (p === "/admin/auth/login") return json(res, { token: "mock-token" });
  if (p === "/admin/players") return json(res, players);
  if (/\/reset$/.test(p) && m === "POST") return json(res, {});
  if (p === "/admin/operations") {
    const from = Date.parse(url.searchParams.get("from") ?? 0);
    const to = Date.parse(url.searchParams.get("to") ?? Date.now());
    const name = url.searchParams.get("name");
    const action = url.searchParams.get("action");
    return json(res, ops.filter((o) => Date.parse(o.at) >= from && Date.parse(o.at) <= to && (!name || o.actorName.includes(name)) && (!action || o.action === action)));
  }
  if (p === "/admin/releases" && m === "GET") return json(res, releases);
  if (p === "/admin/releases") return json(res, { id: "r9" });
  if (p === "/admin/announcements" && m === "GET") return json(res, announcements);
  if (p === "/admin/announcements") { if (body.id) announcements = announcements.map((a) => (a.id === body.id ? { ...a, ...body } : a)); else announcements.push({ ...body, id: uid("a") }); return json(res, {}); }
  if (p === "/admin/popup-types") return json(res, popupTypes);
  if (p.startsWith("/admin/popup-types/") && m === "PUT") { const slug = p.split("/").pop(); popupTypes = popupTypes.map((t) => (t.slug === slug ? { ...t, ...body } : t)); return json(res, {}); }
  if (p === "/admin/content/buildings") return json(res, buildings);
  if (p.startsWith("/admin/content/buildings/") && m === "PUT") return json(res, {});
  if (p === "/content/current") return json(res, { globals: baseGlobals });

  if (p === "/admin/draft/enhance") {
    let createdMaterials = [];
    if (m === "PUT") {
      enhance = clone(body);
      const used = new Set(Object.values(enhance.qualities).flatMap((q) => (q.breakthroughs ?? []).flatMap((n) => n.materials.map((r) => r.itemSlug))));
      for (const material of STARTING_MATERIALS) if (used.has(material.slug) && !items.some((it) => it.id === material.slug)) { items.push({ id: material.slug, displayName: material.displayName, description: "装备强化到突破节点时消耗的材料。" }); createdMaterials.push(material.slug); }
    }
    return json(res, { rules: enhance, starting: STARTING_ENHANCE, startingMaterials: STARTING_MATERIALS, createdMaterials });
  }
  if (p === "/admin/draft/gear") return json(res, { factors, majors });
  if (p === "/admin/draft/gear-qualities" && m === "PUT") { factors = { ...factors, ...body }; return json(res, {}); }
  if (p.startsWith("/admin/draft/gear/") && m === "PUT") { const id = decodeURIComponent(p.split("/").pop()); for (const mj of majors) for (const pc of mj.pieces) if (pc.id === id) Object.assign(pc, { displayName: body.displayName, description: body.description, iconKey: body.iconKey }); return json(res, {}); }
  if (p === "/admin/draft/rules") { if (m === "PUT") { rules = { ...rules, ...body }; return json(res, {}); } return json(res, rules); }
  if (p === "/admin/draft/formula-preview") return json(res, preview(body));
  if (p === "/admin/draft/trial") return json(res, { results: (body.puppetIds ?? []).map((id) => { const pp = puppets.find((x) => x.id === id); return { puppetId: id, displayName: pp?.displayName ?? id, kindName: pp?.kindName ?? "", error: null, win: true, reason: "win", durationSeconds: 14.5, timeLimitSeconds: 20, player: { power: pp?.power ?? 0, attack: pp?.attack ?? 0, defense: pp?.defense ?? 0, hp: pp?.hp ?? 0, speed: pp?.speed ?? 0, interval: pp?.interval ?? 1.5 }, playerHit: 31.2, playerHits: 5, playerKillSeconds: 7.5, bossHit: 18.4, bossHits: 6, bossKillSeconds: 9 }; }) });
  if (p === "/admin/draft/puppets/duels") return json(res, { timeLimitSeconds: 20, fights: puppets.flatMap((a) => puppets.filter((d) => d.id !== a.id).map((d) => ({ attackerId: a.id, attackerName: a.displayName, defenderId: d.id, defenderName: d.displayName, wins: 1, losses: 0 }))) });
  if (p === "/admin/draft/diff") {
    const from = url.searchParams.get("from") ?? "current";
    const to = url.searchParams.get("to") ?? "draft";
    const snap = (ref) => (ref === "draft" ? collections() : ref === "current" ? published.at(-1).snapshot : published.find((v) => String(v.version) === ref)?.snapshot);
    const a = snap(from);
    const b = snap(to);
    if (!b || (from !== "none" && !a)) return json(res, { error: { code: "NOT_FOUND", message: "没有这个版本" } }, 404);
    return json(res, { from, to, ...diff(a, b) });
  }
  if (p === "/admin/draft/versions") { const cur = published.at(-1).version; return json(res, { currentVersion: cur, versions: [...published].reverse().map((entry) => ({ ...omitSnapshot(entry), isCurrent: entry.version === cur })) }); }
  if (p === "/admin/draft/publish" && m === "POST") { publish(body.note ?? "", 0); return json(res, { version: published.at(-1).version }); }

  const match = p.match(/^\/admin\/draft\/([a-z-]+)(?:\/([^/]+))?$/);
  if (match && handlers[match[1]]) {
    const h = handlers[match[1]];
    const [, kind, id] = match;
    const decorate = kind === "stages" ? (list) => list.map(enrichStage) : (list) => list;
    if (m === "GET") return json(res, decorate(h.list()));
    if (m === "POST") return json(res, h.create(body));
    if (m === "PUT") return json(res, h.update(decodeURIComponent(id), body));
    if (m === "DELETE") return json(res, h.remove(decodeURIComponent(id)));
  }
  return json(res, { error: { code: "NOT_FOUND", message: `mock 没有实现 ${m} ${p}` } }, 404);
}

const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".woff2": "font/woff2" };
http
  .createServer(async (req, res) => {
    const url = new URL(req.url, "http://x");
    if (/^\/(admin|healthz|content)(\/|$)/.test(url.pathname)) return api(req, res, url);
    let file = path.join(DIST, decodeURIComponent(url.pathname));
    if (!file.startsWith(DIST) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(DIST, "index.html");
    res.writeHead(200, { "content-type": types[path.extname(file)] ?? "application/octet-stream" });
    fs.createReadStream(file).pipe(res);
  })
  .listen(PORT, "127.0.0.1", () => console.log(`admin mock: http://127.0.0.1:${PORT}`));
