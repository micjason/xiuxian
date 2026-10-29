import { describe, expect, it } from "vitest";
import { DEFAULT_SKILLS } from "./default-skills.js";
import { resolveFxType, skillFxProblem } from "./skill-fx.js";

describe("skill fx defaults", () => {
  it("seeds nine real fx types and only auto or passive", () => {
    expect(DEFAULT_SKILLS.length).toBeGreaterThanOrEqual(8);
    expect(new Set(DEFAULT_SKILLS.map((skill) => skill.fxType))).toEqual(
      new Set(["slash", "thunder", "fire", "heal_circle", "ice", "wind", "poison", "gold_light", "shield"]),
    );
    expect(DEFAULT_SKILLS.every((skill) => skill.castMode === "auto" || skill.castMode === "passive")).toBe(true);
    expect(DEFAULT_SKILLS.every((skill) => skill.fx.type === skill.fxType)).toBe(true);
    expect(JSON.stringify(DEFAULT_SKILLS)).not.toContain("manual");
    expect(JSON.stringify(DEFAULT_SKILLS)).not.toContain("大招");
  });

  it("keeps the real type when the resource exists and falls back only when it does not", () => {
    const bases = ["slash", "thunder", "fire", "heal_circle"];
    expect(resolveFxType("ice", [...bases, "ice"])).toBe("ice");
    expect(resolveFxType("ice", bases)).toBe("thunder");
    expect(resolveFxType("wind", bases)).toBe("slash");
    expect(resolveFxType("poison", bases)).toBe("fire");
    expect(resolveFxType("gold_light", bases)).toBe("slash");
    expect(resolveFxType("gold", ["gold_light"])).toBe("gold_light");
    expect(resolveFxType("shield", bases)).toBe("heal_circle");
    expect(resolveFxType("meteor", bases)).toBe("slash");
  });

  it("rejects a manual cast and a mismatched fx type", () => {
    expect(skillFxProblem({ type: "gold" }, "gold_light")).toBe("表现参数的 type 不正确");
    expect(skillFxProblem({ type: "slash" }, "fire")).toBe("表现参数的 type 要和表现类型一致");
    expect(skillFxProblem({ type: "gold_light", primary: "#FFD45C", scale: 1 }, "gold_light")).toBeNull();
  });
});
