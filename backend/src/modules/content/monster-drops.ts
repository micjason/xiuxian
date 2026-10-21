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

/** 手动装备进随机池的一件：大境界 + 品质相同的公式 6 件之外再加进来。 */
export type PoolExtra = { slug: string; slot: string; mult: number };

/**
 * 一件装备的掉率倍数（没配 = 1）。manual：本大境界、本品质参与随机掉落的手动装备（批次②；没有就和以前完全一样）。
 */
export type DropMultOf = ((slug: string) => number) & { manual?: (majorKey: string, quality: string) => PoolExtra[] };

type PoolItem = { slug: string; dropMult?: number; origin?: string; randomDrop?: boolean; enabled?: boolean; kind?: string | null; slot?: string | null; quality?: string; requiredRealmOrder?: number };

/** 从内容里取掉率倍数表；给了境界表时，把「参与随机掉落」的手动装备按 需求境界 → 大境界 归进对应的池子。 */
export function dropMultsOf(items: PoolItem[], realms?: { sortOrder?: number; majorKey?: string }[]): DropMultOf {
  const map = new Map(items.filter((item) => item.dropMult !== undefined && item.dropMult !== 1).map((item) => [item.slug, Math.max(0, Number(item.dropMult))]));
  const fn: DropMultOf = (slug) => map.get(slug) ?? 1;
  if (realms) {
    const pools = new Map<string, PoolExtra[]>();
    for (const item of items) {
      if (item.origin !== "manual" || !item.randomDrop || item.enabled === false || item.kind !== "equipment" || !item.slot) {
        continue;
      }
      const major = realms.find((realm) => realm.sortOrder === item.requiredRealmOrder)?.majorKey;
      if (!major) {
        continue;
      }
      const key = `${major}:${item.quality ?? "white"}`;
      pools.set(key, [...(pools.get(key) ?? []), { slug: item.slug, slot: item.slot, mult: Math.max(0, Number(item.dropMult ?? 1)) }]);
    }
    if (pools.size > 0) {
      fn.manual = (majorKey, quality) => pools.get(`${majorKey}:${quality}`) ?? [];
    }
  }
  return fn;
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

/**
 * 在「大境界 + 品质」的随机池里抽一件：公式 6 件 + 参与随机掉落的手动装备，按掉率倍数分配。
 * 池里没有手动装备时和 pickSlotWeighted 完全一样（老存档的掉落结果不变）。
 */
export function pickPoolPiece(majorKey: string, quality: string, randomInt: RandomInt, multOf?: DropMultOf): { slug: string; slot: string } | null {
  const extras = multOf?.manual?.(majorKey, quality) ?? [];
  if (extras.length === 0) {
    const slot = pickSlotWeighted(majorKey, quality, randomInt, multOf);
    return slot ? { slug: gearPieceSlug(majorKey, slot, quality), slot } : null;
  }
  const pool = [
    ...GEAR_SLOTS.map((slot) => {
      const slug = gearPieceSlug(majorKey, slot.key, quality);
      return { slug, slot: slot.key, mult: multOf ? multOf(slug) : 1 };
    }),
    ...extras,
  ];
  const scale = 1000;
  const spans = pool.map((row) => Math.round(Math.max(0, row.mult) * scale));
  const total = spans.reduce((sum, value) => sum + value, 0);
  if (total <= 0) {
    return null;
  }
  let roll = randomInt(0, total);
  for (let index = 0; index < pool.length; index += 1) {
    if (roll < spans[index]!) {
      return { slug: pool[index]!.slug, slot: pool[index]!.slot };
    }
    roll -= spans[index]!;
  }
  const last = pool[pool.length - 1]!;
  return { slug: last.slug, slot: last.slot };
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
  const piece = pickPoolPiece(majorKey, quality, randomInt, multOf);
  if (!piece) {
    return null;
  }
  return { slug: piece.slug, quality, slot: piece.slot };
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
    const piece = pickPoolPiece(majorKey, "orange", randomInt, multOf);
    if (piece) {
      return { slug: piece.slug, quality: "orange", slot: piece.slot };
    }
  }
  return rollGearPiece(majorKey, repeatRewardWeights(weights), randomInt, multOf);
}
