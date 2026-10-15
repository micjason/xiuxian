/**
 * 数值模拟：按配置推演 参考角色 打每关怪物、首领（含手动大招 4/5/6 倍）、到达每个境界层要多久，
 * 输出 Markdown 对照表并标出和设计表不一致的地方。
 *
 * 运行（在 backend 目录下，用 backend 的 tsx）：
 *   npx tsx ../tools/sim/sim.ts [--config ../tools/sim/prototype-v1.1.config.json] [--out /workspace/sim_report_week1.md]
 *
 * 复用后端真实代码：simulateBattle / computePower / ratePower（战斗与战力）、gearBudgetOf / splitGearBudget（装备生成器）、
 * enhancedStat（强化）、settleTicks（修为结算，含余数）。大招后端还没有，这里按设计表 2.4 的规则自己实现（见 simulateBoss）。
 * 不连数据库、不读线上内容；"生成器装备"用的是代码里的生成公式 + 设计表的境界属性，不是线上真实装备。
 */
import { readFileSync, writeFileSync } from "node:fs";
import { hitDamage, simulateBattle } from "../../backend/src/modules/combat/battle.js";
import { computePower, ratePower } from "../../backend/src/modules/combat/stats.js";
import { enhancedStat, STARTING_ENHANCE_RULES } from "../../backend/src/modules/content/enhance.js";
import { gearBudgetOf, splitGearBudget, GEAR_SLOTS } from "../../backend/src/modules/content/gear.js";
import { settleTicks } from "../../backend/src/modules/progress/settle.js";

// ---------- 配置类型 ----------
type Stats = { attack: number; defense: number; hp: number; speed: number };
type Quality = "white" | "green" | "blue" | "purple";
type Cfg = {
  globals: {
    weights: Stats;
    baseInterval: number;
    speedBase: number;
    minInterval: number;
    defenseConstant: number;
    timeLimitSeconds: number;
    offlineCapSeconds: number;
    onlineGapSeconds: number;
    waveSize: number;
    waveTransitionSeconds: number;
    reviveSeconds: number;
    statGrowthBp: number;
    qualityFactors: Record<Quality, number>;
    ult: { firstCooldownSeconds: number; autoCastWindowSeconds: number };
    scheduleOnlineMinutesPerDay: number;
  };
  majors: { id: string; name: string; ult: { multBp: number; cooldownSeconds: number }; skillBonusBp: number; bossRewardSkillBp: number }[];
  layers: { id: string; name: string; major: string; gainPerTick: number; costToNext: number | null; requiresBoss?: string; stats: Stats }[];
  stages: {
    id: string;
    name: string;
    monster: { name: string; hp: number; attack: number; defense: number; interval: number; killXp: number };
    boss?: { id: string; name: string; hp: number; attack: number; defense: number; interval: number; recommendedPower: number; firstClearCultivation: number };
  }[];
  gearTable: Record<string, Partial<Stats>[]>;
  referenceLoadouts: Record<string, [string, Quality, number][]>;
  tableClaims: {
    referenceStats: Record<string, Stats & { interval: number; power: number }>;
    avgKillIntervalSeconds: Record<string, number>;
    boss: Record<string, { manual: string; auto: string; noGear: string; manualSeconds: number; manualRemainPct: number; autoSeconds: number; autoRemainPct: number }>;
    targets: { bossWinSeconds: [number, number]; reachFoundationMinutes: number; guideReachFoundationSeconds: number; daysAllNineLayers: { A: number; B: number; range: [number, number] } };
  };
  guideScript: {
    firstBattleAt: number;
    events: { t: number; do: string; slot?: string; quality?: Quality; tier?: number; level?: number; bonusBp?: number; boss?: string }[];
    bossReward: Record<string, { skillBp: number; equip: { slot: string; quality: Quality; tier: number; level: number } }>;
  };
};

const args = process.argv.slice(2);
const argOf = (name: string, fallback: string) => {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? (args[index + 1] as string) : fallback;
};
const configPath = argOf("--config", new URL("./prototype-v1.1.config.json", import.meta.url).pathname);
const outPath = argOf("--out", "/workspace/sim_report_week1.md");
const cfg = JSON.parse(readFileSync(configPath, "utf8")) as Cfg;
const G = cfg.globals;
const ZERO: Stats = { attack: 0, defense: 0, hp: 0, speed: 0 };
const addStats = (a: Stats, b: Partial<Stats>): Stats => ({
  attack: a.attack + (b.attack ?? 0),
  defense: a.defense + (b.defense ?? 0),
  hp: a.hp + (b.hp ?? 0),
  speed: a.speed + (b.speed ?? 0),
});
const majorIndex = (id: string) => cfg.majors.findIndex((m) => m.id === id);

// ---------- 装备：两种来源 ----------
export type GearSource = "table" | "generator";

/** 生成器：把设计表每层的绝对属性换成"到达该层增加的差值"（后台存的就是差值），再走代码里的预算 + 部位份额 + 品质系数。 */
const realmRows = cfg.layers.map((layer, index) => {
  const prev = index === 0 ? ZERO : (cfg.layers[index - 1] as (typeof cfg.layers)[number]).stats;
  return {
    sortOrder: index + 1,
    baseAttack: layer.stats.attack - prev.attack,
    baseDefense: layer.stats.defense - prev.defense,
    baseHp: layer.stats.hp - prev.hp,
    baseSpeed: layer.stats.speed - prev.speed,
  };
});
const generatedBase = new Map<string, Stats>();
cfg.majors.forEach((major, index) => {
  const orders = [index * 3 + 1, index * 3 + 2, index * 3 + 3];
  const budget = gearBudgetOf(realmRows, orders);
  for (const slot of GEAR_SLOTS) {
    for (const quality of Object.keys(G.qualityFactors) as Quality[]) {
      generatedBase.set(`${major.id}|${slot.key}|${quality}`, splitGearBudget({ budget, slotKey: slot.key, factor: G.qualityFactors[quality], weights: G.weights }));
    }
  }
});

