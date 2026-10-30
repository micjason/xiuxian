import { describe, expect, it } from "vitest";
import { STARTING_ENHANCE_RULES, STARTING_ESSENCE_ITEM, STARTING_ESSENCE_RULES } from "../content/enhance.js";
import type { ContentSnapshot } from "../content/validate.js";
import { resolveDefaultTargetRealmId, runProgressionSim, STUCK_FAIL_DAYS } from "./progression.js";

function baseWorld(patch: Partial<ContentSnapshot> = {}): ContentSnapshot {
  const world: ContentSnapshot = {
    globals: {
      startingRealmSlug: "r1",
      starterItems: [],
      offlineCapSeconds: 28800,
      bagCapacity: 40,
      powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
      combat: {
        minInterval: 0.5,
        defenseConstant: 1,
        recommendedPowerMargin: 1.05,
        challengeCooldownSeconds: 0,
        timeLimitSeconds: 45,
        speedBase: 100,
        baseInterval: 1.5,
      },
      enhance: { ...STARTING_ENHANCE_RULES, essence: STARTING_ESSENCE_RULES },
      artSlotRules: [{ minRealmOrder: 1, slots: 2 }],
    },
    realms: [
      {
        slug: "r1",
        displayName: "炼气一层",
        majorName: "炼气",
        sortOrder: 1,
        nextRealmSlug: "r2",
        tickSeconds: 1,
        gainPerTick: 50,
        breakthroughCost: 100,
        baseAttack: 80,
        baseDefense: 20,
        baseHp: 400,
        baseSpeed: 10,
        baseInterval: 1.5,
        requiredStageSlug: null,
        recommendedPower: 0,
        enabled: true,
      },
      {
        slug: "r2",
        displayName: "炼气二层",
        majorName: "炼气",
        sortOrder: 2,
        nextRealmSlug: "dacheng_1",
        tickSeconds: 1,
        gainPerTick: 80,
        breakthroughCost: 200,
        baseAttack: 40,
        baseDefense: 10,
        baseHp: 200,
        baseSpeed: 5,
        baseInterval: 1.5,
        requiredStageSlug: "s1",
        recommendedPower: 0,
        enabled: true,
      },
      {
        slug: "dacheng_1",
        displayName: "大乘一层",
        majorName: "大乘",
        sortOrder: 3,
        nextRealmSlug: null,
        tickSeconds: 1,
        gainPerTick: 100,
        breakthroughCost: 0,
        baseAttack: 100,
        baseDefense: 40,
        baseHp: 500,
        baseSpeed: 10,
        baseInterval: 1.5,
        requiredStageSlug: null,
        recommendedPower: 0,
        enabled: true,
      },
    ],
    stages: [
      {
        slug: "s1",
        displayName: "试炼一",
        sortOrder: 1,
        requiredRealmOrder: 1,
        nextStageSlug: "s2",
        bossDropTableSlug: "d1",
        idleDropTableSlug: "d1",
        firstClearDropTableSlug: "d1",
        bossHp: 50,
        bossInterval: 1.5,
        bossAttack: 5,
        bossDefense: 0,
        bossName: "弱怪",
        bosses: [{ name: "弱怪", attack: 5, defense: 0, hp: 50, interval: 1.5, drops: [] }],
        recommendedPower: 100,
        enabled: true,
      },
      {
        slug: "s2",
        displayName: "试炼二",
        sortOrder: 2,
        requiredRealmOrder: 2,
        nextStageSlug: null,
        bossDropTableSlug: "d1",
        idleDropTableSlug: "d1",
        firstClearDropTableSlug: "d1",
        bossHp: 80,
        bossInterval: 1.5,
        bossAttack: 8,
        bossDefense: 0,
        bossName: "小强",
        bosses: [{ name: "小强", attack: 8, defense: 0, hp: 80, interval: 1.5, drops: [] }],
        recommendedPower: 200,
        enabled: true,
      },
    ],
    items: [
      {
        slug: STARTING_ESSENCE_ITEM.slug,
        displayName: STARTING_ESSENCE_ITEM.displayName,
        kind: "material",
        slot: null,
        skillSlug: null,
        quality: "orange",
        stackable: true,
        enabled: true,
      },
      {
        slug: "sword_r1",
        displayName: "炼气剑",
        kind: "equipment",
        slot: "weapon",
        skillSlug: null,
        quality: "green",
        attack: 30,
        defense: 0,
        hp: 0,
        speed: 5,
        requiredRealmOrder: 1,
        enabled: true,
      },
    ],
    skills: [
      {
        slug: "basic_atk",
        displayName: "基础剑诀",
        attack: 500,
        defense: 0,
        hp: 0,
        speed: 0,
        cultivateBonusBp: 0,
        rank: "1",
        requiredRealmOrder: 1,
        prerequisiteSkillSlugs: [],
        castMode: "auto",
        enabled: true,
      },
    ],
    dropTables: [{ slug: "d1", entries: [] }],
    ...patch,
  };
  // allow patch.stages etc to fully replace
  return { ...world, ...patch, globals: { ...world.globals, ...(patch.globals ?? {}) } };
}

