/**
 * 首领规则（第四批改版，2026-10-21，Chengpeng 定）：每关一个首领、一套规则，不再分精英 / 章末两档。
 * 全局默认值存在 content_globals.tuning.bossRules（配置概览「首领规则」一列），
 * 每关在 bosses[0].rules 里只存改过的项（灰字跟随默认，改了算「已自定义」，「恢复默认」= 删掉这一项）。
 * 只有全局、不能单关改的两项：每日首领挑战总次数（dailyChallengeTotal）、一次结算最多刷几只挂机首领（idleSpawnMaxPerSettle）。
 * 老数据（第三批的 { elite, chief } 两列）读的时候自动换成新的一套（legacyBossRules），迁移 0045 也会把库里的改掉。
 * 只放类型、默认值、校验和合并，不依赖数据库。
 */
import { AppError } from "../../shared/errors.js";
import type { StageMonster } from "./combat-types.js";

/**
 * 首领外观档次（只管画面：立绘边框 / 首领特效 / 标题文案，跟规则无关）：章末关 = chief，其余 = elite。
 * 第四批起规则只有一套；保留这个字段是为了客户端在新美术到之前照旧显示（客户端 tier_for_boss 认这两个字符串）。
 */
export const BOSS_TIERS = ["elite", "chief"] as const;
export type BossTier = (typeof BOSS_TIERS)[number];
/** 怪物档次（下发给客户端，传给 monster_rig / boss_battle 的 tier）：普通怪 / 精英 / 章末首领（只管画面）。 */
export type MonsterTier = "normal" | BossTier;

export const BOSS_QUALITIES = ["white", "green", "blue", "purple", "orange"] as const;
export type BossQuality = (typeof BOSS_QUALITIES)[number];
export const BOSS_STAT_KEYS = ["attack", "defense", "hp", "interval"] as const;
export type BossStatKey = (typeof BOSS_STAT_KEYS)[number];

/** 每关都能单独改的规则。 */
export type BossRuleSet = {
  /** auto = 本关普通怪 × 属性倍率（四舍五入，出手间隔不变）；manual = 首领自己填的数值。 */
  statMode: "auto" | "manual";
  statMul: { hp: number; attack: number; defense: number };
  /** 已击败后还能不能手动再打。 */
  allowRepeat: boolean;
  /** 击败过以后再赢（手动重打、挂机刷出来的首领）给不给重复奖励。 */
  repeatRewards: boolean;
  /** 首通奖励里「随机装备」按这个抽品质（百分比，合计 100）。 */
  gearQualityPct: Record<BossQuality, number>;
  /** 重复奖励的装备按这个抽品质（百分比，合计 100）。 */
  repeatGearQualityPct: Record<BossQuality, number>;
  /** 挂机中战力够了自动挑战（服务端结算时触发，只打还没击败过的首领）。 */
  autoChallenge: boolean;
  /** 自动挑战条件：战力 ≥ 推荐战力 × 这个百分比。 */
  autoChallengePowerPct: number;
  /** 自动挑战输了以后，隔多少秒再自动试一次。 */
  autoChallengeRetrySeconds: number;
  /** 挂机刷首领：已击败的首领，在本关挂机每刷 idleSpawnWaves 波小怪自动打一次（离线也算）。 */
  idleSpawn: boolean;
  /** 每多少波小怪刷一次首领。 */
  idleSpawnWaves: number;
  /** 挂机刷出来的首领算不算「每日首领挑战总次数」（Chengpeng 定：默认不算）。 */
  idleSpawnCountsDaily: boolean;
  /** 解锁下一关：需要击败本关首领。 */
  unlockNeedsBossWin: boolean;
  /** 解锁下一关：需要达到下一关的境界。 */
  unlockNeedsRealm: boolean;
};

/** 只有全局的项（配置概览里改，单关不能改）。 */
export type BossGlobalRules = {
  /** 每日首领挑战总次数（所有首领合计，每日重置整点换天）：已击败首领的手动重打赢了才消耗；没击败过的第一次挑战不算。0 = 手动重打都没有奖励。 */
  dailyChallengeTotal: number;
  /** 一次结算最多刷几只挂机首领（离线很久 + 波数设得很小时防止一次打几千场）；多出来的不补。 */
  idleSpawnMaxPerSettle: number;
};