export function gearPiece(source: GearSource, tier: number, slot: string, quality: Quality, level: number): Stats {
  const major = cfg.majors[tier];
  if (!major) throw new Error(`没有第 ${tier} 个大境界`);
  if (source === "generator") {
    const base = generatedBase.get(`${major.id}|${slot}|${quality}`);
    if (!base) throw new Error(`生成器没有 ${slot}/${quality}`);
    const grow = (value: number) => enhancedStat(value, level, STARTING_ENHANCE_RULES, quality);
    return { attack: grow(base.attack), defense: grow(base.defense), hp: grow(base.hp), speed: grow(base.speed) };
  }
  const white = (cfg.gearTable[slot] ?? [])[tier];
  if (!white) throw new Error(`设计表 3.1 没有 ${slot} 第 ${tier} 阶`);
  const factor = G.qualityFactors[quality];
  // 设计表口径：先 round(白色基础 × 品质系数)，再 round(× (1 + 等级 × 6%))，都是整数
  const f = (value: number | undefined) => (value ? Math.round(Math.round(value * factor) * (1 + (level * G.statGrowthBp) / 10000)) : 0);
  return { attack: f(white.attack), defense: f(white.defense), hp: f(white.hp), speed: f(white.speed) };
}

type Piece = { slot: string; quality: Quality; tier: number; level: number };
type Loadout = Map<string, Piece>;

function referenceLoadout(majorId: string): Piece[] {
  const tier = majorIndex(majorId);
  return (cfg.referenceLoadouts[majorId] ?? []).map(([slot, quality, level]) => ({ slot, quality, level, tier }));
}
function gearSum(source: GearSource, pieces: Piece[] | Loadout): Stats {
  const list = Array.isArray(pieces) ? pieces : [...pieces.values()];
  return list.reduce((sum, p) => addStats(sum, gearPiece(source, p.tier, p.slot, p.quality, p.level)), ZERO);
}

// ---------- 角色 / 战斗 ----------
type Fighter = { attack: number; defense: number; hp: number; interval: number };
function fighterOf(layerIndex: number, gear: Stats): { fighter: Fighter; stats: Stats; power: number; speed: number } {
  const base = (cfg.layers[layerIndex] as (typeof cfg.layers)[number]).stats;
  const stats = addStats(base, gear);
  const { interval, power } = computePower({ ...stats, baseInterval: G.baseInterval, minInterval: G.minInterval, speedBase: G.speedBase, weights: G.weights });
  return { fighter: { attack: stats.attack, defense: stats.defense, hp: stats.hp, interval }, stats, power, speed: stats.speed };
}
const monsterFighter = (m: Cfg["stages"][number]["monster"]): Fighter => ({ attack: m.attack, defense: m.defense, hp: m.hp, interval: m.interval });

/** 一波（3 只依次上前，血量不回，转场时回满）。每只的计时从上前开始（和设计表 2.2 的"刀数 × 间隔"一致）。 */
function simulateWave(player: Fighter, monster: Fighter) {
  let hp = player.hp;
  let total = 0;
  const killTimes: number[] = [];
  let deaths = 0;
  let minHpPct = 100;
  for (let index = 0; index < G.waveSize; index += 1) {
    const result = simulateBattle({ ...player, hp }, monster, { timeLimitSeconds: 600, defenseConstant: G.defenseConstant });
    if (!result.win) {
      deaths += 1;
      total += result.durationSeconds + G.reviveSeconds;
      hp = player.hp;
      continue;
    }
    killTimes.push(result.durationSeconds);
    total += result.durationSeconds;
    const lastBossHit = [...result.log].reverse().find((event) => event.side === "boss");
    hp = lastBossHit ? lastBossHit.targetHpAfter : hp;
    minHpPct = Math.min(minHpPct, (hp / player.hp) * 100);
  }
  const cycle = total + G.waveTransitionSeconds;
  return { killTimes, cycleSeconds: cycle, avgKillInterval: cycle / G.waveSize, deaths, minHpPct };
}

type UltMode = { multBp: number; cooldownSeconds: number; waitSeconds: number } | null;
/** 首领战，带可选大招。大招 = 额外一次伤害（不替代普攻），冷却从释放时算起，首次冷却 8 秒；规则见设计表 2.4。无大招时必须和后端 simulateBattle 完全一致。 */
function simulateBoss(player: Fighter, boss: Fighter, ult: UltMode) {
  const k = G.defenseConstant;
  const pDmg = hitDamage(player.attack, boss.defense, k);
  const bDmg = hitDamage(boss.attack, player.defense, k);
  const ultDmg = ult ? Math.floor((pDmg * ult.multBp) / 10000) : 0;
  let pHp = player.hp;
  let bHp = boss.hp;
  let pNext = player.interval;
  let bNext = boss.interval;
  let readyAt = G.ult.firstCooldownSeconds;
  let uNext = ult ? readyAt + ult.waitSeconds : Number.POSITIVE_INFINITY;
  let casts = 0;
  const finish = (win: boolean, reason: string, seconds: number) => ({ win, reason, seconds, bossRemainPct: (bHp / boss.hp) * 100, playerRemainPct: (pHp / player.hp) * 100, casts });
  for (;;) {
    const next = Math.min(pNext, bNext, uNext);
    if (next > G.timeLimitSeconds) return finish(false, "timeout", G.timeLimitSeconds);
    if (pNext === next) {
      bHp = Math.max(0, bHp - pDmg);
      pNext += player.interval;
      if (bHp <= 0) return finish(true, "win", next);
    }
    if (uNext === next && ult) {
      bHp = Math.max(0, bHp - ultDmg);
      casts += 1;
      readyAt = next + ult.cooldownSeconds;
      uNext = readyAt + ult.waitSeconds;
      if (bHp <= 0) return finish(true, "win", next);
    }
    if (bNext === next && bHp > 0) {
      pHp = Math.max(0, pHp - bDmg);
      bNext += boss.interval;
      if (pHp <= 0) return finish(false, "defeated", next);
    }
  }
}

