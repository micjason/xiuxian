/**
 * 药园分配：灵仆只改时间效率，设施升级加地块 / 队列。
 * 纯函数，结算与单测共用。出厂百分比见 config.DEFAULT_DONGFU。
 */

export type UpgradeTier = {
  toLevel: number;
  wood: number;
  spiritStones: number;
  bonus: number;
};

/** 当前效率：1 = 原时长，下限为 minDurationPercent（例如 20 = 最短 20%）。 */
export function durationFactor(servants: number, reducePercent: number, minDurationPercent: number): number {
  const assigned = Math.max(0, Math.floor(servants));
  const reduce = Math.max(0, reducePercent);
  const min = Math.min(100, Math.max(1, minDurationPercent)) / 100;
  const raw = 1 - (assigned * reduce) / 100;
  const factor = Math.min(1, Math.max(min, raw));
  return Math.round(factor * 10000) / 10000;
}

export function effectiveDurationMs(baseSeconds: number, factor: number): number {
  return Math.max(1, Math.round(baseSeconds * 1000 * factor));
}

/**
 * 按「已完成比例」用新效率重算到期时间。
 * 已经成熟 / 炼成的不推回未来。
 */
export function rescaleReadyAt(input: {
  now: Date;
  startedAt: Date;
  readyAt: Date;
  baseSeconds: number;
  factor: number;
}): Date {
  const prevMs = input.readyAt.getTime() - input.startedAt.getTime();
  const elapsed = input.now.getTime() - input.startedAt.getTime();
  if (prevMs <= 0 || elapsed >= prevMs) {
    return input.readyAt.getTime() <= input.now.getTime() ? input.readyAt : input.now;
  }
  const progress = Math.min(1, Math.max(0, elapsed / prevMs));
  const newTotal = effectiveDurationMs(input.baseSeconds, input.factor);
  const remaining = Math.max(0, Math.round(newTotal * (1 - progress)));
  return new Date(input.now.getTime() + remaining);
}

export function facilitySize(base: number, level: number, tiers: UpgradeTier[], max: number): number {
  let extra = 0;
  for (const tier of tiers) {
    if (tier.toLevel <= level) extra += tier.bonus;
  }
  return Math.min(max, base + extra);
}

export function upgradeOffer(input: {
  level: number;
  tiers: UpgradeTier[];
  base: number;
  max: number;
  woodHave: number;
  spiritStones: number;
}): { canUpgrade: boolean; reason: string; next: UpgradeTier | null } {
  const next = input.tiers.find((tier) => tier.toLevel === input.level + 1) ?? null;
  if (!next) return { canUpgrade: false, reason: "已满级", next: null };
  const before = facilitySize(input.base, input.level, input.tiers, input.max);
  const after = facilitySize(input.base, input.level + 1, input.tiers, input.max);
  if (after <= before) return { canUpgrade: false, reason: "已达上限", next };
  if (input.woodHave < next.wood) return { canUpgrade: false, reason: "灵木不足", next };
  if (input.spiritStones < next.spiritStones) return { canUpgrade: false, reason: "灵石不足", next };
  return { canUpgrade: true, reason: "", next };
}
