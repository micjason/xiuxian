/**
 * 配置概览里的「默认数值」（content_globals.tuning，JSON）。
 * 以前写死在服务端代码里的数（装备预算比例、部位占比、功法层数系数、行囊满时不发装备的来源、满层功法书折算修为），
 * 以及会被关卡继承的默认掉率 / 品质权重、首领橙装概率，都放在这里。没存的项一律用 DEFAULT_TUNING。
 * 只放类型、默认值和校验，不依赖数据库，validate.ts / snapshot.ts / 游戏循环都可以引用。
 */
import { AppError } from "../../shared/errors.js";
import { DEFAULT_BOSS_RULES, bossRulesFromInput, bossRulesOf, type BossRules } from "./boss-rules.js";
import { DEFAULT_SEED_DROPS, seedDropsFromInput, seedDropsOf, type SeedDropEntry } from "./seed-drops.js";

export const TUNING_QUALITIES = ["white", "green", "blue", "purple", "orange"] as const;
export type TuningQuality = (typeof TUNING_QUALITIES)[number];
export const TUNING_SLOTS = ["weapon", "clothes", "helmet", "gloves", "shoes", "accessory"] as const;
export type TuningSlot = (typeof TUNING_SLOTS)[number];
export const SKILL_RANKS = ["yellow", "xuan", "earth", "heaven"] as const;
export type SkillRank = (typeof SKILL_RANKS)[number];
/** 装备发放来源（和 player/grant.ts 的 GRANT_SOURCES 相同；这里单独写一份，tuning.ts 不依赖数据库模块）。 */
export const BAG_FULL_SOURCES = ["stage_drop", "boss_first", "boss_repeat", "admin_grant", "event", "mail"] as const;
export type BagFullSource = (typeof BAG_FULL_SOURCES)[number];

export type Tuning = {
  /** 装备预算 = 大境界第一层累计属性 × 这个比例 */
  gearBudgetRatio: number;
  /** 6 个部位各占预算的比例，合计 1 */
  slotShares: Record<TuningSlot, number>;
  /** 功法层数系数：第 1 层 / 第 2–3 层 / 第 4–6 层 / 第 7 层起 */
  skillLayerFactors: [number, number, number, number];
  /** 功法满层；满层后再用功法书折算成修为 */
  skillMaxLayers: number;
  /**
   * 第五批：行囊满时「不发装备」的来源（grantEquipment 里判断，返回 skipped: "bag_full"）。默认 关卡掉落 / 首领首通 / 首领重复；
   * 后台补发、邮件、活动不在里面 = 满包照发（可以超出容量）。以前的「行囊满时自动分解」（autoDecomposeQualities）已去掉：
   * 分解改为玩家自己选（SPEC_Q §17.2）。老数据里的 autoDecomposeQualities 读的时候忽略。
   */
  bagFullSkipSources: BagFullSource[];
  /** 满层多余功法书折算修为 = 秒数 × 每秒修为 × 品阶系数 */
  bookOverflowSeconds: number;
  bookOverflowRankFactors: Record<SkillRank, number>;
  /** 普通怪每只击杀掉装备的默认概率（万分比），关卡没单独改就用它 */
  monsterDropChanceBp: number;
  /** 普通怪默认品质权重（橙固定 0：橙装只由首领掉） */
  monsterQualityWeights: Record<TuningQuality, number>;
  /**
   * 已停用（第三批起橙装概率是首领规则 bossRules.*.gearQualityPct 里的橙色一档，游戏不再读这一项）。
   * 字段先留着，等后台配置概览去掉这个输入框再删。
   */
  bossOrangeChanceBp: number;
  /** 首领规则（配置概览「首领规则」两列）：小首领（精英）/ 大首领（章末）的默认值，单关可覆盖（boss-rules.ts）。 */
  bossRules: BossRules;
  /** 洞府种子掉落全局默认（配置概览「种子掉落」）；单关 content_stages.seed_drops 可覆盖。 */
  seedDrops: SeedDropEntry[];
};

export const DEFAULT_TUNING: Tuning = {
  gearBudgetRatio: 0.55,
  slotShares: { weapon: 0.25, clothes: 0.2, helmet: 0.13, gloves: 0.12, shoes: 0.15, accessory: 0.15 },
  skillLayerFactors: [1, 1.15, 1.35, 1.6],
  skillMaxLayers: 7,
  bagFullSkipSources: ["stage_drop", "boss_first", "boss_repeat"],
  bookOverflowSeconds: 30,
  bookOverflowRankFactors: { yellow: 1, xuan: 2, earth: 4, heaven: 8 },
  monsterDropChanceBp: 500,
  monsterQualityWeights: { white: 70, green: 25, blue: 5, purple: 0, orange: 0 },
  bossOrangeChanceBp: 200,
  bossRules: DEFAULT_BOSS_RULES,
  seedDrops: DEFAULT_SEED_DROPS,
};

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

type Raw = Partial<Record<keyof Tuning, unknown>> | null | undefined;

function pick<T>(raw: Raw, key: keyof Tuning, fallback: T): unknown {
  const value = raw?.[key];
  return value === undefined || value === null ? fallback : value;
}