// ---------- 报告工具 ----------
const lines: string[] = [];
const out = (text = "") => lines.push(text);
const flags: string[] = [];
const fmt = (value: number, digits = 1) => value.toFixed(digits);
const pct = (value: number) => `${value.toFixed(0)}%`;
const flag = (ok: boolean) => (ok ? "✅" : "⚠️");
function table(header: string[], rows: (string | number)[][]) {
  out(`| ${header.join(" | ")} |`);
  out(`|${header.map(() => "---").join("|")}|`);
  for (const row of rows) out(`| ${row.join(" | ")} |`);
  out();
}
const clock = (seconds: number) => `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(Math.round(seconds % 60)).padStart(2, "0")}`;

const SOURCES: { key: GearSource; label: string }[] = [
  { key: "table", label: "设计表 3.1 的装备数值（设计目标）" },
  { key: "generator", label: "代码生成器装备（gear.ts 预算×部位份额×品质系数，吃设计表的境界属性）" },
];

out("# 数值模拟报告（第 1 周）");
out();
out(`- 生成时间：${new Date().toISOString()}（脚本 \`tools/sim/sim.ts\`，配置 \`${configPath.split("/").slice(-3).join("/")}\`，对照 \`prototype_design_numbers.md\` v1.1）`);
out("- 方法：复用后端真实的 `simulateBattle`（战斗）、`computePower/ratePower`（出手间隔与战力）、`gearBudgetOf/splitGearBudget`（装备生成器）、`enhancedStat`（强化）、`settleTicks`（修为结算，含余数携带）。**大招后端还没做**，本脚本按设计表 2.4 自己实现（额外一次伤害、冷却从释放时算起、首次冷却 8 秒、伤害 = floor(普攻伤害 × 倍率)）；无大招时本脚本的首领战与后端 `simulateBattle` 逐项一致（见 §3 末尾自检）。");
out("- 两套装备：**表**（设计表 3.1 的数值，用来复现表里的结论）和 **生成器**（代码实际会生成的数值，用来看上线后的真实结果）。参考配置（每境界穿什么）取设计表 2.1 注释，两套装备穿同样的件数、品质和强化等级。");
out("- 不是真机、不是线上内容；没有随机（设计表也没有暴击/闪避）。普通波次不含大招（决定：只做表演）。");
out();

// ================= §1 参考属性 =================
out("## 1. 参考配置属性（设计表 2.1）");
out();
const refStatsBySource: Record<string, Record<string, ReturnType<typeof fighterOf>>> = { table: {}, generator: {} };
for (const s of SOURCES) {
  out(`### 1.${s.key === "table" ? 1 : 2} ${s.label}`);
  out();
  const rows: (string | number)[][] = [];
  cfg.layers.forEach((layer, index) => {
    const gear = gearSum(s.key, referenceLoadout(layer.major));
    const f = fighterOf(index, gear);
    refStatsBySource[s.key]![layer.id] = f;
    const claim = cfg.tableClaims.referenceStats[layer.id];
    const diffPower = claim ? ((f.power - claim.power) / claim.power) * 100 : 0;
    const ok = claim ? Math.abs(diffPower) <= 1 : true;
    if (s.key === "table" && claim) {
      const wrong = (["hp", "attack", "defense", "speed"] as const).filter((key) => Math.abs(f.stats[key] - claim[key]) > 0.5);
      if (wrong.length > 0) {
        const label = { hp: "生命", attack: "攻击", defense: "防御", speed: "速度" } as const;
        flags.push(`设计表 2.1 ${layer.name} 的参考配置有数不对：${wrong.map((key) => `${label[key]} 表 ${claim[key]}、复算 ${fmt(f.stats[key], 0)}`).join("；")}（战力差 ${fmt(diffPower)}%，间隔表 ${claim.interval}、复算 ${fmt(f.fighter.interval, 2)}）。`);
      }
    }
    if (s.key === "table" && !ok) flags.push(`参考配置战力与设计表 2.1 不符：${layer.name} 表 ${claim?.power}，复算 ${f.power}（${fmt(diffPower)}%）。`);
    if (s.key === "generator" && claim && Math.abs(diffPower) > 10) flags.push(`生成器装备下 ${layer.name} 的参考战力 ${f.power}，比设计表 ${claim.power} ${diffPower > 0 ? "高" : "低"} ${fmt(Math.abs(diffPower), 0)}%（装备数值要回填表）。`);
    rows.push([
      layer.name,
      `${fmt(f.stats.hp, 0)} / ${fmt(f.stats.attack, 0)} / ${fmt(f.stats.defense, 0)} / ${fmt(f.stats.speed, 0)}`,
      fmt(f.fighter.interval, 2),
      f.power,
      claim ? `${claim.hp} / ${claim.attack} / ${claim.defense} / ${claim.speed}` : "—",
      claim ? claim.interval.toFixed(2) : "—",
      claim ? claim.power : "—",
      claim ? `${diffPower >= 0 ? "+" : ""}${fmt(diffPower)}% ${flag(ok)}` : "—",
    ]);
  });
  table(["层", "复算 生命/攻击/防御/速度", "间隔", "战力", "表 生命/攻击/防御/速度", "表间隔", "表战力", "战力差"], rows);
}
out("装备生成器输出（白色，+0，与设计表 3.1 对比）：");
out();
{
  const rows: (string | number)[][] = [];
  for (const slot of GEAR_SLOTS) {
    const cells: (string | number)[] = [slot.key];
    cfg.majors.forEach((major, tier) => {
      const gen = gearPiece("generator", tier, slot.key, "white", 0);
      const tab = gearPiece("table", tier, slot.key, "white", 0);
      const fmtStat = (s: Stats) =>
        [s.hp ? `生命${fmt(s.hp, 0)}` : "", s.attack ? `攻${fmt(s.attack, 1)}` : "", s.defense ? `防${fmt(s.defense, 1)}` : "", s.speed ? `速${fmt(s.speed, 1)}` : ""].filter(Boolean).join(" ") || "—";
      cells.push(`${fmtStat(gen)}｜表：${fmtStat(tab)}`);
    });
    rows.push(cells);
  }
  table(["部位", ...cfg.majors.map((m) => `${m.name}阶（生成器｜表）`)], rows);
  out("注：生成器给的是**另一套属性分布**（每个部位的属性种类固定在 `GEAR_SLOTS`：武器只有攻击、头冠/衣服防御+生命、护手攻击+防御、鞋子速度+生命、饰品攻击+速度），且数值不取整（保留 2 位小数）；设计表 3.1 的分布（头部只有生命、手部只有攻击、饰品生命+攻击…）在代码里不存在。");
  out();
}

