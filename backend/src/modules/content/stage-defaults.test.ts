import { describe, expect, it } from "vitest";
import { DEFAULT_BOSS_RULES, resolveBossRules } from "./boss-rules.js";
import { bossOrangeChanceBp, resolveMonsterDrop } from "./stage-defaults.js";
import { DEFAULT_TUNING } from "./tuning.js";
import { rollBossRepeatGear, rollMonsterKillDrop } from "./monster-drops.js";

describe("empty drop overrides inherit the config-overview defaults", () => {
  it("treats null, {}, and [] as inherit, and never lets monsters roll orange", () => {
    const expected = { chanceBp: 500, qualityWeights: { white: 70, green: 25, blue: 5, purple: 0, orange: 0 } };
    expect(resolveMonsterDrop(null, DEFAULT_TUNING)).toEqual(expected);
    expect(resolveMonsterDrop({}, DEFAULT_TUNING)).toEqual(expected);
    expect(resolveMonsterDrop([], DEFAULT_TUNING)).toEqual(expected);
    expect(resolveMonsterDrop({ qualityWeights: [] }, DEFAULT_TUNING)).toEqual(expected);
    expect(resolveMonsterDrop({ chanceBp: null, qualityWeights: { white: null } }, DEFAULT_TUNING)).toEqual(expected);
    expect(resolveMonsterDrop({ chanceBp: 800 }, DEFAULT_TUNING).chanceBp).toBe(800);
    const tuned = { ...DEFAULT_TUNING, monsterDropChanceBp: 600, monsterQualityWeights: { ...DEFAULT_TUNING.monsterQualityWeights, white: 60 } };
    expect(resolveMonsterDrop([], tuned).chanceBp).toBe(600);
    expect(resolveMonsterDrop([], tuned).qualityWeights.white).toBe(60);
    expect(resolveMonsterDrop([], tuned).qualityWeights.orange).toBe(0);
    const always = () => 0;
    expect(rollMonsterKillDrop("qi", resolveMonsterDrop([], tuned), always)?.quality).not.toBe("orange");
    expect(rollBossRepeatGear("qi", { white: 1 }, 10000, always)?.quality).toBe("orange");
    expect(bossOrangeChanceBp(null, DEFAULT_TUNING)).toBe(DEFAULT_TUNING.bossOrangeChanceBp);
    expect(bossOrangeChanceBp({}, DEFAULT_TUNING)).toBe(DEFAULT_TUNING.bossOrangeChanceBp);
  });

  it("does not let an empty boss-rule array replace quality weights", () => {
    expect(resolveBossRules(DEFAULT_BOSS_RULES, [] as never).repeatGearQualityPct).toEqual(DEFAULT_BOSS_RULES.repeatGearQualityPct);
    expect(resolveBossRules(DEFAULT_BOSS_RULES, { gearQualityPct: [] as never, statMul: [] as never }).statMul).toEqual(DEFAULT_BOSS_RULES.statMul);
    expect(resolveBossRules(DEFAULT_BOSS_RULES, { gearQualityPct: [] as never }).gearQualityPct.orange).toBe(0);
    expect(DEFAULT_BOSS_RULES.repeatGearQualityPct.orange).toBeGreaterThan(0);
  });
});
