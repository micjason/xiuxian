import type { Tuning } from "./tuning.js";
import { AppError } from "../../shared/errors.js";

const QUALITY_CULTIVATION = { white: 1, green: 2, blue: 4, purple: 8, orange: 16 } as const;
const RANK_CULTIVATION = { yellow: 1, xuan: 2, earth: 4, heaven: 8 } as const;

function secondsCultivation(factor: number, gainPerTick: number): number {
  if (!(gainPerTick > 0)) {
    throw new AppError("INVALID_INPUT", "请先在后台填写：每秒修为");
  }
  return Math.round(30 * gainPerTick * factor);
}

export function decomposeCultivation(quality: string, gainPerTick: number): number {
  const factor = QUALITY_CULTIVATION[quality as keyof typeof QUALITY_CULTIVATION];
  if (factor === undefined) {
    throw new AppError("INVALID_INPUT", "这件装备还没有品质");
  }
  return secondsCultivation(factor, gainPerTick);
}

/** 满层后多余功法书折算的修为 = 秒数 × 每秒修为 × 品阶系数（配置概览里改，不传用默认 30 秒、黄 1 / 玄 2 / 地 4 / 天 8）。 */
export function bookOverflowCultivation(
  rank: string | null | undefined,
  gainPerTick: number,
  tuning?: Pick<Tuning, "bookOverflowSeconds" | "bookOverflowRankFactors">,
): number {
  const factors: Record<string, number> = tuning?.bookOverflowRankFactors ?? RANK_CULTIVATION;
  const factor = factors[String(rank)];
  if (factor === undefined) {
    throw new AppError("INVALID_INPUT", "请先在后台填写：技能品阶");
  }
  if (!(gainPerTick > 0)) {
    throw new AppError("INVALID_INPUT", "请先在后台填写：每秒修为");
  }
  return Math.round((tuning?.bookOverflowSeconds ?? 30) * gainPerTick * factor);
}
