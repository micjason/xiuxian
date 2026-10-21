/**
 * 关卡继承配置概览的默认值。
 * 关卡里只存「单独改过」的项（monster_drop 里缺的或 null 的项 = 跟随默认），
 * 这样改了配置概览，没改过的关卡会一起变。
 */
import type { BossRepeatReward, MonsterDropConfig, MonsterDropOverride, QualityWeights } from "./combat-types.js";
import { TUNING_QUALITIES, type Tuning } from "./tuning.js";

/** 普通怪不掉橙装（橙装只由首领掉）。 */
export const MONSTER_QUALITIES = ["white", "green", "blue", "purple"] as const;

function present(value: unknown): value is number {
  return value !== undefined && value !== null && Number.isFinite(Number(value));
}

/** 关卡覆盖 + 默认值 → 完整的掉落配置（橙固定为 0）。 */
export function resolveMonsterDrop(override: MonsterDropOverride | null | undefined, tuning: Pick<Tuning, "monsterDropChanceBp" | "monsterQualityWeights">): MonsterDropConfig {
  const weights: QualityWeights = {};
  for (const quality of MONSTER_QUALITIES) {
    const own = override?.qualityWeights?.[quality];
    weights[quality] = present(own) ? Number(own) : tuning.monsterQualityWeights[quality];
  }
  weights.orange = 0;
  const chance = override?.chanceBp;
  return { chanceBp: present(chance) ? Number(chance) : tuning.monsterDropChanceBp, qualityWeights: weights };
}

/** 关卡里改过的项数（掉率 + 4 档权重）。 */
export function customDropCount(override: MonsterDropOverride | null | undefined): number {
  let count = present(override?.chanceBp) ? 1 : 0;
  for (const quality of MONSTER_QUALITIES) {
    if (present(override?.qualityWeights?.[quality])) {
      count += 1;
    }
  }
  return count;
}

/** 只留和默认值不同的项（保存时用：填回默认值等于「恢复默认」）。 */
export function compactDropOverride(override: MonsterDropOverride | null | undefined, tuning: Pick<Tuning, "monsterDropChanceBp" | "monsterQualityWeights">): MonsterDropOverride | null {
  const out: MonsterDropOverride = {};
  if (present(override?.chanceBp) && Number(override?.chanceBp) !== tuning.monsterDropChanceBp) {
    out.chanceBp = Number(override?.chanceBp);
  }
  const weights: NonNullable<MonsterDropOverride["qualityWeights"]> = {};
  for (const quality of MONSTER_QUALITIES) {
    const own = override?.qualityWeights?.[quality];
    if (present(own) && Number(own) !== tuning.monsterQualityWeights[quality]) {
      weights[quality] = Number(own);
    }
  }
  if (Object.keys(weights).length > 0) {
    out.qualityWeights = weights;
  }
  return Object.keys(out).length > 0 ? out : null;
}

/** 首领重复奖励装备直接给橙色的概率（万分比）。 */
export function bossOrangeChanceBp(repeat: Pick<BossRepeatReward, "orangeChanceBp"> | null | undefined, tuning: Pick<Tuning, "bossOrangeChanceBp">): number {
  return present(repeat?.orangeChanceBp) ? Number(repeat?.orangeChanceBp) : tuning.bossOrangeChanceBp;
}

export { TUNING_QUALITIES };
