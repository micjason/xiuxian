import { describe, expect, it } from "vitest";
import { bookOverflowCultivation, decomposeCultivation, rollSchemeReward } from "./scheme-drops.js";
import { gearSlug } from "./numeric-scheme.js";

function scripted(values: number[]) {
  const pending = [...values];
  return (min: number, max: number) => {
    const next = pending.shift();
    if (next === undefined || next < min || next >= max) {
      throw new Error(`随机数 ${next} 不在 ${min} 到 ${max}`);
    }
    return next;
  };
}

describe("scheme drops", () => {
  it("always grants this stage's white or green piece on the first clear", () => {
    const rolled = rollSchemeReward({
      major: "qi",
      nextMajor: "foundation",
      stageIndex: 0,
      firstClear: true,
      pity: {},
      randomInt: scripted([1000, 0, 90, 9000, 9000]),
    });
    expect(rolled.grants[0]).toEqual({ slug: gearSlug("qi", "weapon", "white"), kind: "gear" });
    expect(rolled.grants.some((grant) => grant.kind === "book" || grant.kind === "upgrade")).toBe(false);
  });

  it("forces an orange piece after twice the expected misses", () => {
    const rolled = rollSchemeReward({
      major: "qi",
      nextMajor: "foundation",
      stageIndex: 4,
      firstClear: false,
      pity: { "qi:orange": 799 },
      randomInt: scripted([0, 0, 9000]),
    });
    expect(rolled.grants[0]).toEqual({ slug: gearSlug("qi", "accessory", "orange"), kind: "gear" });
    expect(rolled.pity["qi:orange"]).toBe(0);
  });

  it("converts overflow books and spare gear into cultivation", () => {
    expect(decomposeCultivation("orange", 1)).toBe(480);
    expect(bookOverflowCultivation("heaven", 1)).toBe(240);
    expect(() => decomposeCultivation("", 1)).toThrow(/品质/);
    expect(() => bookOverflowCultivation(undefined, 1)).toThrow(/功法品阶/);
  });
});
