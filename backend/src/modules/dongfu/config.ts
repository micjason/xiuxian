/**
 * 洞府 v1 内容配置（药园 / 炼丹）。
 * 出厂默认写入迁移 0060；运行时缺配置直接报错，不偷偷回退。
 * 后台保存走 dongfuConfigFromInput（严格）；运行时 requireDongfu 复用同一套解析。
 */
import { AppError } from "../../shared/errors.js";

export type DongfuSeedConfig = {
  seedSlug: string;
  herbSlug: string;
  growSeconds: number;
};

export type DongfuRecipeCost = { itemSlug: string; count: number };

export type DongfuPillEffect = {
  cultivationGain?: number;
  buffStat?: string;
  buffBp?: number;
  durationSeconds?: number;
};

export type DongfuRecipeConfig = {
  recipeSlug: string;
  outputItemSlug: string;
  outputQty: number;
  craftSeconds: number;
  spiritStones: number;
  costs: DongfuRecipeCost[];
  effect?: DongfuPillEffect;
};

/** 升到 toLevel 的一档。bonus：药园加地块，炼丹加队列。 */
export type DongfuUpgradeTier = {
  toLevel: number;
  wood: number;
  spiritStones: number;
  bonus: number;
};

export type DongfuConfig = {
  plotCount: number;
  alchemyQueueLength: number;
  seeds: DongfuSeedConfig[];
  recipes: DongfuRecipeConfig[];
  /** 灵木物品。升级主材料。 */
  woodItemSlug: string;
  /** 玩家首次进入洞府时发放一次。 */
  startingWood: number;
  /** 玩家首次进入洞府时的灵仆总数。 */
  startingServants: number;
  /** 每名灵仆缩短成熟时间的百分比。 */
  gardenReducePercent: number;
  /** 每名灵仆缩短炼制时间的百分比。 */
  alchemyReducePercent: number;
  /** 最短为原时长的百分比。 */
  minDurationPercent: number;
  maxPlotCount: number;
  maxAlchemyQueue: number;
  gardenUpgrades: DongfuUpgradeTier[];
  alchemyUpgrades: DongfuUpgradeTier[];
};

/**
 * 出厂升级与系数。迁移 0061 的 jsonb 补丁必须与这里一致。
 * 32 灵木够：药园 2 级 + 炼丹 2 级，剩下的再升药园或炼丹其中一级。
 */
export const DEFAULT_GARDEN_UPGRADES: DongfuUpgradeTier[] = [
  { toLevel: 2, wood: 8, spiritStones: 0, bonus: 1 },
  { toLevel: 3, wood: 16, spiritStones: 0, bonus: 1 },
  { toLevel: 4, wood: 32, spiritStones: 20, bonus: 1 },
];

export const DEFAULT_ALCHEMY_UPGRADES: DongfuUpgradeTier[] = [
  { toLevel: 2, wood: 8, spiritStones: 0, bonus: 1 },
  { toLevel: 3, wood: 16, spiritStones: 0, bonus: 1 },
];

const SLUG = /^[a-z][a-z0-9_]*$/;
const BUFF_STATS = new Set(["attack", "defense"]);

/** 出厂默认（迁移 / 测试 / 后台重置用）。 */
export const DEFAULT_DONGFU: DongfuConfig = {
  plotCount: 4,
  alchemyQueueLength: 2,
  woodItemSlug: "wood_lingmu",
  startingWood: 32,
  startingServants: 4,
  gardenReducePercent: 5,
  alchemyReducePercent: 5,
  minDurationPercent: 20,
  maxPlotCount: 12,
  maxAlchemyQueue: 4,
  gardenUpgrades: DEFAULT_GARDEN_UPGRADES,
  alchemyUpgrades: DEFAULT_ALCHEMY_UPGRADES,
  seeds: [
    { seedSlug: "seed_lingcao", herbSlug: "herb_lingcao", growSeconds: 60 },
    { seedSlug: "seed_qingxin", herbSlug: "herb_qingxin", growSeconds: 120 },
  ],
  recipes: [
    {
      recipeSlug: "pill_cultivate",
      outputItemSlug: "pill_cultivate",
      outputQty: 1,
      craftSeconds: 30,
      spiritStones: 0,
      costs: [{ itemSlug: "herb_lingcao", count: 2 }],
      effect: { cultivationGain: 100 },
    },
    {
      recipeSlug: "pill_atk_temp",
      outputItemSlug: "pill_atk_temp",
      outputQty: 1,
      craftSeconds: 45,
      spiritStones: 0,
      costs: [
        { itemSlug: "herb_lingcao", count: 1 },
        { itemSlug: "herb_qingxin", count: 1 },
      ],
      effect: { buffStat: "attack", buffBp: 1000, durationSeconds: 300 },
    },
    {
      recipeSlug: "pill_def_temp",
      outputItemSlug: "pill_def_temp",
      outputQty: 1,
      craftSeconds: 45,
      spiritStones: 0,
      costs: [{ itemSlug: "herb_qingxin", count: 2 }],
      effect: { buffStat: "defense", buffBp: 1000, durationSeconds: 300 },
    },
  ],
};

