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

/** 一件装备的掉率倍数（没配 = 1）。 */
export type DropMultOf = (slug: string) => number;

/** 从内容里取掉率倍数表。 */
export function dropMultsOf(items: { slug: string; dropMult?: number }[]): DropMultOf {
  const map = new Map(items.filter((item) => item.dropMult !== undefined && item.dropMult !== 1).map((item) => [item.slug, Math.max(0, Number(item.dropMult))]));
  return (slug) => map.get(slug) ?? 1;
}

/** 6 个部位等概率抽 1 个。 */
export function pickSlot(randomInt: RandomInt): string {
  return (GEAR_SLOTS[randomInt(0, GEAR_SLOTS.length)] ?? GEAR_SLOTS[0]!).key;
}

/**
 * 按掉率倍数抽部位：本件被抽中的机会 = 本件倍数 ÷ 同大境界、同品质 6 件的倍数之和。
 * 6 件都是 ×1 时和 pickSlot 完全一样（同一个随机调用），老存档的掉落结果不变。倍数全是 0 时返回 null。
 */
export function pickSlotWeighted(majorKey: string, quality: string, randomInt: RandomInt, multOf?: DropMultOf): string | null {
  const mults = GEAR_SLOTS.map((slot) => (multOf ? multOf(gearPieceSlug(majorKey, slot.key, quality)) : 1));
  if (mults.every((value) => value === 1)) {
    return pickSlot(randomInt);
  }
  const scale = 1000;
  const spans = mults.map((value) => Math.round(Math.max(0, value) * scale));
  const total = spans.reduce((sum, value) => sum + value, 0);
  if (total <= 0) {
    return null;
  }
  let roll = randomInt(0, total);
  for (let index = 0; index < spans.length; index += 1) {
    if (roll < spans[index]!) {
      return GEAR_SLOTS[index]!.key;
    }
    roll -= spans[index]!;
  }
  return GEAR_SLOTS[GEAR_SLOTS.length - 1]!.key;
}

/** 掷一件本境界阶的装备（品质按权重、部位按掉率倍数），返回装备编号；没掉返回 null。 */
export function rollGearPiece(
  majorKey: string,
  weights: QualityWeights,
  randomInt: RandomInt,
  multOf?: DropMultOf,
): { slug: string; quality: string; slot: string } | null {
  const quality = pickQuality(weights, randomInt);
  if (!quality) {
    return null;
  }
  const slot = pickSlotWeighted(majorKey, quality, randomInt, multOf);
  if (!slot) {
    return null;
  }
  return { slug: gearPieceSlug(majorKey, slot, quality), quality, slot };
}

/** 一次击杀的掉落：先按 chanceBp（万分比）判定掉不掉，再掷装备。普通怪不掉橙装。 */
export function rollMonsterKillDrop(majorKey: string, config: MonsterDropConfig | null | undefined, randomInt: RandomInt, multOf?: DropMultOf) {
  if (!config || config.chanceBp <= 0) {
    return null;
  }
  if (randomInt(0, 10000) >= config.chanceBp) {
    return null;
  }
  return rollGearPiece(majorKey, { ...config.qualityWeights, orange: 0 }, randomInt, multOf);
}

/** 首领重复挑战的装备：品质权重同本区域，白色并入绿色（橙色单独按 orangeChanceBp 掷）。 */
export function repeatRewardWeights(weights: QualityWeights): QualityWeights {
  return { ...weights, white: 0, orange: 0, green: Number(weights.green ?? 0) + Number(weights.white ?? 0) };
}

/** 首领重复奖励的装备：先按 orangeChanceBp（万分比）判定是不是橙装，不是再按本关权重（白改绿）抽品质。 */
export function rollBossRepeatGear(majorKey: string, weights: QualityWeights, orangeChanceBp: number, randomInt: RandomInt, multOf?: DropMultOf) {
  if (orangeChanceBp > 0 && randomInt(0, 10000) < orangeChanceBp) {
    const slot = pickSlotWeighted(majorKey, "orange", randomInt, multOf);
    if (slot) {
      return { slug: gearPieceSlug(majorKey, slot, "orange"), quality: "orange", slot };
    }
  }
  return rollGearPiece(majorKey, repeatRewardWeights(weights), randomInt, multOf);
}
