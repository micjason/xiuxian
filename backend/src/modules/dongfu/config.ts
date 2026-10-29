/**
 * 洞府 v1 内容配置（药园 / 炼丹）。
 * 出厂默认写入迁移 0060；运行时缺配置直接报错，不偷偷回退。
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

export function requireDongfu(raw: unknown): DongfuConfig {
  if (!raw || typeof raw !== "object") {
    throw new AppError("CONTENT_NOT_PUBLISHED", "洞府配置尚未发布");
  }
  const cfg = raw as Partial<DongfuConfig>;
  if (!Number.isInteger(cfg.plotCount) || (cfg.plotCount as number) < 1 || (cfg.plotCount as number) > 20) {
    throw new AppError("CONTENT_NOT_PUBLISHED", "洞府地块数配置不正确");
  }
  if (
    !Number.isInteger(cfg.alchemyQueueLength) ||
    (cfg.alchemyQueueLength as number) < 1 ||
    (cfg.alchemyQueueLength as number) > 10
  ) {
    throw new AppError("CONTENT_NOT_PUBLISHED", "洞府炼丹队列配置不正确");
  }
  if (!Array.isArray(cfg.seeds) || cfg.seeds.length === 0) {
    throw new AppError("CONTENT_NOT_PUBLISHED", "洞府种子表未配置");
  }
  if (!Array.isArray(cfg.recipes) || cfg.recipes.length === 0) {
    throw new AppError("CONTENT_NOT_PUBLISHED", "洞府配方表未配置");
  }
  return cfg as DongfuConfig;
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