/** 严格校验（保存时用）：缺的项取当前默认，填了就必须合法。 */
export function tuningFromInput(raw: Raw): Tuning {
  const shares = pick(raw, "slotShares", DEFAULT_TUNING.slotShares) as Record<string, unknown>;
  const slotShares = Object.fromEntries(TUNING_SLOTS.map((slot) => [slot, num(shares?.[slot] ?? DEFAULT_TUNING.slotShares[slot], "部位属性占比", 0, 1)])) as Tuning["slotShares"];
  const total = TUNING_SLOTS.reduce((sum, slot) => sum + slotShares[slot], 0);
  if (Math.abs(total - 1) > 0.0001) {
    throw new AppError("INVALID_INPUT", `部位属性占比合计要等于 100%（现在是 ${Math.round(total * 10000) / 100}%）`);
  }
  const layers = pick(raw, "skillLayerFactors", DEFAULT_TUNING.skillLayerFactors) as unknown[];
  if (!Array.isArray(layers) || layers.length !== 4) {
    throw new AppError("INVALID_INPUT", "功法层数系数要填 4 档");
  }
  const skillLayerFactors = layers.map((value) => num(value, "功法层数系数", 0.01, 100)) as Tuning["skillLayerFactors"];
  const skipRaw = pick(raw, "bagFullSkipSources", DEFAULT_TUNING.bagFullSkipSources);
  if (!Array.isArray(skipRaw) || skipRaw.some((key) => !BAG_FULL_SOURCES.includes(key as BagFullSource))) {
    throw new AppError("INVALID_INPUT", "行囊满时不发装备的来源不正确");
  }
  const rankRaw = pick(raw, "bookOverflowRankFactors", DEFAULT_TUNING.bookOverflowRankFactors) as Record<string, unknown>;
  const weightRaw = pick(raw, "monsterQualityWeights", DEFAULT_TUNING.monsterQualityWeights) as Record<string, unknown>;
  const monsterQualityWeights = Object.fromEntries(
    TUNING_QUALITIES.map((q) => [q, q === "orange" ? 0 : num(weightRaw?.[q] ?? 0, "默认品质权重", 0, 1_000_000)]),
  ) as Tuning["monsterQualityWeights"];
  if (Object.values(monsterQualityWeights).every((value) => value === 0)) {
    throw new AppError("INVALID_INPUT", "默认品质权重至少有一档大于 0");
  }
  return {
    gearBudgetRatio: num(pick(raw, "gearBudgetRatio", DEFAULT_TUNING.gearBudgetRatio), "装备预算比例", 0.01, 10),
    slotShares,
    skillLayerFactors,
    skillMaxLayers: num(pick(raw, "skillMaxLayers", DEFAULT_TUNING.skillMaxLayers), "功法满层", 1, 99, true),
    bagFullSkipSources: BAG_FULL_SOURCES.filter((key) => (skipRaw as string[]).includes(key)),
    bookOverflowSeconds: num(pick(raw, "bookOverflowSeconds", DEFAULT_TUNING.bookOverflowSeconds), "多余功法书折算秒数", 0, 86400),
    bookOverflowRankFactors: Object.fromEntries(
      SKILL_RANKS.map((rank) => [rank, num(rankRaw?.[rank] ?? DEFAULT_TUNING.bookOverflowRankFactors[rank], "功法品阶系数", 0, 1000)]),
    ) as Tuning["bookOverflowRankFactors"],
    monsterDropChanceBp: num(pick(raw, "monsterDropChanceBp", DEFAULT_TUNING.monsterDropChanceBp), "默认每只击杀掉落率", 0, 10000, true),
    monsterQualityWeights,
    bossOrangeChanceBp: num(pick(raw, "bossOrangeChanceBp", DEFAULT_TUNING.bossOrangeChanceBp), "首领橙装概率", 0, 10000, true),
    bossRules: bossRulesFromInput(pick(raw, "bossRules", DEFAULT_TUNING.bossRules), DEFAULT_BOSS_RULES),
    seedDrops: seedDropsFromInput(pick(raw, "seedDrops", DEFAULT_TUNING.seedDrops), { label: "种子掉落" }),
  };
}

/** 宽松读取（运行时用）：库里存坏了也不让游戏停，坏的项回退默认。 */
export function tuningOf(raw: Raw): Tuning {
  try {
    return tuningFromInput(raw);
  } catch {
    const out = { ...DEFAULT_TUNING } as Record<string, unknown>;
    for (const key of Object.keys(DEFAULT_TUNING) as (keyof Tuning)[]) {
      try {
        out[key] = tuningFromInput({ [key]: raw?.[key] } as Raw)[key];
      } catch {
        out[key] = DEFAULT_TUNING[key];
      }
    }
    // 首领规则按列、按项回退（一项存坏不影响另一列）
    out.bossRules = bossRulesOf(raw?.bossRules);
    out.seedDrops = seedDropsOf(raw?.seedDrops);
    return out as Tuning;
  }
}

/** 功法第 level 层的系数：1 / 2–3 / 4–6 / 7 层起。 */
export function layerFactorOf(tuning: Pick<Tuning, "skillLayerFactors">, level: number): number {
  const [one, two, four, seven] = tuning.skillLayerFactors;
  if (level >= 7) return seven;
  if (level >= 4) return four;
  if (level >= 2) return two;
  return one;
}