/** tuning.bossRules：一套默认规则 + 全局项。 */
export type BossRules = BossRuleSet & BossGlobalRules;

/** 子项是一组数的规则（单关覆盖按小项存）。 */
export const BOSS_GROUP_KEYS = ["statMul", "gearQualityPct", "repeatGearQualityPct"] as const;
type GroupKey = (typeof BOSS_GROUP_KEYS)[number];
const isGroup = (key: string): key is GroupKey => (BOSS_GROUP_KEYS as readonly string[]).includes(key);

/** 每关的覆盖：只存改过的项。 */
export type BossRuleOverride = Partial<Omit<BossRuleSet, GroupKey>> & {
  statMul?: Partial<BossRuleSet["statMul"]>;
  gearQualityPct?: Partial<BossRuleSet["gearQualityPct"]>;
  repeatGearQualityPct?: Partial<BossRuleSet["repeatGearQualityPct"]>;
};

/**
 * 起始值（第四批，由第三批两档合并来，待负责人确认）：
 * 属性、首通品质、自动挑战沿用原小首领；重复奖励品质、每日次数沿用原章末首领；挂机每 1000 波刷一次，默认不算每日次数。
 */
export const DEFAULT_BOSS_RULE_SET: BossRuleSet = {
  statMode: "auto",
  statMul: { hp: 6.5, attack: 1.55, defense: 1.4 },
  allowRepeat: true,
  repeatRewards: true,
  gearQualityPct: { white: 0, green: 70, blue: 25, purple: 5, orange: 0 },
  repeatGearQualityPct: { white: 0, green: 50, blue: 35, purple: 13, orange: 2 },
  autoChallenge: true,
  autoChallengePowerPct: 100,
  autoChallengeRetrySeconds: 60,
  idleSpawn: true,
  idleSpawnWaves: 1000,
  idleSpawnCountsDaily: false,
  unlockNeedsBossWin: true,
  unlockNeedsRealm: true,
};

export const DEFAULT_BOSS_RULES: BossRules = {
  ...DEFAULT_BOSS_RULE_SET,
  dailyChallengeTotal: 5,
  idleSpawnMaxPerSettle: 20,
};

const PREFIX = "首领规则：";

function num(value: unknown, label: string, min: number, max: number, integer = false): number {
  if (value === undefined || value === null || value === "") {
    throw new AppError("INVALID_INPUT", `请填写${label}`);
  }
  const n = Number(value);
  if (!Number.isFinite(n) || n < min || n > max) {
    throw new AppError("INVALID_INPUT", `${label}要在 ${min} 到 ${max} 之间`);
  }
  if (integer && !Number.isInteger(n)) {
    throw new AppError("INVALID_INPUT", `${label}要填整数`);
  }
  return n;
}

function bool(value: unknown, label: string): boolean {
  if (value === true || value === "true") return true;
  if (value === false || value === "false") return false;
  throw new AppError("INVALID_INPUT", `${label}要选开或关`);
}

function mode(value: unknown): "auto" | "manual" {
  if (value === "auto" || value === "manual") return value;
  throw new AppError("INVALID_INPUT", "首领属性方式只能是「自动（按普通怪 × 倍率）」或「手填」");
}

function quality(value: unknown, label: string): Record<BossQuality, number> {
  const raw = (value ?? {}) as Record<string, unknown>;
  return Object.fromEntries(BOSS_QUALITIES.map((q) => [q, num(raw[q], label, 0, 100)])) as Record<BossQuality, number>;
}

