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

export type DongfuConfig = {
  plotCount: number;
  alchemyQueueLength: number;
  seeds: DongfuSeedConfig[];
  recipes: DongfuRecipeConfig[];
};

const SLUG = /^[a-z][a-z0-9_]*$/;
const BUFF_STATS = new Set(["attack", "defense"]);

/** 出厂默认（迁移 / 测试 / 后台重置用）。 */
export const DEFAULT_DONGFU: DongfuConfig = {
  plotCount: 4,
  alchemyQueueLength: 2,
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

/** 后台保存 / 发布校验用：严格解析整份洞府配置。 */
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
  return {
    plotCount: intInRange(input.plotCount, "地块数", 1, 20),
    alchemyQueueLength: intInRange(input.alchemyQueueLength, "炼丹队列长度", 1, 10),
    seeds,
    recipes,
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
  return [...slugs];
}