function intInRange(value: unknown, label: string, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) {
    throw new AppError("INVALID_INPUT", `${label}必须是 ${min}～${max} 的整数`);
  }
  return value;
}

function intOr(value: unknown, label: string, min: number, max: number, fallback: number): number {
  if (value === undefined || value === null || value === "") return fallback;
  return intInRange(value, label, min, max);
}

function slugOf(value: unknown, label: string): string {
  if (typeof value !== "string" || !SLUG.test(value)) {
    throw new AppError("INVALID_INPUT", `${label}编号格式不正确（小写字母开头，只含小写字母数字下划线）`);
  }
  return value;
}

function parseEffect(raw: unknown, label: string): DongfuPillEffect | undefined {
  if (raw === undefined || raw === null || raw === "") {
    return undefined;
  }
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw new AppError("INVALID_INPUT", `${label}效果格式不正确`);
  }
  const input = raw as Record<string, unknown>;
  const out: DongfuPillEffect = {};
  if (input.cultivationGain !== undefined && input.cultivationGain !== null && input.cultivationGain !== "") {
    out.cultivationGain = intInRange(input.cultivationGain, `${label}修为获得`, 1, 1_000_000_000);
  }
  if (input.buffStat !== undefined && input.buffStat !== null && input.buffStat !== "") {
    if (typeof input.buffStat !== "string" || !BUFF_STATS.has(input.buffStat)) {
      throw new AppError("INVALID_INPUT", `${label}临时属性只能是 attack 或 defense`);
    }
    out.buffStat = input.buffStat;
    out.buffBp = intInRange(input.buffBp, `${label}临时属性万分比`, 1, 100_000);
    out.durationSeconds = intInRange(input.durationSeconds, `${label}临时属性时长`, 1, 86_400);
  }
  if (out.cultivationGain === undefined && out.buffStat === undefined) {
    throw new AppError("INVALID_INPUT", `${label}效果至少要填修为获得或临时属性`);
  }
  if (out.cultivationGain !== undefined && out.buffStat !== undefined) {
    throw new AppError("INVALID_INPUT", `${label}效果不能同时填修为获得和临时属性`);
  }
  return out;
}

function parseSeed(raw: unknown, index: number): DongfuSeedConfig {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new AppError("INVALID_INPUT", `种子第 ${index + 1} 行格式不正确`);
  }
  const row = raw as Record<string, unknown>;
  return {
    seedSlug: slugOf(row.seedSlug, `种子第 ${index + 1} 行种子`),
    herbSlug: slugOf(row.herbSlug, `种子第 ${index + 1} 行草药`),
    growSeconds: intInRange(row.growSeconds, `种子第 ${index + 1} 行成熟秒数`, 1, 604_800),
  };
}

function parseCost(raw: unknown, recipeLabel: string, index: number): DongfuRecipeCost {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new AppError("INVALID_INPUT", `${recipeLabel}材料第 ${index + 1} 项格式不正确`);
  }
  const row = raw as Record<string, unknown>;
  return {
    itemSlug: slugOf(row.itemSlug, `${recipeLabel}材料第 ${index + 1} 项`),
    count: intInRange(row.count, `${recipeLabel}材料第 ${index + 1} 项数量`, 1, 9999),
  };
}