/** 单个字段的校验（全局和单关覆盖共用）。 */
const FIELD: { [K in keyof BossRuleSet]: (value: unknown, prefix: string) => BossRuleSet[K] } = {
  statMode: (value) => mode(value),
  statMul: (value, prefix) => {
    const raw = (value ?? {}) as Record<string, unknown>;
    return {
      hp: num(raw.hp, `${prefix}气血倍率`, 0.01, 1000),
      attack: num(raw.attack, `${prefix}攻击倍率`, 0.01, 1000),
      defense: num(raw.defense, `${prefix}防御倍率`, 0.01, 1000),
    };
  },
  allowRepeat: (value, prefix) => bool(value, `${prefix}允许重打`),
  repeatRewards: (value, prefix) => bool(value, `${prefix}重复奖励`),
  gearQualityPct: (value, prefix) => quality(value, `${prefix}首通装备品质掉率`),
  repeatGearQualityPct: (value, prefix) => quality(value, `${prefix}重复奖励装备品质掉率`),
  autoChallenge: (value, prefix) => bool(value, `${prefix}允许自动挑战`),
  autoChallengePowerPct: (value, prefix) => num(value, `${prefix}自动挑战战力比例`, 1, 1000),
  autoChallengeRetrySeconds: (value, prefix) => num(value, `${prefix}自动挑战重试间隔`, 0, 86400, true),
  idleSpawn: (value, prefix) => bool(value, `${prefix}挂机刷首领`),
  idleSpawnWaves: (value, prefix) => num(value, `${prefix}每多少波刷一次首领`, 1, 1000000, true),
  idleSpawnCountsDaily: (value, prefix) => bool(value, `${prefix}挂机首领算每日次数`),
  unlockNeedsBossWin: (value, prefix) => bool(value, `${prefix}解锁要求击败首领`),
  unlockNeedsRealm: (value, prefix) => bool(value, `${prefix}解锁要求境界`),
};

const GLOBAL_FIELD: { [K in keyof BossGlobalRules]: (value: unknown, prefix: string) => number } = {
  dailyChallengeTotal: (value, prefix) => num(value, `${prefix}每日首领挑战总次数`, 0, 999, true),
  idleSpawnMaxPerSettle: (value, prefix) => num(value, `${prefix}一次结算最多刷几只挂机首领`, 1, 1000, true),
};

export const BOSS_RULE_KEYS = Object.keys(FIELD) as (keyof BossRuleSet)[];
export const BOSS_GLOBAL_KEYS = Object.keys(GLOBAL_FIELD) as (keyof BossGlobalRules)[];

function qualityTotalError(pct: Record<BossQuality, number>, label: string): string | null {
  const total = BOSS_QUALITIES.reduce((sum, q) => sum + pct[q], 0);
  return Math.abs(total - 100) > 0.001 ? `${label}合计要等于 100%（现在是 ${Math.round(total * 100) / 100}%）` : null;
}

function qualityProblems(set: Pick<BossRuleSet, "gearQualityPct" | "repeatGearQualityPct">): string[] {
  return [qualityTotalError(set.gearQualityPct, "首通装备品质掉率"), qualityTotalError(set.repeatGearQualityPct, "重复奖励装备品质掉率")].filter((row): row is string => row !== null);
}

/**
 * 第三批的两列 { elite, chief } → 一套（只在读到老格式时用；迁移 0045 也按同样的规则改库）：
 * 底子是原小首领那列（属性、首通品质、自动挑战、解锁），重复奖励品质 = 原章末那列的品质，
 * 每日首领挑战总次数 = 原章末每日次数（没有就 5），重复奖励打开，挂机刷首领用默认值。
 */
export function legacyBossRules(raw: unknown): Record<string, unknown> | null {
  const input = raw as Record<string, unknown> | null | undefined;
  if (!input || typeof input !== "object" || !("elite" in input || "chief" in input) || "statMode" in input) {
    return null;
  }
  const elite = (input.elite ?? {}) as Record<string, unknown>;
  const chief = (input.chief ?? {}) as Record<string, unknown>;
  const pick = (from: Record<string, unknown>, key: string, fallback: unknown) => (from[key] === undefined || from[key] === null ? fallback : from[key]);
  const out: Record<string, unknown> = { ...DEFAULT_BOSS_RULES };
  for (const key of ["statMode", "statMul", "allowRepeat", "gearQualityPct", "autoChallenge", "autoChallengePowerPct", "autoChallengeRetrySeconds", "unlockNeedsBossWin", "unlockNeedsRealm"]) {
    out[key] = pick(elite, key, out[key]);
  }
  out.repeatGearQualityPct = pick(chief, "gearQualityPct", out.repeatGearQualityPct);
  const limit = Number(chief.dailyRewardLimit);
  out.dailyChallengeTotal = Number.isInteger(limit) && limit > 0 ? limit : DEFAULT_BOSS_RULES.dailyChallengeTotal;
  out.repeatRewards = true;
  return out;
}

