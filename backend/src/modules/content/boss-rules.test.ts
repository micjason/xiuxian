import { readdirSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { MONSTER_ART_KEYS } from "./art-keys.js";
import { DEFAULT_BOSS_RULES, bossRuleProblems, bossRulesFromInput, bossRulesOf, compactBossRuleOverride, customRuleCount, expandBossStats, legacyBossRules, resolveBossRules } from "./boss-rules.js";

const wolf = { name: "青鬃狼", hp: 110, attack: 24, defense: 14, interval: 1.5, killCultivation: 3 };

describe("首领规则（第四批：一套规则）", () => {
  it("defaults: one rule set — auto ×6.5/×1.55/×1.4, first-clear 0/70/25/5/0, repeat 0/50/35/13/2 with rewards, auto-challenge, idle boss every 1000 waves not counted; 5 per day in total", () => {
    expect(DEFAULT_BOSS_RULES).toEqual({
      statMode: "auto",
      statMul: { hp: 6.5, attack: 1.55, defense: 1.4 },
      allowRepeat: true,
      repeatRewards: true,
      gearQualityPct: { white: 0, green: 70, blue: 25, purple: 5, orange: 0 },
      repeatGearQualityPct: { white: 0, green: 50, blue: 35, purple: 13, orange: 2 },
      autoChallenge: true,
      autoChallengePowerPct: 100,
      autoChallengeRetrySeconds: 60,
      idleSpawn: true,
      idleSpawnWaves: 1000,
      idleSpawnCountsDaily: false,
      unlockNeedsBossWin: true,
      unlockNeedsRealm: true,
      dailyChallengeTotal: 5,
      idleSpawnMaxPerSettle: 20,
    });
    expect(bossRulesFromInput(DEFAULT_BOSS_RULES)).toEqual(DEFAULT_BOSS_RULES);
  });

  it("strict input: partial input merges onto the fallback; bad values and a quality total ≠ 100 are rejected", () => {
    const saved = bossRulesFromInput({ dailyChallengeTotal: 3, idleSpawnWaves: 500, repeatGearQualityPct: { green: 52, orange: 0 } });
    expect(saved).toMatchObject({ dailyChallengeTotal: 3, idleSpawnWaves: 500, repeatGearQualityPct: { white: 0, green: 52, blue: 35, purple: 13, orange: 0 } });
    expect(() => bossRulesFromInput({ gearQualityPct: { green: 80 } })).toThrow(/首通装备品质掉率.*100%/);
    expect(() => bossRulesFromInput({ repeatGearQualityPct: { green: 80 } })).toThrow(/重复奖励装备品质掉率.*100%/);
    expect(() => bossRulesFromInput({ statMode: "nope" })).toThrow();
    expect(() => bossRulesFromInput({ dailyChallengeTotal: -1 })).toThrow();
    expect(() => bossRulesFromInput({ idleSpawnWaves: 0 })).toThrow();
    // 运行时宽松读取：坏的项回退代码默认值，好的项保留
    const lenient = bossRulesOf({ gearQualityPct: { green: 80 }, dailyChallengeTotal: 2, idleSpawnWaves: "x" });
    expect(lenient.gearQualityPct).toEqual(DEFAULT_BOSS_RULES.gearQualityPct);
    expect(lenient.dailyChallengeTotal).toBe(2);
    expect(lenient.idleSpawnWaves).toBe(1000);
    expect(bossRulesOf(undefined)).toEqual(DEFAULT_BOSS_RULES);
  });

  it("the old two-column format { elite, chief } is read as one set: elite's base, chief's quality as the repeat quality, chief's daily limit as the daily total", () => {
    const legacy = {
      elite: { statMode: "auto", statMul: { hp: 6, attack: 1.3, defense: 1.2 }, allowRepeat: true, repeatRewards: false, dailyRewardLimit: 0, gearQualityPct: { white: 0, green: 60, blue: 30, purple: 10, orange: 0 }, autoChallenge: true, autoChallengePowerPct: 120, autoChallengeRetrySeconds: 30, unlockNeedsBossWin: true, unlockNeedsRealm: false },
      chief: { statMode: "manual", dailyRewardLimit: 4, gearQualityPct: { white: 0, green: 40, blue: 40, purple: 15, orange: 5 }, autoChallenge: false },
    };
    expect(legacyBossRules(legacy)).not.toBeNull();
    expect(legacyBossRules(DEFAULT_BOSS_RULES)).toBeNull();
    expect(bossRulesOf(legacy)).toEqual({
      ...DEFAULT_BOSS_RULES,
      statMul: { hp: 6, attack: 1.3, defense: 1.2 },
      gearQualityPct: { white: 0, green: 60, blue: 30, purple: 10, orange: 0 },
      repeatGearQualityPct: { white: 0, green: 40, blue: 40, purple: 15, orange: 5 },
      autoChallengePowerPct: 120,
      autoChallengeRetrySeconds: 30,
      unlockNeedsRealm: false,
      dailyChallengeTotal: 4,
    });
    expect(bossRulesFromInput(legacy)).toEqual(bossRulesOf(legacy));
  });

  it("per-stage override keeps only the differences; global-only keys and old keys are ignored; the merged quality must still total 100", () => {
    const defaults = DEFAULT_BOSS_RULES;
    expect(compactBossRuleOverride({ idleSpawnWaves: 1000, statMul: { hp: 6.5 }, dailyChallengeTotal: 9, dailyRewardLimit: 3 }, defaults)).toBeNull();
    const override = compactBossRuleOverride({ autoChallenge: false, idleSpawnWaves: 200, idleSpawnCountsDaily: true, statMul: { hp: 6, attack: 1.55 } }, defaults);
    expect(override).toEqual({ autoChallenge: false, idleSpawnWaves: 200, idleSpawnCountsDaily: true, statMul: { hp: 6 } });
    expect(customRuleCount(override)).toBe(4);
    expect(customRuleCount({ dailyRewardLimit: 3 } as never)).toBe(0);
    const resolved = resolveBossRules(defaults, override);
    expect(resolved).toMatchObject({ autoChallenge: false, idleSpawnWaves: 200, statMul: { hp: 6, attack: 1.55, defense: 1.4 } });
    expect(resolved).not.toHaveProperty("dailyChallengeTotal");
    expect(resolveBossRules(defaults, { dailyRewardLimit: 3 } as never)).not.toHaveProperty("dailyRewardLimit");
    expect(() => compactBossRuleOverride({ gearQualityPct: { orange: 10 } }, defaults)).toThrow(/100%/);
    expect(compactBossRuleOverride({ repeatGearQualityPct: { green: 48, orange: 4 } }, defaults)).toEqual({ repeatGearQualityPct: { green: 48, orange: 4 } });
    // 默认值后来改了，单关的部分覆盖合计不再是 100：发布校验报出来
    expect(bossRuleProblems(resolveBossRules({ ...defaults, gearQualityPct: { white: 0, green: 50, blue: 25, purple: 5, orange: 0 } }, { gearQualityPct: { green: 60 } }))).toHaveLength(1);
  });

  it("stats: auto = the stage's first monster × multipliers (rounded, same interval), hand-filled keys in statsCustom stay; manual = as filled; auto without a monster = as filled (第四批)", () => {
    const boss = { attack: 99, defense: 98, hp: 97, interval: 2 };
    expect(expandBossStats(boss, wolf, DEFAULT_BOSS_RULES)).toEqual({ attack: 37, defense: 20, hp: 715, interval: 1.5 });
    expect(expandBossStats({ ...boss, statsCustom: ["hp", "interval"] }, wolf, DEFAULT_BOSS_RULES)).toEqual({ attack: 37, defense: 20, hp: 97, interval: 2 });
    expect(expandBossStats(boss, wolf, { ...DEFAULT_BOSS_RULES, statMode: "manual" })).toEqual(boss);
    expect(expandBossStats(boss, undefined, DEFAULT_BOSS_RULES)).toEqual(boss);
  });

  it("the monster art list matches the client sprites (game/assets/art/q/sprites/mon_*.png)", () => {
    const dir = new URL("../../../../game/assets/art/q/sprites/", import.meta.url);
    const sprites = readdirSync(dir)
      .filter((name) => /^mon_.+\.png$/.test(name))
      .map((name) => name.slice(4, -4))
      .sort();
    expect(MONSTER_ART_KEYS.map((row) => row.key).sort()).toEqual(sprites);
  });
});
