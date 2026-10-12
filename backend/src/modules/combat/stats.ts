export type StatInput = {
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  baseInterval: number;
  minInterval: number;
  speedBase: number;
  weights: { attack: number; defense: number; hp: number; speed: number };
};

export function sumReachedRealmStats(
  realms: { sortOrder: number; attack: number; defense: number; hp: number; speed: number }[],
  currentSort: number,
): { attack: number; defense: number; hp: number; speed: number } {
  const totals = { attack: 0, defense: 0, hp: 0, speed: 0 };
  for (const realm of realms) {
    if (realm.sortOrder > currentSort) {
      continue;
    }
    totals.attack += realm.attack;
    totals.defense += realm.defense;
    totals.hp += realm.hp;
    totals.speed += realm.speed;
  }
  return totals;
}

export function ratePower(
  stats: { attack: number; defense: number; hp: number; speed: number },
  weights: { attack: number; defense: number; hp: number; speed: number },
): number {
  return Math.round(stats.attack * weights.attack + stats.defense * weights.defense + stats.hp * weights.hp + stats.speed * weights.speed);
}

export function computePower(input: StatInput): { interval: number; power: number } {
  const interval = Math.max(input.minInterval, (input.baseInterval * input.speedBase) / (input.speedBase + Math.max(input.speed, 0)));
  return { interval, power: ratePower(input, input.weights) };
}

export function breakthroughRate(input: {
  power: number;
  recommendedPower: number;
  baseRateBp: number;
  powerFactorBp: number;
  minRateBp: number;
  maxRateBp: number;
  failStreak: number;
  pityStepBp: number;
}): number {
  const ratio = input.recommendedPower > 0 ? Math.min(3, Math.max(0, input.power / input.recommendedPower)) : 1;
  let rate = input.baseRateBp + Math.round((ratio - 1) * input.powerFactorBp);
  rate = Math.min(input.maxRateBp, Math.max(input.minRateBp, rate));
  return Math.min(10000, rate + input.failStreak * input.pityStepBp);
}

export function resolveBreakthrough(input: {
  cultivation: number;
  cost: number;
  rateBp: number;
  failLossBp: number;
  failStreak: number;
  roll: number;
}): { success: boolean; cultivation: number; failStreak: number; lostCultivation: number } {
  if (input.roll < input.rateBp) {
    return {
      success: true,
      cultivation: input.cultivation - input.cost,
      failStreak: 0,
      lostCultivation: input.cost,
    };
  }
  const lost = Math.floor((input.cost * input.failLossBp) / 10000);
  return {
    success: false,
    cultivation: input.cultivation - lost,
    failStreak: input.failStreak + 1,
    lostCultivation: lost,
  };
}
