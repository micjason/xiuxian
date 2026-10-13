import { describe, expect, it } from "vitest";
import { describeBuild, statsAtPower } from "./puppet-build.js";

const weights = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };

describe("puppet build", () => {
  it("explains the standard character as balanced", () => {
    const described = describeBuild({ attack: 100, defense: 100, hp: 333, speed: 20 }, weights);
    expect(described.power).toBe(998);
    expect(described.total).toBe(998.35);
    expect(described.lines.map((line) => line.amount)).toEqual([470, 160, 316.35, 52]);
    expect(described.tendency).toBe("均衡");
  });

  it("names the stat that takes more of the power than the standard mix", () => {
    const attack = statsAtPower(1000, { attack: 0.7, defense: 0.1, hp: 0.15, speed: 0.05 }, weights);
    const speed = statsAtPower(1200, { attack: 0.25, defense: 0.1, hp: 0.2, speed: 0.45 }, weights);
    const both = statsAtPower(1000, { attack: 0.6, defense: 0.08, hp: 0.1, speed: 0.22 }, weights);
    expect(describeBuild(attack, weights).tendency).toBe("偏攻击");
    expect(describeBuild(speed, weights).tendency).toBe("偏速度");
    expect(describeBuild(both, weights).tendency).toBe("偏速度、偏攻击");
    expect(describeBuild(statsAtPower(1000, { attack: 0.47, defense: 0.16, hp: 0.32, speed: 0.05 }, weights), weights).tendency).toBe("均衡");
  });
});
