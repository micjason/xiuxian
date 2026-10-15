import { describe, expect, it } from "vitest";
import { buildFormulaPreview } from "./formula-preview.js";
import type { GameRules } from "./rules.js";
import { DEFAULT_OPTIONAL_RULES } from "./combat-types.js";

const rules: GameRules = {
  offlineCapSeconds: 36000,
  bagCapacity: 20,
  powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
  minInterval: 0.5,
  challengeCooldownSeconds: 0,
  timeLimitSeconds: 20,
  defenseConstant: 1,
  speedBase: 100,
  recommendedPowerMargin: 1.05,
  gearSpeedFactor: 0.3,
  ...DEFAULT_OPTIONAL_RULES,
};

describe("formula preview", () => {
  it("makes a larger k slow the same fight down", () => {
    const preview = buildFormulaPreview(rules);
    const atOne = preview.kCurve.find((point) => point.k === 1);
    const atOneAndHalf = preview.kCurve.find((point) => point.k === 1.5);
    expect(preview.evenDamage).toBe(50);
    expect(atOne?.durationSeconds).toBeGreaterThan(8);
    expect(atOneAndHalf?.durationSeconds).toBeGreaterThan(atOne?.durationSeconds ?? 0);
    expect(preview.raisedK.damage).toBeLessThan(preview.evenDamage);
  });

  it("lets a faster puppet overtake when the speed weight doubles", () => {
    const preview = buildFormulaPreview(rules);
    const powerOf = (name: string, rows: { name: string; power: number }[]) => rows.find((row) => row.name === name)?.power ?? 0;
    expect(powerOf("偏攻击", preview.puppets)).toBeGreaterThan(powerOf("偏速度", preview.puppets));
    expect(powerOf("偏速度", preview.speedWeightDoubled.puppets)).toBeGreaterThan(powerOf("偏攻击", preview.speedWeightDoubled.puppets));
    expect(preview.raisedSpeedBase.intervalAt20).toBeGreaterThan(preview.intervalAt20);
    const balanced = preview.puppets.find((puppet) => puppet.name === "均衡");
    expect(balanced?.lines.map((line) => line.amount)).toEqual([470, 160, 316.35, 52]);
    expect(balanced?.power).toBe(998);
  });
});
