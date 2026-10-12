import { describe, expect, it } from "vitest";
import { computePower, sumReachedRealmStats } from "./stats.js";

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
});