describe("progression sim", () => {
  it("defaults target to 大乘一层", () => {
    const world = baseWorld();
    expect(resolveDefaultTargetRealmId(world)).toBe("dacheng_1");
  });

  it("reaches a lower target cleanly without stuck", () => {
    const world = baseWorld();
    const result = runProgressionSim(world, { targetRealmId: "r2", wallBudgetMs: 5000 });
    expect(result.stuck).toBeNull();
    expect(result.meta.truncated).toBe(false);
    expect(result.meta.targetRealmId).toBe("r2");
    expect(result.overview.some((row) => row.realmId === "r2" || row.status === "ok")).toBe(true);
    expect(result.timeline.some((e) => e.kind === "boss_win")).toBe(true);
    expect(result.timeline.some((e) => e.kind === "breakthrough")).toBe(true);
    expect(result.overview.every((row) => row.status !== "stuck")).toBe(true);
  });

  it("marks stuck after 10 consecutive lose days on an impossible boss", () => {
    const world = baseWorld({
      stages: [
        {
          slug: "wall",
          displayName: "绝壁",
          sortOrder: 1,
          requiredRealmOrder: 1,
          nextStageSlug: null,
          bossDropTableSlug: "d1",
          idleDropTableSlug: "d1",
          firstClearDropTableSlug: "d1",
          bossHp: 9_999_999,
          bossInterval: 0.5,
          bossAttack: 50_000,
          bossDefense: 50_000,
          bossName: "无敌魔君",
          bosses: [{ name: "无敌魔君", attack: 50_000, defense: 50_000, hp: 9_999_999, interval: 0.5, drops: [] }],
          recommendedPower: 1_000_000,
          enabled: true,
        },
      ],
      // 突破也卡住：需要打过 wall
      realms: [
        {
          slug: "r1",
          displayName: "炼气一层",
          majorName: "炼气",
          sortOrder: 1,
          nextRealmSlug: "dacheng_1",
          tickSeconds: 1,
          gainPerTick: 1,
          breakthroughCost: 999999999,
          baseAttack: 10,
          baseDefense: 1,
          baseHp: 50,
          baseSpeed: 1,
          baseInterval: 1.5,
          requiredStageSlug: "wall",
          recommendedPower: 0,
          enabled: true,
        },
        {
          slug: "dacheng_1",
          displayName: "大乘一层",
          majorName: "大乘",
          sortOrder: 2,
          nextRealmSlug: null,
          tickSeconds: 1,
          gainPerTick: 1,
          breakthroughCost: 0,
          baseAttack: 1,
          baseDefense: 1,
          baseHp: 1,
          baseSpeed: 1,
          baseInterval: 1.5,
          requiredStageSlug: null,
          recommendedPower: 0,
          enabled: true,
        },
      ],
    });
    const result = runProgressionSim(world, { wallBudgetMs: 5000 });
    expect(result.stuck).not.toBeNull();
    expect(result.stuck!.bossName).toBe("无敌魔君");
    expect(result.stuck!.day).toBeGreaterThanOrEqual(STUCK_FAIL_DAYS);
    expect(result.stuck!.powerGap).toBeGreaterThan(0);
    expect(result.stuck!.redLights.length).toBeGreaterThan(0);
    expect(result.overview.some((row) => row.status === "stuck")).toBe(true);
    const loses = result.timeline.filter((e) => e.kind === "boss_lose");
    expect(loses.length).toBeGreaterThanOrEqual(STUCK_FAIL_DAYS);
  });
});
