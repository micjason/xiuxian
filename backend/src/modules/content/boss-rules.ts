/**
 * 首领规则（第三批，ADMIN_SPEC §11）：每关都有首领——普通关卡是小首领（精英，tier = elite），每章最后一关是大首领（章末，tier = chief）。
 * 全局默认值存在 content_globals.tuning.bossRules.{elite, chief}（配置概览「首领规则」两列），
 * 每关在 bosses[0].rules 里只存改过的项（灰字跟随默认，改了算「已自定义」，「恢复默认」= 删掉这一项）。
 * 只放类型、默认值、校验和合并，不依赖数据库。
 */
import { AppError } from "../../shared/errors.js";
import type { StageMonster } from "./combat-types.js";

export const BOSS_TIERS = ["elite", "chief"] as const;
export type BossTier = (typeof BOSS_TIERS)[number];
/** 怪物档次（下发给客户端，传给 monster_rig / boss_battle 的 tier）：普通怪 / 精英 / 章末首领。 */
export type MonsterTier = "normal" | BossTier;

export const BOSS_QUALITIES = ["white", "green", "blue", "purple", "orange"] as const;
export type BossQuality = (typeof BOSS_QUALITIES)[number];
export const BOSS_STAT_KEYS = ["attack", "defense", "hp", "interval"] as const;
export type BossStatKey = (typeof BOSS_STAT_KEYS)[number];

export type BossRuleSet = {
  /** auto = 本关普通怪 × 属性倍率（四舍五入，出手间隔不变）；manual = 首领自己填的数值。 */
  statMode: "auto" | "manual";
  statMul: { hp: number; attack: number; defense: number };
  /** 已击败后还能不能再打。 */
  allowRepeat: boolean;
  /** 重打给不给奖励（消耗每日次数）。 */
  repeatRewards: boolean;
  /** 每天能拿重打奖励的次数（每日重置整点换天）；0 = 不限次数挑战、不给重打奖励。 */
  dailyRewardLimit: number;
  /** 首领给 1 件本境界装备时按这个抽品质（百分比，合计 100）。 */
  gearQualityPct: Record<BossQuality, number>;
  /** 挂机中战力够了自动挑战（服务端结算时触发，只打还没击败过的首领）。 */
  autoChallenge: boolean;
  /** 自动挑战条件：战力 ≥ 推荐战力 × 这个百分比。 */
  autoChallengePowerPct: number;
  /** 自动挑战输了以后，隔多少秒再自动试一次。 */
  autoChallengeRetrySeconds: number;
  /** 解锁下一关：需要击败本关首领。 */
  unlockNeedsBossWin: boolean;
  /** 解锁下一关：需要达到下一关的境界。 */
  unlockNeedsRealm: boolean;
};

export type BossRules = Record<BossTier, BossRuleSet>;

/** 每关的覆盖：只存改过的项。 */
export type BossRuleOverride = Partial<Omit<BossRuleSet, "statMul" | "gearQualityPct">> & {
  statMul?: Partial<BossRuleSet["statMul"]>;
  gearQualityPct?: Partial<BossRuleSet["gearQualityPct"]>;
};

/** Chengpeng 定的起始值（2026-10-21）；后台配置概览可改。 */
export const DEFAULT_BOSS_RULES: BossRules = {
  elite: {
    statMode: "auto",
    statMul: { hp: 5, attack: 1.3, defense: 1.2 },
    allowRepeat: true,
    repeatRewards: false,
    dailyRewardLimit: 0,
    gearQualityPct: { white: 0, green: 70, blue: 25, purple: 5, orange: 0 },
    autoChallenge: true,
    autoChallengePowerPct: 100,
    autoChallengeRetrySeconds: 60,
    unlockNeedsBossWin: true,
    unlockNeedsRealm: true,
  },
  chief: {
    statMode: "manual",
    // 章末首领默认手填数值；只有单关改成「自动」时才用这组倍率（取自现有 3 个大首领 ÷ 本关小怪的大致比例）。
    statMul: { hp: 8.5, attack: 1.15, defense: 1.2 },
    allowRepeat: true,
    repeatRewards: true,
    dailyRewardLimit: 5,
    gearQualityPct: { white: 0, green: 50, blue: 35, purple: 13, orange: 2 },
    autoChallenge: false,
    autoChallengePowerPct: 100,
    autoChallengeRetrySeconds: 60,
    unlockNeedsBossWin: true,
    unlockNeedsRealm: true,
  },
};

