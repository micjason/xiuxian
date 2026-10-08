import { describe, expect, it } from "vitest";
import { breakthroughRate, computePower, resolveBreakthrough } from "./stats.js";

const weights = { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 };

describe("combat stats", () => {
  it("matches the documented power and interval", () => {
    const result = computePower({
      attack: 30,
      defense: 18,
      hp: 120,
      speed: 0,
      baseInterval: 1.45,
      minInterval: 0.7,
      weights,
    });
    expect(result.power).toBe(Math.round(30 + 18 * 0.8 + 120 * 0.04));
    expect(result.interval).toBeCloseTo(1.45);
  });

  it("uses the base breakthrough rate at the recommended power", () => {
    expect(
      breakthroughRate({
        power: 40,
        recommendedPower: 40,
        baseRateBp: 9000,
        powerFactorBp: 3000,
        minRateBp: 2000,
        maxRateBp: 9500,
        failStreak: 0,
        pityStepBp: 1000,
      }),
    ).toBe(9000);
  });

  it("succeeds only when the roll is below the rate", () => {
    const shared = { cultivation: 500, cost: 100, rateBp: 100, failLossBp: 3000, failStreak: 1 };
    expect(resolveBreakthrough({ ...shared, roll: 99 }).success).toBe(true);
    expect(resolveBreakthrough({ ...shared, roll: 100 }).success).toBe(false);
    expect(resolveBreakthrough({ ...shared, roll: 100 }).lostCultivation).toBe(30);
  });
});
