import { describe, expect, it } from "vitest";
import { bossPower, computePower, sumReachedRealmStats } from "./stats.js";

describe("combat power", () => {
  it("adds every reached realm and weights the four stats", () => {
    const stats = sumReachedRealmStats(
      [
        { sortOrder: 1, attack: 10, defense: 0, hp: 100, speed: 1 },
        { sortOrder: 2, attack: 20, defense: 5, hp: 0, speed: 0 },
        { sortOrder: 3, attack: 100, defense: 0, hp: 0, speed: 0 },
      ],
      2,
    );
    expect(stats).toEqual({ attack: 30, defense: 5, hp: 100, speed: 1 });
    expect(
      computePower({
        ...stats,
        baseInterval: 1.5,
        minInterval: 0.7,
        speedBase: 100,
        weights: { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 },
      }).power,
    ).toBe(Math.round(30 + 5 * 0.8 + 100 * 0.04 + 1 * 1.5));
  });

  it("turns the boss interval into an equivalent speed", () => {
    const weights = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };
    const boss = { attack: 100, defense: 100, hp: 333, interval: 1.25 };
    expect(bossPower(boss, { baseInterval: 1.5, speedBase: 100, weights })).toBeCloseTo(998.35, 6);
  });

  it("treats a boss slower than the realm interval as zero speed", () => {
    const weights = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };
    const boss = { attack: 100, defense: 100, hp: 333, interval: 2 };
    expect(bossPower(boss, { baseInterval: 1.5, speedBase: 100, weights })).toBeCloseTo(946.35, 6);
  });
});
