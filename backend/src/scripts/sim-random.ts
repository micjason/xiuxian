// 长时随机模拟：满包 + 自动分解 + 强化经验回流到装备，对照《数值与玩法设计表》v1.2。
// 直接驱动真实后端（app.inject，虚拟时钟，带种子的随机数），不是另写一套公式。
// 用法：cd backend && DATABASE_URL=postgres://.../xiuxian_sim npx tsx src/scripts/sim-random.ts [天数=14] [种子数=3] > out.json
import { loadConfig } from "../config.js";
import { getDb, getSql } from "../db/client.js";
import { buildApp } from "../app.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";

type Json = any; // eslint-disable-line @typescript-eslint/no-explicit-any

function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ───────── 设计表 v1.2 的数字 ─────────
const TABLE = {
  qualityMult: { white: 1.0, green: 1.1, blue: 1.25, purple: 1.4, orange: 1.6 } as Record<string, number>,
  capByQuality: { white: 5, green: 8, blue: 10, purple: 12, orange: 15 } as Record<string, number>,
  decomposeBase: { white: 30, green: 60, blue: 120, purple: 240, orange: 480 } as Record<string, number>,
  statPerLevel: 0.06, // 表 3.3/3.6：每级 +6% 基础属性
  refund: 0.8,
  weights: {
    major1: { white: 70, green: 25, blue: 5, purple: 0 },
    major4: { white: 50, green: 35, blue: 13, purple: 2 },
    major7: { white: 35, green: 40, blue: 20, purple: 5 },
  } as Record<string, Record<string, number>>,
  dropPerHourOnline: [30, 35], // 表 2.6：每小时前台约 30–35 件
  referencePower: { lianqi_1: 759, lianqi_2: 847, lianqi_3: 950, zhuji_1: 2068, zhuji_2: 2303, zhuji_3: 2582, jindan_1: 5613, jindan_2: 6218, jindan_3: 6939 } as Record<string, number>,
  daysAB: { A: 2.22, B: 4.13 },
  recommendedBoss: { lianqi_3: 900, zhuji_3: 2450, jindan_3: 6590 } as Record<string, number>,
};
const enhanceCost = (level: number, quality: string) => Math.round(60 * Math.pow(1.25, level) * (TABLE.qualityMult[quality] ?? 1));
const decomposeGain = (quality: string, invested: number) => (TABLE.decomposeBase[quality] ?? 0) + Math.floor(invested * TABLE.refund);

const ROLE_SLOTS = ["weapon", "helmet", "clothes", "gloves", "shoes", "accessory"];

type Variant = "auto" | "manual";
type Schedule = "A" | "B";

async function main() {
  loadConfig();
  const days = Number(process.argv[2] ?? 14);
  const seeds = Number(process.argv[3] ?? 3);
  const db = getDb();
  await applyPrototypeV12(db);
  const results: Json[] = [];
  for (let seed = 1; seed <= seeds; seed++) {
    for (const schedule of ["A", "B"] as Schedule[]) {
      for (const variant of ["auto", "manual"] as Variant[]) {
        const started = Date.now();
        const r: Awaited<ReturnType<typeof runBot>> & { wallSeconds?: number } = await runBot(db, { seed, schedule, variant, days });
        r.wallSeconds = (Date.now() - started) / 1000;
        results.push(r);
        console.error(`done seed=${seed} ${schedule} ${variant} reached=${r.finalRealm} day=${r.finalDay.toFixed(2)} wall=${r.wallSeconds}s`);
      }
    }
  }
  console.log(JSON.stringify(results));
  await getSql().end();
}

