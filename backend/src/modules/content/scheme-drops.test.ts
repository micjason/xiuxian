import { describe, expect, it } from "vitest";
import { bookOverflowCultivation, decomposeCultivation } from "./scheme-drops.js";

describe("scheme drops", () => {
  it("converts overflow books and spare gear into cultivation", () => {
    expect(decomposeCultivation("orange", 1)).toBe(480);
    expect(bookOverflowCultivation("heaven", 1)).toBe(240);
    expect(() => decomposeCultivation("", 1)).toThrow(/品质/);
    expect(() => bookOverflowCultivation(undefined, 1)).toThrow(/技能品阶/);
  });

  it("no longer exports the legacy scheme reward roller", async () => {
    const mod = await import("./scheme-drops.js");
    expect("rollSchemeReward" in mod).toBe(false);
  });
});
