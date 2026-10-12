export function settleTicks(input: {
  cultivation: number;
  lastSettledAt: Date;
  now: Date;
  tickSeconds: number;
  gainPerTick: number;
  bonusBp: number;
  offlineCapSeconds: number;
}): { cultivation: number; lastSettledAt: Date; countedSeconds: number; hitCap: boolean } {
  const elapsed = Math.floor((input.now.getTime() - input.lastSettledAt.getTime()) / 1000);
  if (elapsed <= 0 || input.tickSeconds < 1 || input.gainPerTick <= 0) {
    return {
      cultivation: input.cultivation,
      lastSettledAt: input.tickSeconds < 1 || input.gainPerTick <= 0 ? input.now : input.lastSettledAt,
      countedSeconds: 0,
      hitCap: false,
    };
  }
  const hitCap = elapsed > input.offlineCapSeconds;
  const countedSeconds = Math.min(elapsed, input.offlineCapSeconds);
  const ticks = Math.floor(countedSeconds / input.tickSeconds);
  const perTick = Math.floor((input.gainPerTick * (10000 + input.bonusBp)) / 10000);
  const lastSettledAt = hitCap
    ? input.now
    : new Date(input.lastSettledAt.getTime() + ticks * input.tickSeconds * 1000);
  return {
    cultivation: input.cultivation + ticks * perTick,
    lastSettledAt,
    countedSeconds,
    hitCap,
  };
}
