import { describe, expect, it } from "vitest";
import { hitDamage, simulateBattle } from "./battle.js";

const config = {
  timeLimitSeconds: 60,
  playerDefenseFactor: 0.4,
  bossDefenseFactor: 0.5,
  playerDamageFloor: 1,
  bossDamageFloor: 0,
};

describe("simulateBattle", () => {
  it("deals at least 1 damage when attack is below boss defense", () => {
    expect(hitDamage(1, 100, 0.4, 1, 1)).toBe(1);
  });

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
});