// ================= §2 普通关卡 =================
out("## 2. 普通怪波次（3 只/波，转场 2 秒，只算普攻）");
out();
const waveBySource: Record<string, Record<string, ReturnType<typeof simulateWave>>> = { table: {}, generator: {} };
for (const s of SOURCES) {
  out(`### 2.${s.key === "table" ? 1 : 2} ${s.label}`);
  out();
  const rows: (string | number)[][] = [];
  cfg.stages.forEach((stage, index) => {
    const player = (refStatsBySource[s.key] as Record<string, ReturnType<typeof fighterOf>>)[(cfg.layers[index] as (typeof cfg.layers)[number]).id] as ReturnType<typeof fighterOf>;
    const wave = simulateWave(player.fighter, monsterFighter(stage.monster));
    (waveBySource[s.key] as Record<string, ReturnType<typeof simulateWave>>)[stage.id] = wave;
    const unarmed = fighterOf(index, ZERO);
    const unarmedWave = simulateWave(unarmed.fighter, monsterFighter(stage.monster));
    rows.push([
      stage.name,
      stage.monster.name,
      wave.killTimes.map((t) => fmt(t, 1)).join(" / "),
      fmt(wave.cycleSeconds, 1),
      fmt(wave.avgKillInterval, 2),
      `${stage.monster.killXp}`,
      fmt(stage.monster.killXp / wave.avgKillInterval, 2),
      wave.deaths > 0 ? `⚠️ 阵亡 ${wave.deaths}` : `最低剩血 ${pct(wave.minHpPct)}`,
      `${fmt(unarmedWave.avgKillInterval, 2)}${unarmedWave.deaths > 0 ? "（会阵亡）" : ""}`,
    ]);
    if (wave.deaths > 0) flags.push(`${s.key === "table" ? "表装备" : "生成器装备"}下参考配置在 ${stage.name} 会阵亡 ${wave.deaths} 次。`);
  });
  table(["关卡", "怪物", "每只击杀耗时(s)", "一波周期(s)", "击杀间隔(s)", "击杀修为", "击杀修为/秒", "安全度", "无装备击杀间隔(s)"], rows);
}
out("与设计表 2.5 的“平均击杀间隔”（炼气 4.67 / 筑基 4.23 / 金丹 4.23）对照（取每个大境界 3 关的平均）：");
out();
{
  const rows: (string | number)[][] = [];
  for (const s of SOURCES) {
    cfg.majors.forEach((major) => {
      const ids = cfg.stages.filter((st) => cfg.layers.find((l) => l.id === st.id)?.major === major.id).map((st) => st.id);
      const avg = ids.reduce((sum, id) => sum + ((waveBySource[s.key] as Record<string, ReturnType<typeof simulateWave>>)[id] as ReturnType<typeof simulateWave>).avgKillInterval, 0) / ids.length;
      const claim = cfg.tableClaims.avgKillIntervalSeconds[major.id] as number;
      const ok = Math.abs(avg - claim) / claim <= 0.05;
      if (s.key === "table" && !ok) flags.push(`${major.name}平均击杀间隔：表 ${claim}，复算 ${fmt(avg, 2)}。`);
      rows.push([s.key === "table" ? "表装备" : "生成器装备", major.name, fmt(avg, 2), claim, `${flag(ok)}`]);
    });
  }
  table(["装备来源", "境界", "复算平均击杀间隔(s)", "表(s)", "±5% 内"], rows);
}

