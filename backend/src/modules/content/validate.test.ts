import { describe, expect, it } from "vitest";
import { validateContent, type ContentSnapshot } from "./validate.js";

function draft(patch: Partial<ContentSnapshot> = {}): ContentSnapshot {
  return {
    globals: { startingRealmSlug: "mortal", starterItems: [] },
    realms: [
      {
        slug: "mortal",
        nextRealmSlug: null,
        tickSeconds: 1,
        gainPerTick: 2,
        breakthroughCost: 360,
        minRateBp: 2000,
        baseRateBp: 10000,
        maxRateBp: 10000,
        requiredStageSlug: null,
        recommendedPower: 0,
        enabled: true,
      },
    ],
    stages: [],
    dropTables: [],
    items: [],
    skills: [],
    ...patch,
  };
}

describe("validateContent", () => {
  it("accepts a single realm", () => {
    expect(validateContent(draft()).errors).toEqual([]);
  });

  it("rejects a bad slug and a missing next realm", () => {
    const result = validateContent(draft({ realms: [{ ...draft().realms[0]!, slug: "Bad", nextRealmSlug: "missing" }] }));
    expect(result.errors.some((error) => error.field === "slug")).toBe(true);
    expect(result.errors.some((error) => error.message.includes("一条链") || error.message.includes("下一环"))).toBe(true);
  });

  it("rejects deleting a published slug", () => {
    const result = validateContent(draft(), { realms: ["qi_early"], stages: [], items: [], skills: [], dropTables: [] });
    expect(result.errors.some((error) => error.slug === "qi_early")).toBe(true);
  });

  it("warns when a skill has no book", () => {
    const result = validateContent(
      draft({
        skills: [{ slug: "tuna", prerequisiteSkillSlugs: [], enabled: true }],
      }),
    );
    expect(result.errors).toEqual([]);
    expect(result.warnings.some((warning) => warning.slug === "tuna")).toBe(true);
  });
});
