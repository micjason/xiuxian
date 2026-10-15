/** 1 万分比 = 1.00 倍。修为按“整段时长 × 每节拍 × (1 + 加成)”一次取整，不在每秒或每次轮询里取整。 */
export const BASIS_POINTS = 10000;

export type SettleInput = {
  cultivation: number;
  lastSettledAt: Date;
  now: Date;
  tickSeconds: number;
  gainPerTick: number;
  /** 功法加成，万分比。可以带小数（层数系数），这里只在入口处 Math.round 一次，之后全是整数运算。 */
  bonusBp: number;
  offlineCapSeconds: number;
  /** 上次结算后不足 1 点的部分，单位是“万分之一点”，范围 [0, 10000)。没有就当 0。 */
  remainderBp?: number;
};

export type SettleResult = {
  cultivation: number;
  lastSettledAt: Date;
  countedSeconds: number;
  hitCap: boolean;
  /** 这次入账的修为（整数）。 */
  gained: number;
  /** 本次结算后剩下的不足 1 点的部分（万分之一点），要写回 player_states.cultivation_remainder_bp。 */
  remainderBp: number;
};

function safeRemainder(value: number | undefined): number {
  if (value === undefined || !Number.isFinite(value) || value <= 0) {
    return 0;
  }
  return Math.min(Math.floor(value), BASIS_POINTS - 1);
}

export function settleTicks(input: SettleInput): SettleResult {
  const carried = safeRemainder(input.remainderBp);
  const elapsed = Math.floor((input.now.getTime() - input.lastSettledAt.getTime()) / 1000);
  if (elapsed <= 0 || input.tickSeconds < 1 || input.gainPerTick <= 0) {
    return {
      cultivation: input.cultivation,
      lastSettledAt: input.tickSeconds < 1 || input.gainPerTick <= 0 ? input.now : input.lastSettledAt,
      countedSeconds: 0,
      hitCap: false,
      gained: 0,
      remainderBp: carried,
    };
  }
  const hitCap = elapsed > input.offlineCapSeconds;
  const countedSeconds = Math.min(elapsed, input.offlineCapSeconds);
  const ticks = Math.floor(countedSeconds / input.tickSeconds);
  const factorBp = BASIS_POINTS + Math.round(input.bonusBp);
  // ticks × gainPerTick × factorBp 全是整数；加上上次的余数后再除一次 10000，只取整这一次。
  const units = ticks * input.gainPerTick * Math.max(0, factorBp) + carried;
  const gained = Math.floor(units / BASIS_POINTS);
  const lastSettledAt = hitCap
    ? input.now
    : new Date(input.lastSettledAt.getTime() + ticks * input.tickSeconds * 1000);
  return {
    cultivation: input.cultivation + gained,
    lastSettledAt,
    countedSeconds,
    hitCap,
    gained,
    remainderBp: units - gained * BASIS_POINTS,
  };
}
