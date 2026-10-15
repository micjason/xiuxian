const BEIJING_OFFSET_MS = 8 * 3600 * 1000;

/**
 * “今天”的编号（北京时间，每天 dayStartHour 点换天）：首领每日奖励次数按它重置。
 * 例：dayStartHour = 5 时，北京时间 10-16 04:59 还算 10-15，05:00 起算 10-16。
 */
export function rewardDayKey(now: Date, dayStartHour: number): string {
  const shifted = new Date(now.getTime() + BEIJING_OFFSET_MS - dayStartHour * 3600 * 1000);
  return shifted.toISOString().slice(0, 10);
}