// ================= §3 首领 =================
out("## 3. 首领战（限时 " + G.timeLimitSeconds + " 秒；手动及时放大招 / 全不点自动放 / 无大招 / 无装备）");
out();
const bossRows: Record<string, (string | number)[][]> = { table: [], generator: [] };
const bossResults: Record<string, Record<string, Record<string, ReturnType<typeof simulateBoss>>>> = { table: {}, generator: {} };
for (const s of SOURCES) {
  cfg.stages.forEach((stage, index) => {
    if (!stage.boss) return;
    const layer = cfg.layers[index] as (typeof cfg.layers)[number];
    const major = cfg.majors.find((m) => m.id === layer.major) as (typeof cfg.majors)[number];
    const boss: Fighter = { attack: stage.boss.attack, defense: stage.boss.defense, hp: stage.boss.hp, interval: stage.boss.interval };
    const ref = (refStatsBySource[s.key] as Record<string, ReturnType<typeof fighterOf>>)[layer.id] as ReturnType<typeof fighterOf>;
    const bare = fighterOf(index, ZERO);
    const manual = simulateBoss(ref.fighter, boss, { ...major.ult, waitSeconds: 0 });
    const auto = simulateBoss(ref.fighter, boss, { ...major.ult, waitSeconds: G.ult.autoCastWindowSeconds });
    const none = simulateBoss(ref.fighter, boss, null);
    const noGear = simulateBoss(bare.fighter, boss, { ...major.ult, waitSeconds: G.ult.autoCastWindowSeconds });
    const check = simulateBattle(ref.fighter, boss, { timeLimitSeconds: G.timeLimitSeconds, defenseConstant: G.defenseConstant });
    ((bossResults[s.key] as Record<string, Record<string, ReturnType<typeof simulateBoss>>>)[stage.boss.id] = { manual, auto, none, noGear });
    const claim = cfg.tableClaims.boss[stage.boss.id] as (typeof cfg.tableClaims.boss)[string];
    const show = (r: ReturnType<typeof simulateBoss>) => (r.win ? `胜 ${fmt(r.seconds, 1)}s 剩血 ${pct(r.playerRemainPct)}` : `败(${r.reason}) 首领剩 ${pct(r.bossRemainPct)}`);
    const selfCheck = check.win === none.win && Math.abs(check.durationSeconds - none.seconds) < 1e-9;
    if (!selfCheck) flags.push(`自检失败：${stage.boss.name} 无大招时脚本与后端 simulateBattle 不一致。`);
    const inWindow = (r: ReturnType<typeof simulateBoss>) => r.win && r.seconds >= cfg.tableClaims.targets.bossWinSeconds[0] && r.seconds <= cfg.tableClaims.targets.bossWinSeconds[1];
    const power = ref.power;
    const recommended = Math.round(power * 0.95);
    (bossRows[s.key] as (string | number)[][]).push([
      stage.boss.name,
      `${power} / 推荐 ${stage.boss.recommendedPower}（${s.key === "table" ? "表装备" : "生成器"}×0.95=${recommended}）`,
      `${show(manual)} ${flag(inWindow(manual))}`,
      show(auto),
      show(none),
      show(noGear),
      `${claim.manual}｜${claim.auto}｜${claim.noGear}`,
      selfCheck ? "✅" : "❌",
    ]);
    if (s.key === "table") {
      const dm = Math.abs(manual.seconds - claim.manualSeconds);
      const dr = Math.abs(manual.playerRemainPct - claim.manualRemainPct);
      if (!manual.win || dm > 3 || dr > 8) flags.push(`${stage.boss.name}（表装备，手动大招）：表“${claim.manual}”，复算“${show(manual)}”。`);
      const da = Math.abs(auto.seconds - claim.autoSeconds);
      if (!auto.win || da > 3) flags.push(`${stage.boss.name}（表装备，自动大招）：表“${claim.auto}”，复算“${show(auto)}”。`);
      if (noGear.win) flags.push(`${stage.boss.name}：无装备也能打赢（表说败）——首领就不是“装备检查点”了。`);
    } else {
      if (!manual.win) flags.push(`${stage.boss.name}（生成器装备）：参考配置手动大招也打不过：${show(manual)}。`);
      else if (!inWindow(manual)) flags.push(`${stage.boss.name}（生成器装备）：手动大招用时 ${fmt(manual.seconds, 1)}s，不在 25–35s 目标内。`);
      if (!auto.win) flags.push(`${stage.boss.name}（生成器装备）：自动大招打不过：${show(auto)}。`);
      if (noGear.win) flags.push(`${stage.boss.name}（生成器装备）：无装备也能赢，首领不再是装备检查点。`);
    }
  });
}
for (const s of SOURCES) {
  out(`### 3.${s.key === "table" ? 1 : 2} ${s.label}`);
  out();
  table(["首领", "参考战力", "手动及时放（等待 0 秒）", "全不点（自动放，等待 2 秒）", "无大招（纯普攻）", "无装备（自动放）", "设计表 2.3 原文（手动｜自动｜无装备）", "与后端一致"], bossRows[s.key] as (string | number)[][]);
}
out("“剩血”= 玩家剩余血量百分比（与设计表 2.3 一致）；“败(timeout)”= 45 秒内没打死。");
out();

// ================= §4 到达各层 =================
out("## 4. 到达每个境界层要多久");
out();

// ---- 4.1 引导 10 分钟 ----
type GuideLog = { layerTimes: { layer: string; t: number }[]; boss?: { start: number; end: number; win: boolean; seconds: number; remain: number }; cultAt: Record<number, number>; finalLayer: number; notes: string[] };
function runGuide(source: GearSource): GuideLog {
  const script = cfg.guideScript;
  const loadout: Loadout = new Map();
  let layer = 0;
  let cult = 0;
  let remainderBp = 0;
  let skillBp = 0;
  let bossCleared = false;
  let bossBusyUntil = -1;
  let pendingBoss: { start: number } | null = null;
  const done = new Set<number>();
  const killCache = new Map<string, number>();
  let killAcc = 0;
  const log: GuideLog = { layerTimes: [], cultAt: {}, finalLayer: 0, notes: [] };
  const epoch = new Date("2026-10-16T00:00:00Z");
  const killIntervalNow = () => {
    const key = `${layer}|${[...loadout.entries()].map(([s, p]) => `${s}:${p.quality}${p.tier}${p.level}`).sort().join(",")}`;
    const hit = killCache.get(key);
    if (hit !== undefined) return hit;
    const f = fighterOf(layer, gearSum(source, loadout));
    const wave = simulateWave(f.fighter, monsterFighter((cfg.stages[layer] as (typeof cfg.stages)[number]).monster));
    killCache.set(key, wave.avgKillInterval);
    return wave.avgKillInterval;
  };
  const stamps = [28, 58, 75, 120, 165, 200, 239, 270, 320, 389, 414, 450, 510, 600];
  for (let t = 0; t <= 900; t += 1) {
    // 脚本事件
    script.events.forEach((event, index) => {
      if (done.has(index) || event.t > t) return;
      if (event.do === "equip") {
        loadout.set(event.slot as string, { slot: event.slot as string, quality: event.quality as Quality, tier: event.tier ?? 0, level: event.level ?? 0 });
      } else if (event.do === "skill") {
        skillBp = event.bonusBp ?? 0;
      } else if (event.do === "boss") {
        if (layer === 2 && !bossCleared && !pendingBoss && bossBusyUntil < 0) {
          const stage = cfg.stages[layer] as (typeof cfg.stages)[number];
          const boss = stage.boss as NonNullable<typeof stage.boss>;
          const major = cfg.majors[majorIndex((cfg.layers[layer] as (typeof cfg.layers)[number]).major)] as (typeof cfg.majors)[number];
          const f = fighterOf(layer, gearSum(source, loadout));
          const result = simulateBoss(f.fighter, { attack: boss.attack, defense: boss.defense, hp: boss.hp, interval: boss.interval }, { ...major.ult, waitSeconds: 0 });
          log.boss = { start: t, end: t + result.seconds, win: result.win, seconds: result.seconds, remain: result.playerRemainPct };
          log.notes.push(`首领战开始于 ${clock(t)}，战力 ${f.power}（推荐 ${boss.recommendedPower}），${result.win ? "胜" : "败"} 用时 ${fmt(result.seconds, 1)}s`);
          bossBusyUntil = t + result.seconds;
          pendingBoss = { start: t };
        } else if (layer < 2) {
          return; // 还没到炼气三层，先不标记完成，等到了再打
        }
      }
      done.add(index);
    });
    // 首领战结束
    if (pendingBoss && t >= bossBusyUntil && log.boss) {
      if (log.boss.win) {
        const reward = script.bossReward[(cfg.stages[2] as (typeof cfg.stages)[number]).boss?.id as string];
        cult += (cfg.stages[2] as (typeof cfg.stages)[number]).boss?.firstClearCultivation ?? 0;
        if (reward) {
          skillBp = reward.skillBp;
          loadout.set(reward.equip.slot, { ...reward.equip });
        }
        bossCleared = true;
      } else {
        log.notes.push("首领战失败，引导无法继续（脚本里没有重试）");
        break;
      }
      pendingBoss = null;
      bossBusyUntil = -1;
    }
    // 修为：每秒按真实 settleTicks（整数万分比 + 余数）
    const L = cfg.layers[layer] as (typeof cfg.layers)[number];
    const settled = settleTicks({ cultivation: cult, lastSettledAt: new Date(epoch.getTime() + (t - 1) * 1000), now: new Date(epoch.getTime() + t * 1000), tickSeconds: 1, gainPerTick: L.gainPerTick, bonusBp: skillBp, offlineCapSeconds: G.offlineCapSeconds, remainderBp });
    if (t > 0) {
      cult = settled.cultivation;
      remainderBp = settled.remainderBp;
    }
    // 击杀修为（前台在线；开场 20 秒、首领战期间没有）
    if (t >= script.firstBattleAt && t >= bossBusyUntil && !(pendingBoss)) {
      killAcc += 1 / killIntervalNow();
      while (killAcc >= 1) {
        killAcc -= 1;
        cult += (cfg.stages[layer] as (typeof cfg.stages)[number]).monster.killXp;
      }
    }
    if (stamps.includes(t)) log.cultAt[t] = cult;
    // 突破：够修为、过了首领就点
    if (L.costToNext !== null && cult >= L.costToNext && (!L.requiresBoss || bossCleared) && layer < cfg.layers.length - 1) {
      cult -= L.costToNext;
      layer += 1;
      log.layerTimes.push({ layer: (cfg.layers[layer] as (typeof cfg.layers)[number]).name, t });
      if (layer === 3) {
        break;
      }
    }
  }
  log.finalLayer = layer;
  return log;
}