function parseRecipe(raw: unknown, index: number): DongfuRecipeConfig {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new AppError("INVALID_INPUT", `配方第 ${index + 1} 行格式不正确`);
  }
  const row = raw as Record<string, unknown>;
  const label = `配方第 ${index + 1} 行`;
  if (!Array.isArray(row.costs) || row.costs.length === 0) {
    throw new AppError("INVALID_INPUT", `${label}至少要有一种材料`);
  }
  const spiritStones =
    row.spiritStones === undefined || row.spiritStones === null || row.spiritStones === ""
      ? 0
      : intInRange(row.spiritStones, `${label}灵石消耗`, 0, 1_000_000_000);
  const recipe: DongfuRecipeConfig = {
    recipeSlug: slugOf(row.recipeSlug, `${label}配方`),
    outputItemSlug: slugOf(row.outputItemSlug, `${label}产出`),
    outputQty: intInRange(row.outputQty, `${label}产出数量`, 1, 9999),
    craftSeconds: intInRange(row.craftSeconds, `${label}炼制秒数`, 1, 604_800),
    spiritStones,
    costs: row.costs.map((cost, costIndex) => parseCost(cost, label, costIndex)),
  };
  const effect = parseEffect(row.effect, label);
  if (effect) {
    recipe.effect = effect;
  }
  return recipe;
}

function parseUpgrade(raw: unknown, label: string, index: number): DongfuUpgradeTier {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new AppError("INVALID_INPUT", `${label}第 ${index + 1} 档格式不正确`);
  }
  const row = raw as Record<string, unknown>;
  const spiritStones =
    row.spiritStones === undefined || row.spiritStones === null || row.spiritStones === ""
      ? 0
      : intInRange(row.spiritStones, `${label}第 ${index + 1} 档灵石`, 0, 1_000_000_000);
  const bonus =
    row.bonus === undefined || row.bonus === null || row.bonus === ""
      ? 1
      : intInRange(row.bonus, `${label}第 ${index + 1} 档增加数量`, 1, 10);
  return {
    toLevel: intInRange(row.toLevel, `${label}第 ${index + 1} 档等级`, 2, 20),
    wood: intInRange(row.wood ?? 0, `${label}第 ${index + 1} 档灵木`, 0, 1_000_000_000),
    spiritStones,
    bonus,
  };
}

function parseUpgradeTable(raw: unknown, label: string, fallback: DongfuUpgradeTier[]): DongfuUpgradeTier[] {
  if (raw === undefined || raw === null) {
    return fallback.map((row) => ({ ...row }));
  }
  if (!Array.isArray(raw)) {
    throw new AppError("INVALID_INPUT", `${label}格式不正确`);
  }
  if (raw.length > 19) {
    throw new AppError("INVALID_INPUT", `${label}最多 19 档`);
  }
  const tiers = raw.map((row, index) => parseUpgrade(row, label, index));
  for (let index = 0; index < tiers.length; index += 1) {
    if (tiers[index]?.toLevel !== index + 2) {
      throw new AppError("INVALID_INPUT", `${label}必须从 2 级起连续排列`);
    }
  }
  return tiers;
}