/** 一套规则的严格校验（保存配置概览时用）。缺的项用 fallback 补上。 */
export function bossRuleSetFromInput(raw: unknown, fallback: BossRuleSet, prefix = PREFIX): BossRuleSet {
  const input = (raw ?? {}) as Record<string, unknown>;
  const out = {} as Record<string, unknown>;
  for (const key of BOSS_RULE_KEYS) {
    const value = input[key];
    if (isGroup(key)) {
      out[key] = FIELD[key]({ ...(fallback[key] as object), ...((value ?? {}) as object) }, prefix);
    } else {
      out[key] = FIELD[key](value === undefined || value === null ? fallback[key] : value, prefix);
    }
  }
  const set = out as BossRuleSet;
  const problems = qualityProblems(set);
  if (problems.length > 0) {
    throw new AppError("INVALID_INPUT", prefix + problems[0]);
  }
  return set;
}

/** 全局规则（一套 + 全局项）的严格校验。老格式先换成新的一套。 */
export function bossRulesFromInput(raw: unknown, fallback: BossRules = DEFAULT_BOSS_RULES): BossRules {
  const input = (legacyBossRules(raw) ?? raw ?? {}) as Record<string, unknown>;
  const set = bossRuleSetFromInput(input, fallback);
  const global = Object.fromEntries(
    BOSS_GLOBAL_KEYS.map((key) => [key, GLOBAL_FIELD[key](input[key] === undefined || input[key] === null ? fallback[key] : input[key], PREFIX)]),
  ) as BossGlobalRules;
  return { ...set, ...global };
}

/** 宽松读取（运行时用）：库里存坏的项回退代码默认值，不让游戏停。 */
export function bossRulesOf(raw: unknown): BossRules {
  try {
    return bossRulesFromInput(raw);
  } catch {
    const input = (legacyBossRules(raw) ?? raw ?? {}) as Record<string, unknown>;
    const out = { ...DEFAULT_BOSS_RULES } as Record<string, unknown>;
    for (const key of BOSS_RULE_KEYS) {
      try {
        out[key] = isGroup(key) ? FIELD[key]({ ...(DEFAULT_BOSS_RULES[key] as object), ...((input[key] ?? {}) as object) }, PREFIX) : FIELD[key](input[key] ?? DEFAULT_BOSS_RULES[key], PREFIX);
      } catch {
        out[key] = DEFAULT_BOSS_RULES[key];
      }
    }
    for (const key of BOSS_GLOBAL_KEYS) {
      try {
        out[key] = GLOBAL_FIELD[key](input[key] ?? DEFAULT_BOSS_RULES[key], PREFIX);
      } catch {
        out[key] = DEFAULT_BOSS_RULES[key];
      }
    }
    for (const key of ["gearQualityPct", "repeatGearQualityPct"] as const) {
      if (qualityTotalError(out[key] as Record<BossQuality, number>, "") !== null) {
        out[key] = DEFAULT_BOSS_RULES[key];
      }
    }
    return out as BossRules;
  }
}

/** 一套规则（去掉全局项），合并单关覆盖用。 */
export function ruleSetOf(rules: BossRules | BossRuleSet): BossRuleSet {
  return Object.fromEntries(BOSS_RULE_KEYS.map((key) => [key, rules[key]])) as BossRuleSet;
}

/** 默认值 + 单关覆盖 → 生效的规则（覆盖里不认识的老字段，例如第三批的 dailyRewardLimit，忽略）。 */
export function resolveBossRules(defaults: BossRuleSet, override: BossRuleOverride | null | undefined): BossRuleSet {
  const base = ruleSetOf(defaults as BossRules);
  if (!override || typeof override !== "object" || Array.isArray(override)) {
    return base;
  }
  const out = { ...base } as Record<string, unknown>;
  for (const key of BOSS_RULE_KEYS) {
    const value = (override as Record<string, unknown>)[key];
    if (value === undefined || value === null || Array.isArray(value)) continue;
    out[key] = isGroup(key) ? { ...(base[key] as object), ...stripNull(value as object) } : value;
  }
  return out as BossRuleSet;
}

