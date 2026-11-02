/**
 * 洞府炼器：图纸 + 材料 → 按品质表造装；顶橙；不改精粹强化公式。
 */
import type { DongfuForgeConfig, DongfuForgeBlueprint } from "./config.js";

export const FORGE_QUALITIES = ["white", "green", "blue", "purple", "orange"] as const;
export type ForgeQuality = (typeof FORGE_QUALITIES)[number];

export type ForgeJobRow = {
  id: string;
  blueprintSlug: string;
  startedAt: Date;
  readyAt: Date;
  claimedAt: Date | null;
  rolledQuality: string | null;
  outputItemSlug: string | null;
};

/** 品质权重：白绿蓝紫为主，橙按 baseOrangeChance（再 cap）。 */
export function rollForgeQuality(config: DongfuForgeConfig, rng: () => number = Math.random): ForgeQuality {
  const orangeChance = Math.min(config.orangeChanceCap, Math.max(0, config.baseOrangeChance));
  if (rng() < orangeChance) return "orange";
  // 剩余权重：白 40 / 绿 30 / 蓝 20 / 紫 10
  const r = rng();
  if (r < 0.4) return "white";
  if (r < 0.7) return "green";
  if (r < 0.9) return "blue";
  return "purple";
}

export function blueprintOf(config: DongfuForgeConfig, slug: string): DongfuForgeBlueprint {
  const bp = config.blueprints.find((row) => row.blueprintSlug === slug);
  if (!bp) {
    throw new Error(`UNKNOWN_BLUEPRINT:${slug}`);
  }
  return bp;
}

export function outputSlugForQuality(bp: DongfuForgeBlueprint, quality: ForgeQuality): string {
  const slug = bp.outputByQuality[quality];
  if (!slug) {
    throw new Error(`MISSING_OUTPUT:${bp.blueprintSlug}:${quality}`);
  }
  return slug;
}
