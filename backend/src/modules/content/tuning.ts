/**
 * 配置概览里的「默认数值」（content_globals.tuning，JSON）。
 * 以前写死在服务端代码里的数（装备预算比例、部位占比、功法层数系数、自动分解范围、满层功法书折算修为），
 * 以及会被关卡继承的默认掉率 / 品质权重、首领橙装概率，都放在这里。没存的项一律用 DEFAULT_TUNING。
 * 只放类型、默认值和校验，不依赖数据库，validate.ts / snapshot.ts / 游戏循环都可以引用。
 */
import { AppError } from "../../shared/errors.js";

export const TUNING_QUALITIES = ["white", "green", "blue", "purple", "orange"] as const;
export type TuningQuality = (typeof TUNING_QUALITIES)[number];
export const TUNING_SLOTS = ["weapon", "clothes", "helmet", "gloves", "shoes", "accessory"] as const;
export type TuningSlot = (typeof TUNING_SLOTS)[number];
export const SKILL_RANKS = ["yellow", "xuan", "earth", "heaven"] as const;
export type SkillRank = (typeof SKILL_RANKS)[number];

export type Tuning = {
  /** 装备预算 = 大境界第一层累计属性 × 这个比例 */
  gearBudgetRatio: number;
  /** 6 个部位各占预算的比例，合计 1 */
  slotShares: Record<TuningSlot, number>;
  /** 功法层数系数：第 1 层 / 第 2–3 层 / 第 4–6 层 / 第 7 层起 */
  skillLayerFactors: [number, number, number, number];
  /** 功法满层；满层后再用功法书折算成修为 */
  skillMaxLayers: number;
  /** 行囊满时自动分解哪些品质 */
  autoDecomposeQualities: TuningQuality[];
  /** 满层多余功法书折算修为 = 秒数 × 每秒修为 × 品阶系数 */
  bookOverflowSeconds: number;
  bookOverflowRankFactors: Record<SkillRank, number>;
  /** 普通怪每只击杀掉装备的默认概率（万分比），关卡没单独改就用它 */
  monsterDropChanceBp: number;
  /** 普通怪默认品质权重（橙固定 0：橙装只由首领掉） */
  monsterQualityWeights: Record<TuningQuality, number>;
  /** 首领重复奖励给的装备有多大概率直接是橙色（万分比） */
  bossOrangeChanceBp: number;
};

export const DEFAULT_TUNING: Tuning = {
  gearBudgetRatio: 0.55,
  slotShares: { weapon: 0.25, clothes: 0.2, helmet: 0.13, gloves: 0.12, shoes: 0.15, accessory: 0.15 },
  skillLayerFactors: [1, 1.15, 1.35, 1.6],
  skillMaxLayers: 7,
  autoDecomposeQualities: ["white", "green"],
  bookOverflowSeconds: 30,
  bookOverflowRankFactors: { yellow: 1, xuan: 2, earth: 4, heaven: 8 },
  monsterDropChanceBp: 500,
  monsterQualityWeights: { white: 70, green: 25, blue: 5, purple: 0, orange: 0 },
  bossOrangeChanceBp: 200,
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
  const autoRaw = pick(raw, "autoDecomposeQualities", DEFAULT_TUNING.autoDecomposeQualities);
  if (!Array.isArray(autoRaw) || autoRaw.some((key) => !TUNING_QUALITIES.includes(key as TuningQuality))) {
    throw new AppError("INVALID_INPUT", "自动分解范围不正确");
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
    autoDecomposeQualities: TUNING_QUALITIES.filter((q) => (autoRaw as string[]).includes(q)),
    bookOverflowSeconds: num(pick(raw, "bookOverflowSeconds", DEFAULT_TUNING.bookOverflowSeconds), "多余功法书折算秒数", 0, 86400),
    bookOverflowRankFactors: Object.fromEntries(
      SKILL_RANKS.map((rank) => [rank, num(rankRaw?.[rank] ?? DEFAULT_TUNING.bookOverflowRankFactors[rank], "功法品阶系数", 0, 1000)]),
    ) as Tuning["bookOverflowRankFactors"],
    monsterDropChanceBp: num(pick(raw, "monsterDropChanceBp", DEFAULT_TUNING.monsterDropChanceBp), "默认每只击杀掉落率", 0, 10000, true),
    monsterQualityWeights,
    bossOrangeChanceBp: num(pick(raw, "bossOrangeChanceBp", DEFAULT_TUNING.bossOrangeChanceBp), "首领橙装概率", 0, 10000, true),
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