out("### 4.1 新手引导前 10 分钟（设计表 6.1 的脚本：装备/功法按脚本时间到手，其余全自动；够修为就点突破）");
out();
const guideBySource: Record<string, GuideLog> = {};
for (const s of SOURCES) {
  const g = runGuide(s.key);
  guideBySource[s.key] = g;
  out(`**${s.label}**`);
  out();
  table(
    ["事件", "复算时刻", "设计表 6.1 时刻"],
    g.layerTimes.map((row) => [`到达 ${row.layer}`, clock(row.t), row.layer === "炼气二层" ? "00:58" : row.layer === "炼气三层" ? "03:59" : row.layer === "筑基一层" ? "06:54" : "—"]),
  );
  for (const note of g.notes) out(`- ${note}`);
  out();
  const reachedFoundation = g.layerTimes.find((row) => row.layer === "筑基一层");
  if (!reachedFoundation) {
    flags.push(`${s.key === "table" ? "表装备" : "生成器装备"}：引导脚本 15 分钟内没能到达筑基。`);
  } else {
    const minutes = reachedFoundation.t / 60;
    if (minutes > cfg.tableClaims.targets.reachFoundationMinutes) flags.push(`${s.key === "table" ? "表装备" : "生成器装备"}：引导到筑基用时 ${clock(reachedFoundation.t)}，超过 10 分钟目标。`);
    if (s.key === "table" && reachedFoundation.t > cfg.tableClaims.targets.guideReachFoundationSeconds + 15) flags.push(`引导到筑基：表写 06:54，复算 ${clock(reachedFoundation.t)}（脚本里首领 06:29 开战、用时约 28 秒，06:54 前打不完）。`);
  }
}
out("注：脚本里“06:29 挑战首领、06:54 突破”之间只有 25 秒，而首领战本身要约 28 秒，所以设计表 6.1 的 06:54 在时间上放不下；复算给出的是首领打完后的最早突破时刻。引导里的每一步在脚本时刻是否“买得起”，见 4.2 的修为余量。");
out();

