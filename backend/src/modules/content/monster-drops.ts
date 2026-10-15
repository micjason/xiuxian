import { GEAR_QUALITIES, GEAR_SLOTS, gearPieceSlug } from "./gear.js";
import type { MonsterDropConfig, QualityWeights } from "./combat-types.js";

type RandomInt = (min: number, max: number) => number;

/** 按权重挑一个品质；权重全是 0 时返回 null。randomInt 的上限是开区间。 */
export function pickQuality(weights: QualityWeights, randomInt: RandomInt): (typeof GEAR_QUALITIES)[number]["key"] | null {
  const entries = GEAR_QUALITIES.map((quality) => ({ key: quality.key, weight: Math.max(0, Number(weights[quality.key] ?? 0)) })).filter((entry) => entry.weight > 0);
  const total = entries.reduce((sum, entry) => sum + entry.weight, 0);
  if (total <= 0) {
    return null;
  }
  // 权重可以是小数：放大到整数再掷骰
  const scale = 1000;
  let roll = randomInt(0, Math.round(total * scale));
  for (const entry of entries) {
    const span = Math.round(entry.weight * scale);
    if (roll < span) {
      return entry.key;
    }
    roll -= span;
  }
  return entries[entries.length - 1]?.key ?? null;
}

/** 6 个部位等概率抽 1 个。 */
export function pickSlot(randomInt: RandomInt): string {
  return (GEAR_SLOTS[randomInt(0, GEAR_SLOTS.length)] ?? GEAR_SLOTS[0]!).key;
}

/** 掷一件本境界阶的装备（品质按权重、部位等概率），返回装备编号；没掉返回 null。 */
export function rollGearPiece(majorKey: string, weights: QualityWeights, randomInt: RandomInt): { slug: string; quality: string; slot: string } | null {
  const quality = pickQuality(weights, randomInt);
  if (!quality) {
    return null;
  }
  const slot = pickSlot(randomInt);
  return { slug: gearPieceSlug(majorKey, slot, quality), quality, slot };
}

/** 一次击杀的掉落：先按 chanceBp（万分比）判定掉不掉，再掷装备。 */
export function rollMonsterKillDrop(majorKey: string, config: MonsterDropConfig | null | undefined, randomInt: RandomInt) {
  if (!config || config.chanceBp <= 0) {
    return null;
  }
  if (randomInt(0, 10000) >= config.chanceBp) {
    return null;
  }
  return rollGearPiece(majorKey, config.qualityWeights, randomInt);
}

/** 首领重复挑战的装备：品质权重同本区域，白色并入绿色。 */
export function repeatRewardWeights(weights: QualityWeights): QualityWeights {
  return { ...weights, white: 0, green: Number(weights.green ?? 0) + Number(weights.white ?? 0) };
}
