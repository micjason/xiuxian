import { readdirSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { MONSTER_ART_KEYS } from "./art-keys.js";
import { DEFAULT_BOSS_RULES, bossRuleProblems, bossRulesFromInput, bossRulesOf, compactBossRuleOverride, customRuleCount, expandBossStats, resolveBossRules } from "./boss-rules.js";

const wolf = { name: "青鬃狼", hp: 110, attack: 24, defense: 14, interval: 1.5, killCultivation: 3 };

describe("首领规则（第三批）", () => {
  it("defaults: 精英 ×5/×1.3/×1.2 auto, first clear only, 0/70/25/5/0, auto-challenge; 章末 manual, 5 per day, 0/50/35/13/2, manual challenge", () => {
    expect(DEFAULT_BOSS_RULES.elite).toMatchObject({
      statMode: "auto",
      statMul: { hp: 5, attack: 1.3, defense: 1.2 },
      allowRepeat: true,
      repeatRewards: false,
      dailyRewardLimit: 0,
      gearQualityPct: { white: 0, green: 70, blue: 25, purple: 5, orange: 0 },
      autoChallenge: true,
      autoChallengePowerPct: 100,
      unlockNeedsBossWin: true,
      unlockNeedsRealm: true,
    });
    expect(DEFAULT_BOSS_RULES.chief).toMatchObject({
      statMode: "manual",
      repeatRewards: true,
      dailyRewardLimit: 5,
      gearQualityPct: { white: 0, green: 50, blue: 35, purple: 13, orange: 2 },
      autoChallenge: false,
    });
    expect(bossRulesFromInput(DEFAULT_BOSS_RULES)).toEqual(DEFAULT_BOSS_RULES);
  });

  it("strict input: partial columns merge onto the fallback; bad values and a quality total ≠ 100 are rejected with the tier in the message", () => {
    const saved = bossRulesFromInput({ chief: { dailyRewardLimit: 3 } });
    expect(saved.chief.dailyRewardLimit).toBe(3);
    expect(saved.elite).toEqual(DEFAULT_BOSS_RULES.elite);
    expect(() => bossRulesFromInput({ elite: { gearQualityPct: { green: 80 } } })).toThrow(/精英.*100%/);
    expect(() => bossRulesFromInput({ chief: { statMode: "nope" } })).toThrow();
    expect(() => bossRulesFromInput({ chief: { dailyRewardLimit: -1 } })).toThrow();
    // 运行时宽松读取：坏的一列回退代码默认值，好的一列保留
    const lenient = bossRulesOf({ elite: { gearQualityPct: { green: 80 } }, chief: { dailyRewardLimit: 2 } });
    expect(lenient.elite).toEqual(DEFAULT_BOSS_RULES.elite);
    expect(lenient.chief.dailyRewardLimit).toBe(2);
    expect(bossRulesOf(undefined)).toEqual(DEFAULT_BOSS_RULES);
  });

  it("per-stage override keeps only the differences; filling the default back clears it; the merged quality must still total 100", () => {
    const defaults = DEFAULT_BOSS_RULES.elite;
    expect(compactBossRuleOverride({ dailyRewardLimit: 0, statMul: { hp: 5 } }, defaults, "elite")).toBeNull();
    const override = compactBossRuleOverride({ autoChallenge: false, statMul: { hp: 6, attack: 1.3 } }, defaults, "elite");
    expect(override).toEqual({ autoChallenge: false, statMul: { hp: 6 } });
    expect(customRuleCount(override)).toBe(2);
    const resolved = resolveBossRules(defaults, override);
    expect(resolved).toMatchObject({ autoChallenge: false, statMul: { hp: 6, attack: 1.3, defense: 1.2 } });
    expect(() => compactBossRuleOverride({ gearQualityPct: { orange: 10 } }, defaults, "elite")).toThrow(/100%/);
    expect(compactBossRuleOverride({ gearQualityPct: { green: 60, orange: 10 } }, defaults, "elite")).toEqual({ gearQualityPct: { green: 60, orange: 10 } });
    // 默认值后来改了，单关的部分覆盖合计不再是 100：发布校验报出来
    expect(bossRuleProblems(resolveBossRules({ ...defaults, gearQualityPct: { white: 0, green: 50, blue: 25, purple: 5, orange: 0 } }, { gearQualityPct: { green: 60 } }))).toHaveLength(1);
  });

  it("stats: auto = the stage's first monster × multipliers (rounded, same interval), hand-filled keys in statsCustom stay; manual = as filled; auto without a monster = null", () => {
    const boss = { attack: 99, defense: 98, hp: 97, interval: 2 };
    expect(expandBossStats(boss, wolf, DEFAULT_BOSS_RULES.elite)).toEqual({ attack: 31, defense: 17, hp: 550, interval: 1.5 });
    expect(expandBossStats({ ...boss, statsCustom: ["hp", "interval"] }, wolf, DEFAULT_BOSS_RULES.elite)).toEqual({ attack: 31, defense: 17, hp: 97, interval: 2 });
    expect(expandBossStats(boss, wolf, DEFAULT_BOSS_RULES.chief)).toEqual(boss);
    expect(expandBossStats(boss, undefined, DEFAULT_BOSS_RULES.elite)).toBeNull();
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