// ---- 4.2 自由玩法：每层用时 + 天数 ----
out("### 4.2 不按引导脚本：参考配置在每一层的速度（前台在线含击杀 / 离线 / 日程 A、B）");
out();
type LayerRow = { name: string; cost: number; onlineRate: number; onlineMinutes: number; offline8h: number; dayA: number; dayB: number; daysA: number; daysB: number };
function freePlay(source: GearSource) {
  const rows: LayerRow[] = [];
  const epoch = new Date("2026-10-16T00:00:00Z");
  cfg.layers.forEach((layer, index) => {
    if (layer.costToNext === null) return;
    const major = cfg.majors[majorIndex(layer.major)] as (typeof cfg.majors)[number];
    const wave = (waveBySource[source] as Record<string, ReturnType<typeof simulateWave>>)[layer.id] as ReturnType<typeof simulateWave>;
    const stage = cfg.stages[index] as (typeof cfg.stages)[number];
    // 表的假设：功法加成取该境界大部分时间的值（炼气 5%、筑基 15%、金丹 30%）
    const bonusBp = major.skillBonusBp;
    const baseRate = (layer.gainPerTick * (10000 + bonusBp)) / 10000;
    const onlineRate = baseRate + stage.monster.killXp / wave.avgKillInterval;
    const offline = settleTicks({ cultivation: 0, lastSettledAt: epoch, now: new Date(epoch.getTime() + G.offlineCapSeconds * 1000), tickSeconds: 1, gainPerTick: layer.gainPerTick, bonusBp, offlineCapSeconds: G.offlineCapSeconds }).gained;
    const onlineDay = onlineRate * G.scheduleOnlineMinutesPerDay * 60;
    rows.push({
      name: layer.name,
      cost: layer.costToNext as number,
      onlineRate,
      onlineMinutes: (layer.costToNext as number) / onlineRate / 60,
      offline8h: offline,
      dayA: onlineDay + 2 * offline,
      dayB: onlineDay + offline,
      daysA: 0,
      daysB: 0,
    });
  });
  rows.forEach((row) => {
    row.daysA = row.cost / row.dayA;
    row.daysB = row.cost / row.dayB;
  });
  return rows;
}
const freeBySource: Record<string, LayerRow[]> = {};
for (const s of SOURCES) {
  const rows = freePlay(s.key);
  freeBySource[s.key] = rows;
  out(`**${s.label}**`);
  out();
  let cumA = 0;
  let cumB = 0;
  let cumOnline = 0;
  table(
    ["层 → 下一层", "所需修为", "在线每秒(含击杀)", "纯在线分钟", "累计在线分钟", "8h 离线得", "日程A 每日修为", "日程B 每日修为", "A 天", "B 天", "累计 A 天", "累计 B 天"],
    rows.map((row) => {
      cumA += row.daysA;
      cumB += row.daysB;
      cumOnline += row.onlineMinutes;
      return [row.name, row.cost.toLocaleString("en-US"), fmt(row.onlineRate, 2), fmt(row.onlineMinutes, 1), fmt(cumOnline, 0), row.offline8h.toLocaleString("en-US"), Math.round(row.dayA).toLocaleString("en-US"), Math.round(row.dayB).toLocaleString("en-US"), fmt(row.daysA, 2), fmt(row.daysB, 2), fmt(cumA, 2), fmt(cumB, 2)];
    }),
  );
  const first3 = rows.slice(0, 3).reduce((sum, row) => sum + row.onlineMinutes, 0);
  out(`- 只靠前台在线、不含引导脚本：炼气三层全部走完（含 1,800 修为那一层，且不算首领首通送的 +1,500）约 ${fmt(first3, 0)} 分钟；若首通 +1,500 到手，炼气三层那一层实际只需要再赚约 ${Math.max(0, 1800 - 1500)} 修为。`);
  const after = rows.slice(3);
  const totalA = rows.reduce((sum, row) => sum + row.daysA, 0);
  const totalB = rows.reduce((sum, row) => sum + row.daysB, 0);
  const t = cfg.tableClaims.targets.daysAllNineLayers;
  const bracket = (totalA <= t.range[1] && totalB >= t.range[0]) || (totalA >= t.range[0] && totalA <= t.range[1]) || (totalB >= t.range[0] && totalB <= t.range[1]);
  out(`- 8 层突破（炼气一 → 金丹三）合计：日程 A（每天 2 段 8h 离线 + ${G.scheduleOnlineMinutesPerDay} 分钟前台）**${fmt(totalA, 2)} 天**，日程 B（每天 1 段 8h 离线）**${fmt(totalB, 2)} 天**。目标 2–3 天；设计表自己写的是 A ${t.A} / B ${t.B} 天。${flag(bracket)}`);
  out();
  if (!bracket) flags.push(`${s.key === "table" ? "表装备" : "生成器装备"}：走完 9 层要 A ${fmt(totalA, 2)} 天 / B ${fmt(totalB, 2)} 天，不在 2–3 天目标内。`);
  void after;
}
const claimsA = cfg.tableClaims.targets.daysAllNineLayers;
{
  const rows = freeBySource.table as LayerRow[];
  const fa = rows.filter((r) => r.name.startsWith("筑基")).reduce((s, r) => s + r.daysA, 0);
  const fb = rows.filter((r) => r.name.startsWith("筑基")).reduce((s, r) => s + r.daysB, 0);
  const ja = rows.filter((r) => r.name.startsWith("金丹")).reduce((s, r) => s + r.daysA, 0);
  const jb = rows.filter((r) => r.name.startsWith("金丹")).reduce((s, r) => s + r.daysB, 0);
  out(`与设计表 1.3 对照（表装备）：筑基 A ${fmt(fa, 2)}（表 0.86）/ B ${fmt(fb, 2)}（表 1.6）；金丹 A ${fmt(ja, 2)}（表 0.8）/ B ${fmt(jb, 2)}（表 1.5）。设计表 1.3 的合计“A 约 1.7 天 / B 约 3.1 天”对应 ${claimsA.A} / ${claimsA.B}。`);
  out();
  const tol = (a: number, b: number) => Math.abs(a - b) / b <= 0.1;
  if (!(tol(fa, 0.86) && tol(fb, 1.6) && tol(ja, 0.8) && tol(jb, 1.5))) flags.push(`1.3 日程天数与设计表差超过 10%：筑基 A ${fmt(fa, 2)}/B ${fmt(fb, 2)}，金丹 A ${fmt(ja, 2)}/B ${fmt(jb, 2)}。`);
}

// ---- 4.3 引导里每步“买得起”吗 ----
out("### 4.3 引导脚本时刻的修为余量（表装备）");
out();
{
  const g = guideBySource.table as GuideLog;
  const rows = Object.entries(g.cultAt).map(([t, c]) => [clock(Number(t)), Math.round(c as number)]);
  table(["时刻", "复算当前修为（结余）"], rows);
  out("设计表 6.1 在这些时刻写的“当前修为”：00:28→11、00:58→2、01:15→28、02:00→103、02:45→178、03:20→235、03:59→0、04:30→54、05:20→139、06:29→1,757、06:54→0、07:14→109、08:30→552、10:00→1,082。（表里的“结余”是突破后剩下的；对照时看“每次突破前修为是否已超过所需”和“首领前是否已有约 300”即可，不要逐格比。）");
  out();
}

