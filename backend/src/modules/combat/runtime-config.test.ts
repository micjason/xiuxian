import { describe, it, expect } from "vitest";
import { runtimeConfigOf, runtimeConfigFromInput, combatTraits, configuredSkills } from "./runtime-config.js";
describe("combat overview configuration", () => {
  it("has safe defaults and validates bounded durations/rage/speeds", () => {
    expect(runtimeConfigOf(null)).toMatchObject({ skipAfterWin: true, speeds: [1,2,3], statusDurationSeconds: 3, fogTimeLimitSeconds: 45 });
    expect(() => runtimeConfigFromInput({ rage: { max: 0 } })).toThrow();
    expect(() => runtimeConfigFromInput({ skills: { a: { effects: [{ kind: "heal", valueBp: -1 }] } } })).toThrow();
  });
  it("only running combat skills contribute configured traits and effects", () => {
    const config = runtimeConfigFromInput({ skills: { a: { critChanceBp: 1000, effects: [{ kind: "shield", valueBp: 2000 }] }, b: { dodgeChanceBp: 9000 } } });
    const skills = configuredSkills([{ slug: "a", name: "a", castMode: "auto", castEveryAttacks: 4, damageMultBp: 10000 }], config);
    expect(combatTraits(skills, config)).toMatchObject({ critChanceBp: 1000, dodgeChanceBp: 0 });
    expect(skills[0].effects?.[0]).toMatchObject({ kind: "shield", durationSeconds: 3 });
  });
});
