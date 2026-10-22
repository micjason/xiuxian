/**
 * 新建大境界：一次生成三层，数值按「上一大境界对应三层」比例预填。
 *
 * 预填对齐 ADMIN_SPEC §17 / realm_new.png：
 *   修为/攻/防/血/突破消耗 ×3（上一跃迁修为倍率）；速度 = 上一境同层 +10。
 * 没有上一大境界时，用炼气种子三层原值（不再乘倍率）。
 */
export const MAJOR_LAYER_LABELS = ["一层", "二层", "三层"] as const;

/**
 * 预填比例：对齐稿 §17 —— 默认取上一跃迁的修为倍率（炼气→筑基→金丹均为 ×3）；
 * 攻/防/血同乘；速度 = 上一境同层 +10；突破消耗同乘。
 */
export const MAJOR_PREFILL_MULT = {
  gain: 3,
  stat: 3,
  cost: 3,
  speedBonus: 10,
} as const;

export type MajorLayerSeed = {
  gainPerTick: number;
  breakthroughCost: number;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
};

/** 炼气三层增量（与 prototype-v12 一致），无上一境时直接采用。 */
export const SEED_MAJOR_LAYERS: MajorLayerSeed[] = [
  { gainPerTick: 1, breakthroughCost: 60, attack: 30, defense: 10, hp: 300, speed: 20 },
  { gainPerTick: 1, breakthroughCost: 300, attack: 6, defense: 2, hp: 60, speed: 0 },
  { gainPerTick: 1, breakthroughCost: 1800, attack: 7, defense: 2, hp: 70, speed: 0 },
];

function roundStat(value: number): number {
  if (!Number.isFinite(value) || value <= 0) return 0;
  return Math.max(0, Math.round(value));
}

/** 取上一大境界（编号最大的 majorName）按编号排序的最多三层；不足三层用最后一层补齐。 */
export function previousMajorLayers(
  realms: { majorName: string; sortOrder: number; gainPerTick: number; breakthroughCost: number; baseAttack: number; baseDefense: number; baseHp: number; baseSpeed: number }[],
): MajorLayerSeed[] | null {
  const named = realms.filter((row) => row.majorName.trim());
  if (named.length === 0) return null;
  const last = [...named].sort((a, b) => b.sortOrder - a.sortOrder)[0]!;
  const major = last.majorName.trim();
  const layers = named
    .filter((row) => row.majorName.trim() === major)
    .sort((a, b) => a.sortOrder - b.sortOrder)
    .map((row) => ({
      gainPerTick: row.gainPerTick,
      breakthroughCost: row.breakthroughCost,
      attack: row.baseAttack,
      defense: row.baseDefense,
      hp: row.baseHp,
      speed: row.baseSpeed,
    }));
  if (layers.length === 0) return null;
  while (layers.length < 3) {
    layers.push({ ...layers[layers.length - 1]! });
  }
  return layers.slice(0, 3);
}

export function scaleMajorLayers(previous: MajorLayerSeed[] | null): MajorLayerSeed[] {
  if (!previous) {
    return SEED_MAJOR_LAYERS.map((row) => ({ ...row }));
  }
  const m = MAJOR_PREFILL_MULT;
  return previous.slice(0, 3).map((row) => ({
    gainPerTick: roundStat(row.gainPerTick * m.gain),
    breakthroughCost: row.breakthroughCost <= 0 ? 0 : roundStat(row.breakthroughCost * m.cost),
    attack: roundStat(row.attack * m.stat),
    defense: roundStat(row.defense * m.stat),
    hp: roundStat(row.hp * m.stat),
    speed: Math.max(0, roundStat(row.speed + m.speedBonus)),
  }));
}

export type MajorLayerPreview = MajorLayerSeed & { displayName: string; majorName: string };

export function previewMajorLayers(
  realms: Parameters<typeof previousMajorLayers>[0],
  majorName: string,
): MajorLayerPreview[] {
  const name = majorName.trim();
  const seeds = scaleMajorLayers(previousMajorLayers(realms));
  return seeds.map((seed, index) => ({
    displayName: name ? `${name}${MAJOR_LAYER_LABELS[index]}` : `？${MAJOR_LAYER_LABELS[index]}`,
    majorName: name,
    ...seed,
  }));
}