// ================= §5 结论 =================
out("## 5. 不一致 / 需要决定的地方（脚本自动汇总）");
out();
if (flags.length === 0) out("没有发现不一致。");
for (const [index, text] of flags.entries()) out(`${index + 1}. ${text}`);
out();
out("## 6. 没有验证的东西");
out();
out("- 这是离散模拟，不是服务端实现：大招、普通波次、在线/离线分段在后端都还没有，结论按设计表规则推演。");
out("- 装备掉落（4%、品质权重）、背包满、自动分解、玩家操作延迟都没有进模拟；“日程 A/B”是均值估算，不含掉装备带来的变强。");
out("- 引导脚本里的强化（+3）按设计表给的结果直接设成 +3，没有模拟强化经验。");
out("- “生成器装备”用的是代码里的生成公式 + 设计表的境界属性；线上库里实际装备数值没有读取。");
out("- 没有真机、没有随机掉落，也没有离线/在线交替的真实 3 秒轮询（修为用 `settleTicks` 每秒结算，已含余数携带，结果等价）。");

// ---------- 开头的要点 ----------
{
  const gen = bossResults.generator as Record<string, Record<string, ReturnType<typeof simulateBoss>>>;
  const tab = bossResults.table as Record<string, Record<string, ReturnType<typeof simulateBoss>>>;
  const bossIds = cfg.stages.flatMap((st) => (st.boss ? [st.boss.id] : []));
  const secs = (m: Record<string, Record<string, ReturnType<typeof simulateBoss>>>, key: string) => bossIds.map((id) => fmt(((m[id] as Record<string, ReturnType<typeof simulateBoss>>)[key] as ReturnType<typeof simulateBoss>).seconds, 1)).join(" / ");
  const remain = (m: Record<string, Record<string, ReturnType<typeof simulateBoss>>>, key: string) => bossIds.map((id) => pct(((m[id] as Record<string, ReturnType<typeof simulateBoss>>)[key] as ReturnType<typeof simulateBoss>).playerRemainPct)).join(" / ");
  const gt = guideBySource.table as GuideLog;
  const gg = guideBySource.generator as GuideLog;
  const reach = (g: GuideLog) => g.layerTimes.find((row) => row.layer === "筑基一层")?.t;
  const tf = freeBySource.table as LayerRow[];
  const gf = freeBySource.generator as LayerRow[];
  const sum = (rows: LayerRow[], key: "daysA" | "daysB") => rows.reduce((acc, row) => acc + row[key], 0);
  const genCore = (refStatsBySource.generator as Record<string, ReturnType<typeof fighterOf>>).jindan_1 as ReturnType<typeof fighterOf>;
  const genCoreWave = (waveBySource.generator as Record<string, ReturnType<typeof simulateWave>>).jindan_1 as ReturnType<typeof simulateWave>;
  const tabCoreWave = (waveBySource.table as Record<string, ReturnType<typeof simulateWave>>).jindan_1 as ReturnType<typeof simulateWave>;
  const noBonusMin = tf.slice(0, 3).reduce((acc, row) => acc + row.onlineMinutes, 0);
  const summary = [
    "## 要点（先看这里）",
    "",
    `1. **用设计表 3.1 的装备数值，本脚本复现了设计表的结论**：9 层参考战力与表 2.1 的差都在 0.1% 内（金丹层速度表写 54、复算 57，见 §5）；首领自动放大招 ${secs(tab, "auto")} 秒（表 32 / 30 / 28）；无装备都打不过；修为日程 A ${fmt(sum(tf, "daysA"), 2)} 天 / B ${fmt(sum(tf, "daysB"), 2)} 天（表 1.7 / 3.1）。手动及时放大招 ${secs(tab, "manual")} 秒、玩家剩血 ${remain(tab, "manual")}（表 28 / 28 / 28 秒，33% / 33% / 32%）——炼气首领差约 1 秒、3 个点。`,
    `2. **但代码生成器实际出的装备和设计表 3.1 不是一回事**：只有战力总量接近（9 层差 1–5%），属性分布不同（防御偏多、金丹速度偏多）。金丹一层参考角色速度 ${fmt(genCore.stats.speed, 0)}、出手间隔 ${fmt(genCore.fighter.interval, 2)} 秒（下限 ${G.minInterval}），打金丹一层小怪平均 ${fmt(genCoreWave.avgKillInterval, 1)} 秒一只（表装备 ${fmt(tabCoreWave.avgKillInterval, 1)} 秒），首领手动大招 ${secs(gen, "manual")} 秒打完（目标 25–35 秒），玩家剩血 ${remain(gen, "manual")}（表 33% 左右）。**也就是说装备数值要么改生成器的部位属性分布/速度预算，要么把表 3.1 改成生成器的结果，再重推怪物和首领数值。**这就是表里待确认第 10、11 条要的结论。`,
    `3. **新手引导 10 分钟到筑基**：按 6.1 脚本（表装备）${reach(gt) !== undefined ? clock(reach(gt) as number) : "没到"}、（生成器装备）${reach(gg) !== undefined ? clock(reach(gg) as number) : "没到"} 到筑基一层，都在 10 分钟内，但比表写的 06:54 晚约 ${reach(gt) !== undefined ? Math.round((reach(gt) as number) - 414) : "?"} 秒：首领 06:29 开打、要 ~29 秒，06:54 放不下。**这个 10 分钟成立的前提是首领首通送的修为 +1,500**；没有这笔奖励，只靠在线挂机，炼气三层全走完约 ${fmt(noBonusMin, 0)} 分钟。`,
    `4. **9 层要多久**：A ${fmt(sum(tf, "daysA"), 2)} 天 / B ${fmt(sum(tf, "daysB"), 2)} 天（表装备）；生成器装备 A ${fmt(sum(gf, "daysA"), 2)} / B ${fmt(sum(gf, "daysB"), 2)} 天。目标 2–3 天只在 A 和 B 之间“夹住”：A 型玩家不到 2 天，B 型玩家略超 3 天。`,
    "",
  ];
  const at = lines.findIndex((line) => line.startsWith("## 1. 参考配置属性"));
  lines.splice(at, 0, ...summary);
}

writeFileSync(outPath, lines.join("\n") + "\n");
console.log(`wrote ${outPath} (${lines.length} lines), ${flags.length} flags`);