const TIER_LABEL: Record<BossTier, string> = { elite: "小首领（精英）", chief: "大首领（章末）" };

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
  repeatRewards: (value, prefix) => bool(value, `${prefix}重打给奖励`),
  dailyRewardLimit: (value, prefix) => num(value, `${prefix}每日次数`, 0, 99, true),
  gearQualityPct: (value, prefix) => {
    const raw = (value ?? {}) as Record<string, unknown>;
    return Object.fromEntries(BOSS_QUALITIES.map((q) => [q, num(raw[q], `${prefix}装备品质掉率`, 0, 100)])) as BossRuleSet["gearQualityPct"];
  },
  autoChallenge: (value, prefix) => bool(value, `${prefix}允许自动挑战`),
  autoChallengePowerPct: (value, prefix) => num(value, `${prefix}自动挑战战力比例`, 1, 1000),
  autoChallengeRetrySeconds: (value, prefix) => num(value, `${prefix}自动挑战重试间隔`, 0, 86400, true),
  unlockNeedsBossWin: (value, prefix) => bool(value, `${prefix}解锁要求击败首领`),
  unlockNeedsRealm: (value, prefix) => bool(value, `${prefix}解锁要求境界`),
};

export const BOSS_RULE_KEYS = Object.keys(FIELD) as (keyof BossRuleSet)[];

function qualityTotalError(pct: BossRuleSet["gearQualityPct"]): string | null {
  const total = BOSS_QUALITIES.reduce((sum, q) => sum + pct[q], 0);
  return Math.abs(total - 100) > 0.001 ? `装备品质掉率合计要等于 100%（现在是 ${Math.round(total * 100) / 100}%）` : null;
}

/** 一整列规则的严格校验（保存配置概览时用）。缺的项用 fallback 补上。 */
export function bossRuleSetFromInput(raw: unknown, fallback: BossRuleSet, tier: BossTier): BossRuleSet {
  const input = (raw ?? {}) as Record<string, unknown>;
  const prefix = `${TIER_LABEL[tier]}：`;
  const out = {} as Record<string, unknown>;
  for (const key of BOSS_RULE_KEYS) {
    const value = input[key];
    if (key === "statMul" || key === "gearQualityPct") {
      out[key] = FIELD[key]({ ...(fallback[key] as object), ...((value ?? {}) as object) }, prefix);
    } else {
      out[key] = FIELD[key](value === undefined || value === null ? fallback[key] : value, prefix);
    }
  }
  const set = out as BossRuleSet;
  const problem = qualityTotalError(set.gearQualityPct);
  if (problem) {
    throw new AppError("INVALID_INPUT", prefix + problem);
  }
  return set;
}

export function bossRulesFromInput(raw: unknown, fallback: BossRules = DEFAULT_BOSS_RULES): BossRules {
  const input = (raw ?? {}) as Record<string, unknown>;
  return {
    elite: bossRuleSetFromInput(input.elite, fallback.elite, "elite"),
    chief: bossRuleSetFromInput(input.chief, fallback.chief, "chief"),
  };
}

/** 宽松读取（运行时用）：库里存坏的项回退代码默认值，不让游戏停。 */
export function bossRulesOf(raw: unknown): BossRules {
  try {
    return bossRulesFromInput(raw);
  } catch {
    const input = (raw ?? {}) as Record<string, unknown>;
    const out = {} as BossRules;
    for (const tier of BOSS_TIERS) {
      try {
        out[tier] = bossRuleSetFromInput(input[tier], DEFAULT_BOSS_RULES[tier], tier);
      } catch {
        out[tier] = DEFAULT_BOSS_RULES[tier];
      }
    }
    return out;
  }
}

/** 默认值 + 单关覆盖 → 生效的规则。 */
export function resolveBossRules(defaults: BossRuleSet, override: BossRuleOverride | null | undefined): BossRuleSet {
  if (!override) {
    return defaults;
  }
  return {
    ...defaults,
    ...Object.fromEntries(Object.entries(override).filter(([key, value]) => key !== "statMul" && key !== "gearQualityPct" && value !== undefined && value !== null)),
    statMul: { ...defaults.statMul, ...stripNull(override.statMul) },
    gearQualityPct: { ...defaults.gearQualityPct, ...stripNull(override.gearQualityPct) },
  } as BossRuleSet;
}

