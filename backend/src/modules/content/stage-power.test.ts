import { describe, expect, it } from "vitest";
import { stagePowerErrors, stageRecommendedPower } from "./stage-power.js";
import type { ContentSnapshot } from "./validate.js";

type Boss = { attack: number; defense: number; hp: number; interval: number };

function realm(slug: string, displayName: string, sortOrder: number, baseInterval: number | undefined) {
  return {
    slug,
    displayName,
    sortOrder,
    nextRealmSlug: null,
    tickSeconds: 1,
    gainPerTick: 1,
    breakthroughCost: 10,
    minRateBp: 10000,
    baseRateBp: 10000,
    maxRateBp: 10000,
    requiredStageSlug: null,
    recommendedPower: 0,
    baseInterval,
    enabled: true,
  };
}

function stage(slug: string, displayName: string, requiredRealmOrder: number, boss: Boss | null) {
  return {
    slug,
    displayName,
    requiredRealmOrder,
    nextStageSlug: null,
    bossDropTableSlug: "d",
    idleDropTableSlug: "d",
    firstClearDropTableSlug: "d",
    bossHp: 1,
    bossInterval: 1,
    bosses: boss ? [{ name: "首领", ...boss, drops: [] }] : [],
    recommendedPower: 0,
    enabled: true,
  };
}

const weak = { attack: 100, defense: 100, hp: 333, interval: 1.25 };
const strong = { attack: 120, defense: 120, hp: 400, interval: 1.25 };

function world(patch: Partial<ContentSnapshot> = {}): ContentSnapshot {
  return {
    globals: {
      startingRealmSlug: "qi",
      starterItems: [],
      offlineCapSeconds: 3600,
      bagCapacity: 20,
      powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
      combat: {
        baseInterval: 1.5,
        minInterval: 0.5,
        challengeCooldownSeconds: 0,
        timeLimitSeconds: 20,
        defenseConstant: 1,
        speedBase: 100,
        recommendedPowerMargin: 1.05,
      },
    },
    realms: [realm("qi", "炼气", 1, 1.5), realm("zhuji", "筑基", 2, 1.5)],
    stages: [stage("stage_a", "后山", 1, weak), stage("stage_b", "山门", 2, strong)],
    dropTables: [],
    items: [],
    skills: [],
    ...patch,
  };
}

describe("stage recommended power", () => {
  it("multiplies the first boss power by the margin", () => {
    const current = world();
    expect(stageRecommendedPower(current, current.stages[0]!)).toBe(1048);
    expect(stageRecommendedPower(current, current.stages[1]!)).toBe(1247);
  });

  it("accepts power that rises with the realm", () => {
    expect(stagePowerErrors(world())).toEqual([]);
  });

  it("rejects a higher realm stage that is not stronger", () => {
    const errors = stagePowerErrors(world({ stages: [stage("stage_a", "后山", 1, weak), stage("stage_b", "山门", 2, weak)] }));
    expect(errors).toEqual([{ slug: "stage_b", message: "推荐战力 1048 不高于低一个境界的关卡「后山」的 1048" }]);
  });

  it("does not compare stages on the same realm", () => {
    expect(stagePowerErrors(world({ stages: [stage("stage_a", "后山", 1, strong), stage("stage_b", "山门", 1, weak)] }))).toEqual([]);
  });

  it("skips stages without a boss", () => {
    expect(stagePowerErrors(world({ stages: [stage("stage_a", "后山", 1, null)] }))).toEqual([]);
  });

  it("prices a stage from the global interval when the realm has none", () => {
    const errors = stagePowerErrors(world({ realms: [realm("qi", "炼气", 1, undefined), realm("zhuji", "筑基", 2, 1.5)] }));
    expect(errors).toEqual([]);
  });

  it("reports a stage whose realm is gone", () => {
    const errors = stagePowerErrors(world({ stages: [stage("stage_a", "后山", 9, weak)] }));
    expect(errors).toEqual([{ slug: "stage_a", message: "关卡「后山」的境界不存在" }]);
  });

  it("reports missing rules instead of guessing", () => {
    const current = world();
    const errors = stagePowerErrors({ ...current, globals: { ...current.globals, combat: undefined } });
    expect(errors[0]?.message.startsWith("请先在后台填写：")).toBe(true);
  });

  it("uses the hand-filled power instead of the boss-derived value, and 0 means auto", () => {
    const current = world();
    current.stages[0]!.recommendedPower = 900;
    expect(stageRecommendedPower(current, current.stages[0]!)).toBe(900);
    expect(stageRecommendedPower(current, current.stages[1]!)).toBe(1247);
  });

  it("does not need a realm base interval when the power is hand-filled", () => {
    const current = world({ realms: [realm("qi", "炼气", 1, undefined), realm("zhuji", "筑基", 2, 1.5)] });
    current.stages[0]!.recommendedPower = 900;
    expect(stagePowerErrors(current)).toEqual([]);
  });

  it("checks that hand-filled power still rises with the realm", () => {
    const current = world();
    current.stages[0]!.recommendedPower = 2000;
    current.stages[1]!.recommendedPower = 1500;
    expect(stagePowerErrors(current)).toEqual([{ slug: "stage_b", message: "推荐战力 1500 不高于低一个境界的关卡「后山」的 2000" }]);
  });
});
