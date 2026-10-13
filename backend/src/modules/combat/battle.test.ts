import { describe, expect, it } from "vitest";
import { hitDamage, simulateBattle } from "./battle.js";

const config = { timeLimitSeconds: 60, defenseConstant: 1 };

describe("hitDamage", () => {
  it("blocks half the damage when attack equals defense", () => {
    expect(hitDamage(100, 100, 1)).toBe(50);
  });

  it("doubles the damage when both sides double", () => {
    expect(hitDamage(200, 200, 1)).toBe(2 * hitDamage(100, 100, 1));
  });

  it("deals full attack against zero defense", () => {
    expect(hitDamage(100, 0, 1)).toBe(100);
  });

  it("deals nothing with zero attack", () => {
    expect(hitDamage(0, 0, 1)).toBe(0);
    expect(hitDamage(0, 50, 1)).toBe(0);
  });

  it("never drops to a cliff when defense is far above attack", () => {
    expect(hitDamage(10, 1000, 1)).toBeGreaterThan(0);
  });
});

describe("simulateBattle", () => {
  it("times out when the boss cannot be finished in time", () => {
    const result = simulateBattle(
      { attack: 1, defense: 0, hp: 100, interval: 10 },
      { attack: 0, defense: 0, hp: 10000, interval: 10 },
      { ...config, timeLimitSeconds: 5 },
    );
    expect(result).toMatchObject({ win: false, reason: "timeout" });
  });

  it("lets the player strike first when both act at the same time", () => {
    const result = simulateBattle(
      { attack: 10, defense: 10, hp: 20, interval: 2 },
      { attack: 10, defense: 0, hp: 10, interval: 2 },
      config,
    );
    expect(result.win).toBe(true);
    expect(result.log[0]?.side).toBe("player");
    expect(result.durationSeconds).toBe(2);
  });

  it("finishes a same-level boss in about nine seconds", () => {
    const side = { attack: 100, defense: 100, hp: 333, interval: 1.25 };
    const result = simulateBattle(side, side, { ...config, timeLimitSeconds: 20 });
    expect(result).toMatchObject({ win: true, reason: "win" });
    expect(result.durationSeconds).toBeCloseTo(8.75, 6);
  });
});