/** 后台保存 / 发布校验用：严格解析整份洞府配置。缺分配字段时用出厂默认，兼容 0060 已发布配置。 */
export function dongfuConfigFromInput(raw: unknown): DongfuConfig {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new AppError("INVALID_INPUT", "洞府配置格式不正确");
  }
  const input = raw as Record<string, unknown>;
  if (!Array.isArray(input.seeds) || input.seeds.length === 0) {
    throw new AppError("INVALID_INPUT", "至少配置一种种子");
  }
  if (!Array.isArray(input.recipes) || input.recipes.length === 0) {
    throw new AppError("INVALID_INPUT", "至少配置一种配方");
  }
  const seeds = input.seeds.map(parseSeed);
  const recipes = input.recipes.map(parseRecipe);
  const seedSlugs = new Set<string>();
  for (const seed of seeds) {
    if (seedSlugs.has(seed.seedSlug)) {
      throw new AppError("INVALID_INPUT", `种子编号重复：${seed.seedSlug}`);
    }
    seedSlugs.add(seed.seedSlug);
  }
  const recipeSlugs = new Set<string>();
  for (const recipe of recipes) {
    if (recipeSlugs.has(recipe.recipeSlug)) {
      throw new AppError("INVALID_INPUT", `配方编号重复：${recipe.recipeSlug}`);
    }
    recipeSlugs.add(recipe.recipeSlug);
  }
  const plotCount = intInRange(input.plotCount, "地块数", 1, 20);
  const alchemyQueueLength = intInRange(input.alchemyQueueLength, "炼丹队列长度", 1, 10);
  const maxPlotCount = intOr(input.maxPlotCount, "药园地块上限", 1, 20, DEFAULT_DONGFU.maxPlotCount);
  const maxAlchemyQueue = intOr(input.maxAlchemyQueue, "炼丹队列上限", 1, 10, DEFAULT_DONGFU.maxAlchemyQueue);
  if (maxPlotCount < plotCount) {
    throw new AppError("INVALID_INPUT", "药园地块上限不能小于地块数");
  }
  if (maxAlchemyQueue < alchemyQueueLength) {
    throw new AppError("INVALID_INPUT", "炼丹队列上限不能小于队列长度");
  }
  const woodItemSlug =
    input.woodItemSlug === undefined || input.woodItemSlug === null || input.woodItemSlug === ""
      ? DEFAULT_DONGFU.woodItemSlug
      : slugOf(input.woodItemSlug, "灵木物品");
  return {
    plotCount,
    alchemyQueueLength,
    seeds,
    recipes,
    woodItemSlug,
    startingWood: intOr(input.startingWood, "初始灵木", 0, 9999, DEFAULT_DONGFU.startingWood),
    startingServants: intOr(input.startingServants, "初始灵仆", 0, 99, DEFAULT_DONGFU.startingServants),
    gardenReducePercent: intOr(input.gardenReducePercent, "药园每仆缩短百分比", 0, 100, DEFAULT_DONGFU.gardenReducePercent),
    alchemyReducePercent: intOr(input.alchemyReducePercent, "炼丹每仆缩短百分比", 0, 100, DEFAULT_DONGFU.alchemyReducePercent),
    minDurationPercent: intOr(input.minDurationPercent, "最短时长百分比", 1, 100, DEFAULT_DONGFU.minDurationPercent),
    maxPlotCount,
    maxAlchemyQueue,
    gardenUpgrades: parseUpgradeTable(input.gardenUpgrades, "药园升级", DEFAULT_GARDEN_UPGRADES),
    alchemyUpgrades: parseUpgradeTable(input.alchemyUpgrades, "炼丹升级", DEFAULT_ALCHEMY_UPGRADES),
  };
}

/** 运行时读取已发布配置；缺了或坏了都当未发布。 */
export function requireDongfu(raw: unknown): DongfuConfig {
  if (!raw || typeof raw !== "object") {
    throw new AppError("CONTENT_NOT_PUBLISHED", "洞府配置尚未发布");
  }
  try {
    return dongfuConfigFromInput(raw);
  } catch (cause) {
    if (cause instanceof AppError && cause.code === "INVALID_INPUT") {
      throw new AppError("CONTENT_NOT_PUBLISHED", cause.message);
    }
    throw cause;
  }
}

export function seedOf(config: DongfuConfig, seedSlug: string): DongfuSeedConfig {
  const seed = config.seeds.find((row) => row.seedSlug === seedSlug);
  if (!seed) {
    throw new AppError("INVALID_INPUT", `未知种子：${seedSlug}`);
  }
  return seed;
}

export function recipeOf(config: DongfuConfig, recipeSlug: string): DongfuRecipeConfig {
  const recipe = config.recipes.find((row) => row.recipeSlug === recipeSlug);
  if (!recipe) {
    throw new AppError("INVALID_INPUT", `未知配方：${recipeSlug}`);
  }
  return recipe;
}

/** 配置里引用到的物品编号（种子 / 草药 / 材料 / 产出）。 */
export function dongfuReferencedItemSlugs(config: DongfuConfig): string[] {
  const slugs = new Set<string>();
  for (const seed of config.seeds) {
    slugs.add(seed.seedSlug);
    slugs.add(seed.herbSlug);
  }
  for (const recipe of config.recipes) {
    slugs.add(recipe.outputItemSlug);
    for (const cost of recipe.costs) {
      slugs.add(cost.itemSlug);
    }
  }
  slugs.add(config.woodItemSlug);
  return [...slugs];
}