function stripNull<T extends object>(value: T | undefined): Partial<T> {
  return Object.fromEntries(Object.entries(value ?? {}).filter(([, v]) => v !== undefined && v !== null)) as Partial<T>;
}

/**
 * 单关覆盖的保存：每一项先校验，再只留和默认值不同的项（填回默认值 = 恢复默认）。
 * 合并后的装备品质掉率合计必须是 100%。返回 null 表示全部跟随默认。
 */
export function compactBossRuleOverride(raw: unknown, defaults: BossRuleSet, tier: BossTier): BossRuleOverride | null {
  const input = (raw ?? {}) as Record<string, unknown>;
  const prefix = `${TIER_LABEL[tier]}：`;
  const out: Record<string, unknown> = {};
  for (const key of BOSS_RULE_KEYS) {
    const value = input[key];
    if (value === undefined || value === null) {
      continue;
    }
    if (key === "statMul" || key === "gearQualityPct") {
      const merged = FIELD[key]({ ...(defaults[key] as object), ...stripNull(value as object) }, prefix) as Record<string, number>;
      const base = defaults[key] as Record<string, number>;
      const diff = Object.fromEntries(Object.entries(merged).filter(([sub, v]) => (value as Record<string, unknown>)[sub] !== undefined && (value as Record<string, unknown>)[sub] !== null && v !== base[sub]));
      if (Object.keys(diff).length > 0) {
        out[key] = diff;
      }
      continue;
    }
    const parsed = FIELD[key](value, prefix);
    if (parsed !== defaults[key]) {
      out[key] = parsed;
    }
  }
  const problem = qualityTotalError(resolveBossRules(defaults, out as BossRuleOverride).gearQualityPct);
  if (problem) {
    throw new AppError("INVALID_INPUT", prefix + problem);
  }
  return Object.keys(out).length > 0 ? (out as BossRuleOverride) : null;
}

/** 单关改过几项（后台列表「M 关已自定义」用；倍率、品质按小项算）。 */
export function customRuleCount(override: BossRuleOverride | null | undefined): number {
  if (!override) return 0;
  let count = 0;
  for (const [key, value] of Object.entries(override)) {
    if (value === undefined || value === null) continue;
    count += key === "statMul" || key === "gearQualityPct" ? Object.values(value as object).filter((v) => v !== undefined && v !== null).length : 1;
  }
  return count;
}

/** 合并后规则的问题（发布校验用：默认值改过以后，单关的部分覆盖可能让品质合计不是 100%）。 */
export function bossRuleProblems(rules: BossRuleSet): string[] {
  const problem = qualityTotalError(rules.gearQualityPct);
  return problem ? [problem] : [];
}

export type StoredBossStats = { attack: number; defense: number; hp: number; interval: number; statsCustom?: BossStatKey[] };

/**
 * 首领实际数值：
 * - manual：首领自己填的数值；
 * - auto：本关第一只普通怪 × 倍率（气血 / 攻击 / 防御四舍五入，出手间隔同普通怪），statsCustom 里列出的项保留手填值。
 * auto 模式但本关没有普通怪时返回 null（发布校验报错，挑战时报错）。
 */
export function expandBossStats(boss: StoredBossStats, monster: StageMonster | undefined, rules: BossRuleSet): { attack: number; defense: number; hp: number; interval: number } | null {
  if (rules.statMode === "manual") {
    return { attack: boss.attack, defense: boss.defense, hp: boss.hp, interval: boss.interval };
  }
  if (!monster) {
    return null;
  }
  const custom = new Set(boss.statsCustom ?? []);
  return {
    attack: custom.has("attack") ? boss.attack : Math.round(monster.attack * rules.statMul.attack),
    defense: custom.has("defense") ? boss.defense : Math.round(monster.defense * rules.statMul.defense),
    hp: custom.has("hp") ? boss.hp : Math.round(monster.hp * rules.statMul.hp),
    interval: custom.has("interval") ? boss.interval : monster.interval,
  };
}
