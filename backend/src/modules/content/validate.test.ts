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

  it("rejects a higher realm stage whose recommended power is not higher", () => {
    const base = draft().realms[0]!;
    const boss = { name: "首领", attack: 100, defense: 100, hp: 333, interval: 1.25, drops: [] };
    const stageOf = (slug: string, next: string | null, order: number) => ({
      slug,
      displayName: slug,
      nextStageSlug: next,
      requiredRealmOrder: order,
      bossDropTableSlug: "drop_a",
      idleDropTableSlug: "drop_a",
      firstClearDropTableSlug: "drop_a",
      bossHp: 1,
      bossInterval: 1,
      bosses: [boss],
      recommendedPower: 0,
      enabled: true,
    });
    const result = validateContent(
      draft({
        globals: {
          startingRealmSlug: "mortal",
          starterItems: [],
          offlineCapSeconds: 3600,
          bagCapacity: 20,
          powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
          combat: {
            minInterval: 0.5,
            challengeCooldownSeconds: 0,
            timeLimitSeconds: 20,
            defenseConstant: 1,
            speedBase: 100,
            recommendedPowerMargin: 1.05,
          },
        },
        realms: [
          { ...base, slug: "mortal", sortOrder: 1, nextRealmSlug: "qi", baseInterval: 1.5 },
          { ...base, slug: "qi", sortOrder: 2, nextRealmSlug: null, baseInterval: 1.5 },
        ],
        stages: [stageOf("stage_a", "stage_b", 1), stageOf("stage_b", null, 2)],
        dropTables: [{ slug: "drop_a", entries: [] }],
      }),
    );
    expect(result.errors).toEqual([
      { kind: "stage", slug: "stage_b", field: "bosses", message: "推荐战力 1048 不高于低一个境界的关卡「stage_a」的 1048" },
    ]);
  });
});
