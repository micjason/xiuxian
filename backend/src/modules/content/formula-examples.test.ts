import { describe, expect, it } from "vitest";
import { formulaExamples } from "./formula-examples.js";

const weights = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };

describe("formula examples", () => {
  it("uses the live damage and power functions", () => {
    const examples = formulaExamples({ defenseConstant: 1, speedBase: 100, minInterval: 0.5, weights });
    expect(examples.evenDamage).toBe(50);
    expect(examples.doubledDamage).toBe(100);
    expect(examples.standardPower).toBe(998);
    expect(examples.nakedDelta).toBe(examples.gearedDelta);
    expect(examples.intervalSeconds).toBeCloseTo(1.25, 6);
  });
});