function stripNull<T extends object>(value: T | undefined): Partial<T> {
  return Object.fromEntries(Object.entries(value ?? {}).filter(([, v]) => v !== undefined && v !== null)) as Partial<T>;
}

/**
 * 单关覆盖的保存：每一项先校验，再只留和默认值不同的项（填回默认值 = 恢复默认）。
 * 合并后的两组装备品质掉率合计都必须是 100%。返回 null 表示全部跟随默认。全局项（每日总次数等）不能单关改，传了忽略。
 */
export function compactBossRuleOverride(raw: unknown, defaults: BossRuleSet): BossRuleOverride | null {
  const input = (raw ?? {}) as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const key of BOSS_RULE_KEYS) {
    const value = input[key];
    if (value === undefined || value === null) {
      continue;
    }
    if (isGroup(key)) {
      const merged = FIELD[key]({ ...(defaults[key] as object), ...stripNull(value as object) }, PREFIX) as Record<string, number>;
      const base = defaults[key] as Record<string, number>;
      const diff = Object.fromEntries(Object.entries(merged).filter(([sub, v]) => (value as Record<string, unknown>)[sub] !== undefined && (value as Record<string, unknown>)[sub] !== null && v !== base[sub]));
      if (Object.keys(diff).length > 0) {
        out[key] = diff;
      }
      continue;
    }
    const parsed = FIELD[key](value, PREFIX);
    if (parsed !== defaults[key]) {
      out[key] = parsed;
    }
  }
  const problems = qualityProblems(resolveBossRules(defaults, out as BossRuleOverride));
  if (problems.length > 0) {
    throw new AppError("INVALID_INPUT", PREFIX + problems[0]);
  }
  return Object.keys(out).length > 0 ? (out as BossRuleOverride) : null;
}

/** 单关改过几项（后台列表「M 关已自定义」用；倍率、品质按小项算）。 */
export function customRuleCount(override: BossRuleOverride | null | undefined): number {
  if (!override) return 0;
  let count = 0;
  for (const [key, value] of Object.entries(override)) {
    if (value === undefined || value === null || !BOSS_RULE_KEYS.includes(key as keyof BossRuleSet)) continue;
    count += isGroup(key) ? Object.values(value as object).filter((v) => v !== undefined && v !== null).length : 1;
  }
  return count;
}

/** 合并后规则的问题（发布校验用：默认值改过以后，单关的部分覆盖可能让品质合计不是 100%）。 */
export function bossRuleProblems(rules: BossRuleSet): string[] {
  return qualityProblems(rules);
}

export type StoredBossStats = { attack: number; defense: number; hp: number; interval: number; statsCustom?: BossStatKey[] };

/**
 * 首领实际数值：
 * - manual：首领自己填的数值；
 * - auto：本关第一只普通怪 × 倍率（气血 / 攻击 / 防御四舍五入，出手间隔同普通怪），statsCustom 里列出的项保留手填值。
 * auto 模式但本关没有普通怪时（第四批起规则只有一套、默认自动，老的手写关卡 / 没配普通怪的关卡会这样）：用首领自己填的数值，和手填一样。
 * （返回 null 的分支留给调用方兼容，现在不会出现。）
 */
export function expandBossStats(boss: StoredBossStats, monster: StageMonster | undefined, rules: BossRuleSet): { attack: number; defense: number; hp: number; interval: number } | null {
  if (rules.statMode === "manual") {
    return { attack: boss.attack, defense: boss.defense, hp: boss.hp, interval: boss.interval };
  }
  if (!monster) {
    return { attack: boss.attack, defense: boss.defense, hp: boss.hp, interval: boss.interval };
  }
  const custom = new Set(boss.statsCustom ?? []);
  return {
    attack: custom.has("attack") ? boss.attack : Math.round(monster.attack * rules.statMul.attack),
    defense: custom.has("defense") ? boss.defense : Math.round(monster.defense * rules.statMul.defense),
    hp: custom.has("hp") ? boss.hp : Math.round(monster.hp * rules.statMul.hp),
    interval: custom.has("interval") ? boss.interval : monster.interval,
  };
}