async function runBot(db: Json, cfg: { seed: number; schedule: Schedule; variant: Variant; days: number }) {
  const rng = mulberry32(cfg.seed * 7919 + (cfg.schedule === "A" ? 1 : 2) * 104729 + (cfg.variant === "auto" ? 3 : 4));
  const randomInt = (min: number, max: number) => min + Math.floor(rng() * (max - min));
  const T0 = Date.parse("2026-10-01T05:00:00.000Z");
  let clock = T0;
  const app = await buildApp(db, () => new Date(clock), { randomInt });
  const username = `s${cfg.seed}${cfg.schedule}${cfg.variant[0]}${Date.now() % 1e7}`;
  const reg = (await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username, password: "correct-horse-1" } })).json() as Json;
  let token: string = reg.token;
  if (!token) console.error("register failed", JSON.stringify(reg));
  let keySeq = 0;
  const call = async (method: "GET" | "POST", url: string, payload?: Json): Promise<{ code: number; body: Json }> => {
    for (let attempt = 0; attempt < 2; attempt++) {
      const res = await app.inject({
        method,
        url: `/api/v1${url}`,
        headers: { authorization: `Bearer ${token}`, "idempotency-key": `sim-${cfg.seed}-${keySeq++}-${clock}` },
        payload: payload ?? (method === "POST" ? {} : undefined),
      });
      if (res.statusCode === 401 && attempt === 0) {
        const login = (await app.inject({ method: "POST", url: "/api/v1/auth/login", payload: { username, password: "correct-horse-1" } })).json() as Json;
        token = login.token;
        continue;
      }
      return { code: res.statusCode, body: res.json() as Json };
    }
    throw new Error("unreachable");
  };
  const content = (await call("GET", "/content/current")).body as Json;
  const items = new Map<string, Json>((content.items as Json[]).map((i) => [i.slug, i]));
  const realms = content.realms as Json[];
  const realmBySlug = new Map<string, Json>(realms.map((r) => [r.slug, r]));
  const weights = content.globals.powerWeights as Record<string, number>;
  const capacity = content.globals.bagCapacity as number;
  const stagesWithBoss = (content.stages as Json[]).filter((s) => (s.bosses?.length ?? 0) > 0);

  // 指标
  const m: Json = {
    onlineSeconds: 0,
    drops: { total: 0, byRealm: {} as Json, byQuality: {} as Json, dropped: 0, decomposed: 0, freedEvents: 0, bagFullHeartbeats: 0 },
    violations: [] as string[],
    deviations: { enhanceCost: [] as Json[], decompose: [] as Json[], statGain: [] as Json[] },
    enhance: { calls: 0, levelsGained: 0, expSpent: 0, blockedAtNode: 0, nodeBreaks: 0, byQuality: {} as Json },
    exp: { fromAutoDecompose: 0, fromManualDecompose: 0, fromFreed: 0 },
    bag: { maxUsed: 0, overCapacity: 0, bossBagFull: 0, manualDecomposeCalls: 0 },
    boss: { attempts: 0, wins: 0, losses: 0, byStage: {} as Json },
    breakthroughs: [] as Json[],
    layerReached: {} as Json,
    powerAtLayer: {} as Json,
    offlineReports: [] as Json[],
    timeline: [] as Json[],
  };
  const viol = (msg: string) => { if (m.violations.length < 40) m.violations.push(msg); };

  const bagUsed = (state: Json) => (state.items as Json[]).filter((i) => !i.equippedSlot).length;
  const score = (item: Json) => {
    const d = items.get(item.itemSlug)!;
    const mult = 1 + TABLE.statPerLevel * (item.enhanceLevel ?? 0);
    return ((d.attack ?? 0) * weights.attack + (d.defense ?? 0) * weights.defense + (d.hp ?? 0) * weights.hp + (d.speed ?? 0) * weights.speed) * mult;
  };
  const isGear = (item: Json) => items.get(item.itemSlug)?.kind === "equipment" && !!items.get(item.itemSlug)?.slot;
  const quality = (item: Json) => items.get(item.itemSlug)?.quality as string;

  let state = (await call("GET", "/me/state")).body as Json;
  const noteLayer = (label: string) => {
    const slug = state.realmSlug as string;
    if (m.layerReached[slug] === undefined) {
      m.layerReached[slug] = (clock - T0) / 86400000;
      m.powerAtLayer[slug] = state.power;
      m.timeline.push({ at: label, day: +((clock - T0) / 86400000).toFixed(3), realm: slug, power: state.power });
    }
  };
  noteLayer("start");

  const heartbeat = async (online: boolean) => {
    const before = state;
    const res = await call("GET", "/me/state");
    if (res.code !== 200) throw new Error(`state ${res.code} ${JSON.stringify(res.body)}`);
    state = res.body;
    const last = state.lastSettle as Json;
    if (last?.online) {
      const stage = (content.stages as Json[]).find((s) => s.slug === (state.wave as Json)?.stageSlug);
      const realm = realms.find((r) => r.sortOrder === stage?.requiredRealmOrder);
      const key = realm?.majorKey ?? "?";
      m.drops.byRealm[key] ??= { drops: 0, onlineSeconds: 0 };
      m.drops.byRealm[key].onlineSeconds += last.seconds ?? 0;
      m.onlineSeconds += last.seconds ?? 0;
      for (const d of last.drops as Json[]) {
        m.drops.total++;
        m.drops.byRealm[key].drops++;
        const q = d.quality ?? "?";
        m.drops.byQuality[key] ??= {};
        m.drops.byQuality[key][q] = (m.drops.byQuality[key][q] ?? 0) + 1;
        if (d.dropped) m.drops.dropped++;
        if (d.decomposed) {
          m.drops.decomposed++;
          m.exp.fromAutoDecompose += d.enhanceExp;
          const expect = decomposeGain(q, 0);
          if (d.enhanceExp !== expect) m.deviations.decompose.push({ src: "auto-new", quality: q, got: d.enhanceExp, expect });
        }
        for (const f of d.freed as Json[]) {
          m.drops.freedEvents++;
          m.exp.fromFreed += f.enhanceExp;
          const fq = items.get(f.itemSlug)?.quality as string;
          const expect = decomposeGain(fq, 0);
          if (f.enhanceExp !== expect) m.deviations.decompose.push({ src: "freed", quality: fq, got: f.enhanceExp, expect });
        }
      }
      if (last.bagFull) m.drops.bagFullHeartbeats++;
      // 不变量：满包丢弃只能发生在包真满时；自动分解开着时，丢的只能是蓝/紫且包里已没有未强化白/绿
      const used = bagUsed(state);
      const droppedNow = (last.drops as Json[]).filter((d) => d.dropped);
      if (droppedNow.length > 0) {
        if (used < capacity) viol(`丢弃了掉落但背包只有 ${used}/${capacity}`);
        if (state.autoDecompose) {
          for (const d of droppedNow) {
            if (["white", "green"].includes(d.quality)) viol("自动分解开着，白/绿掉落却被丢弃（应直接分解）");
          }
          const junk = (state.items as Json[]).filter((i) => !i.equippedSlot && isGear(i) && ["white", "green"].includes(quality(i)) && i.enhanceLevel === 0);
          if (junk.length > 0) viol(`自动分解开着，蓝/紫掉落被丢弃，但包里还有 ${junk.length} 件未强化白/绿可腾格`);
        }
      }
    }
    const used = bagUsed(state);
    m.bag.maxUsed = Math.max(m.bag.maxUsed, used);
    if (used > capacity) m.bag.overCapacity++;
    if ((state.enhanceExp as number) < 0) viol("强化经验为负");
    void before;
    noteLayer("heartbeat");
    return res.code;
  };

  const equipBest = async () => {
    for (let round = 0; round < 3; round++) {
      let changed = false;
      for (const slot of ROLE_SLOTS) {
        const worn = (state.items as Json[]).find((i) => i.equippedSlot === slot);
        const cands = (state.items as Json[]).filter((i) => !i.equippedSlot && isGear(i) && items.get(i.itemSlug)?.slot === slot);
        cands.sort((a, b) => score(b) - score(a));
        const best = cands[0];
        if (best && (!worn || score(best) > score(worn) + 1e-9)) {
          const r = await call("POST", `/me/items/${best.id}/equip`);
          if (r.code === 200) { state = (await call("GET", "/me/state")).body; changed = true; }
        }
      }
      if (!changed) break;
    }
  };

  // 强化：把强化经验花在已穿戴装备上（先便宜的），并核对消耗和属性增益
  const spendEnhance = async () => {
    for (let guard = 0; guard < 80; guard++) {
      const worn = (state.items as Json[]).filter((i) => i.equippedSlot && isGear(i));
      const options = worn.map((i) => ({ i, q: quality(i), level: i.enhanceLevel as number })).filter((o) => o.level < (TABLE.capByQuality[o.q] ?? 0));
      options.sort((a, b) => enhanceCost(a.level, a.q) - enhanceCost(b.level, b.q));
      let acted = false;
      for (const o of options) {
        const cost = enhanceCost(o.level, o.q);
        const node = (content.enhance?.qualities ?? content.globals.enhance.qualities)[o.q]?.breakthroughs?.find((b: Json) => b.level === o.level);
        if (node && (o.i.breakLevel ?? 0) < o.level) {
          // 到突破节点：材料够就突破
          const need = node.materials as Json[];
          const have = (slug: string) => (state.items as Json[]).filter((x) => x.itemSlug === slug).reduce((s, x) => s + (x.quantity ?? 1), 0);
          if (need.every((n) => have(n.itemSlug) >= n.count)) {
            const r = await call("POST", `/me/items/${o.i.id}/breakthrough`);
            if (r.code === 200) { m.enhance.nodeBreaks++; state = (await call("GET", "/me/state")).body; acted = true; break; }
          } else { m.enhance.blockedAtNode++; continue; }
        }
        if ((state.enhanceExp as number) < cost) continue;
        const beforeExp = state.enhanceExp as number;
        const beforeStats = { attack: state.attack as number, defense: state.defense as number, hp: state.hp as number, speed: state.speed as number };
        const r = await call("POST", `/me/items/${o.i.id}/enhance`, { toMax: false });
        if (r.code !== 200) continue;
        state = (await call("GET", "/me/state")).body;
        const spent = beforeExp - (state.enhanceExp as number);
        m.enhance.calls++; m.enhance.levelsGained++; m.enhance.expSpent += spent;
        m.enhance.byQuality[o.q] ??= { levels: 0, exp: 0 };
        m.enhance.byQuality[o.q].levels++; m.enhance.byQuality[o.q].exp += spent;
        if (spent !== cost) m.deviations.enhanceCost.push({ quality: o.q, level: o.level, got: spent, table: cost });
        const d = items.get(o.i.itemSlug)!;
        for (const stat of ["attack", "defense", "hp", "speed"]) {
          if (!(d[stat] > 0)) continue;
          const gain = (state[stat] as number) - (beforeStats as Json)[stat];
          const expect = d[stat] * TABLE.statPerLevel * (stat === "speed" ? 1 : 1);
          // 速度会被速度系数折算，只比其它三项
          if (stat !== "speed") m.deviations.statGain.push({ quality: o.q, level: o.level, stat, got: +gain.toFixed(3), table: +expect.toFixed(3), rel: +((gain - expect) / expect).toFixed(4) });
        }
        acted = true;
        break;
      }
      if (!acted) break;
    }
  };

  const manualDecompose = async () => {
    const junk = (state.items as Json[]).filter((i) => !i.equippedSlot && isGear(i) && ["white", "green"].includes(quality(i)) && (i.enhanceLevel ?? 0) === 0);
    junk.sort((a, b) => score(a) - score(b));
    for (const it of junk) {
      if (bagUsed(state) <= capacity - 8) break;
      const before = state.enhanceExp as number;
      const r = await call("POST", `/me/items/${it.id}/decompose`);
      if (r.code !== 200) continue;
      m.bag.manualDecomposeCalls++;
      state = (await call("GET", "/me/state")).body;
      const got = (state.enhanceExp as number) - before;
      m.exp.fromManualDecompose += got;
      const expect = decomposeGain(quality(it), 0);
      if (got !== expect) m.deviations.decompose.push({ src: "manual", quality: quality(it), got, expect });
    }
  };

  const tryBoss = async (stageSlug: string): Promise<"win" | "loss" | "bagfull" | "err"> => {
    m.boss.attempts++;
    m.boss.byStage[stageSlug] ??= { attempts: 0, wins: 0 };
    m.boss.byStage[stageSlug].attempts++;
    let r = await call("POST", `/me/stages/${stageSlug}/challenge`, { ultTaps: [] });
    if (r.code === 409 && r.body?.error?.code === "BAG_FULL") {
      m.bag.bossBagFull++;
      if (cfg.variant === "manual") {
        await manualDecompose();
        r = await call("POST", `/me/stages/${stageSlug}/challenge`, { ultTaps: [] });
      }
      if (r.code === 409) return "bagfull";
    }
    if (r.code !== 200) return "err";
    state = (await call("GET", "/me/state")).body;
    if (r.body.battle.win) { m.boss.wins++; m.boss.byStage[stageSlug].wins++; return "win"; }
    m.boss.losses++;
    return "loss";
  };

  const manage = async () => {
    if (state.offlineReport) {
      const rep = state.offlineReport as Json;
      m.offlineReports.push({ day: +((clock - T0) / 86400000).toFixed(2), seconds: rep.seconds, counted: rep.countedSeconds, gained: rep.gained, base: rep.baseGained, bonus: rep.bonusGained, hitCap: rep.hitCap });
      await call("POST", `/me/offline-reports/${rep.id}/ack`);
    }
    if (cfg.variant === "manual" && state.autoDecompose) { await call("POST", "/me/auto-decompose", { enabled: false }); state = (await call("GET", "/me/state")).body; }
    if (cfg.variant === "manual" && bagUsed(state) >= capacity - 4) await manualDecompose();
    await equipBest();
    await spendEnhance();
    // 突破：修为够就先过关卡再突破
    for (let guard = 0; guard < 6; guard++) {
      const b = state.breakthrough as Json;
      if (!b?.nextSlug || (state.cultivation as number) < b.cost) break;
      if (b.requiredStage && !b.requiredStage.cleared) {
        const out = await tryBoss(b.requiredStage.slug);
        if (out !== "win") break;
        await equipBest(); await spendEnhance();
        continue;
      }
      const before = state;
      const r = await call("POST", "/me/breakthrough");
      state = (await call("GET", "/me/state")).body;
      const success = r.code === 200 && r.body.result?.success;
      m.breakthroughs.push({ day: +((clock - T0) / 86400000).toFixed(3), from: before.realmSlug, to: state.realmSlug, success: !!success, code: r.code, rateBp: b.rateBp, powerBefore: before.power, powerAfter: state.power, previewPower: b.preview?.power });
      if (r.code === 200 && success && b.preview?.power && Math.abs(b.preview.power - state.power) > 1) viol(`突破预览战力 ${b.preview.power} ≠ 突破后 ${state.power}`);
      noteLayer("breakthrough");
      await equipBest(); await spendEnhance();
    }
    // 每天首领重复挑战（前 3 次胜利有奖励）：打当前能挑战的最高已通关首领
    const cleared = stagesWithBoss.filter((s) => (state.stages as Json[]).some((x) => x.stageSlug === s.slug && x.firstClearedAt));
    const top = cleared[cleared.length - 1];
    if (top) {
      const row = (state.stages as Json[]).find((x) => x.stageSlug === top.slug);
      const daily = (state.bossDaily as Json[] | undefined)?.find((d) => d.stageSlug === top.slug);
      if (daily && daily.used < daily.limit) { for (let k = 0; k < daily.limit - daily.used; k++) { const o = await tryBoss(top.slug); if (o !== "win") break; } await equipBest(); await spendEnhance(); }
      void row;
    }
  };

  const sessionTimesHours = cfg.schedule === "B" ? [6, 6 + 1 / 3, 6 + 2 / 3] : [6, 6 + 1 / 3, 14.5];
  const day0 = clock;
  const endAt = T0 + cfg.days * 86400000;
  let finalRealm = state.realmSlug as string;
  outer: for (let day = 0; clock < endAt; day++) {
    for (const h of sessionTimesHours) {
      const start = day0 + day * 86400000 + h * 3600000;
      if (start < clock) continue;
      clock = start;
      await heartbeat(true); // 第一次请求：上次结算之后的间隔算离线，生成报告
      await manage();
      for (let t = 0; t < 15 * 60; t += 12) {
        clock += 12000;
        await heartbeat(true);
        if (t % 120 === 0) await manage();
      }
      if (state.realmSlug === "jindan_3" && (state.cultivation as number) >= 0) { finalRealm = "jindan_3"; if (m.boss.byStage.jindan_3?.wins >= 1 || day >= cfg.days) break outer; }
    }
    finalRealm = state.realmSlug as string;
    if (state.realmSlug === "jindan_3" && day >= 1 + Math.floor(m.layerReached["jindan_3"] ?? 0)) break;
  }
  // 战力 vs 参考配置
  const finalItems = (state.items as Json[]).filter((i) => i.equippedSlot);
  void realmBySlug;
  return {
    seed: cfg.seed, schedule: cfg.schedule, variant: cfg.variant, finalRealm: state.realmSlug, finalDay: (clock - T0) / 86400000,
    layerReached: m.layerReached, powerAtLayer: m.powerAtLayer, metrics: { ...m, timeline: undefined }, timeline: m.timeline,
    finalPower: state.power, finalGear: finalItems.map((i) => ({ slot: i.equippedSlot, slug: i.itemSlug, level: i.enhanceLevel })),
    finalEnhanceExp: state.enhanceExp, TABLE_ref: TABLE.referencePower,
  };
}

await main();
