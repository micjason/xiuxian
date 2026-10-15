import { describe, expect, it } from "vitest";
import { hitDamage, simulateBattle } from "../combat/battle.js";
import { ratePower } from "../combat/stats.js";
import { buildScheme, bossOf, gearSlug, intervalOf, schemeBudgetPower, schemeWorld, standardPanel, SCHEME_TIME_LIMIT_SECONDS, SCHEME_WEIGHTS } from "./numeric-scheme.js";
import { equipmentPowerErrors, validateContent } from "./validate.js";
import { stagePowerErrors } from "./stage-power.js";

describe("numeric scheme", () => {
  const scheme = buildScheme();
  const world = schemeWorld(scheme);

  it("stores realm deltas, one-second cultivation, and a 1.5 second interval", () => {
    expect(scheme.realms).toHaveLength(15);
    expect(scheme.realms[0]).toMatchObject({ slug: "qi_early", baseAttack: 10, baseDefense: 10, baseHp: 33, baseSpeed: 0, breakthroughCost: 210 });
    expect(scheme.realms[1]).toMatchObject({ baseAttack: 2, baseSpeed: 4, breakthroughCost: 273 });
    expect(scheme.realms.every((realm) => realm.baseInterval === 1.5 && realm.gainPerTick === 1 && realm.tickSeconds === 1)).toBe(true);
    const summed = scheme.realms.slice(0, 3).reduce((sum, realm) => sum + realm.baseAttack, 0);
    expect(summed).toBe(14);
  });

  it("prices one white weapon at its slot share of the gear budget", () => {
    const weapon = scheme.items.find((item) => item.slug === gearSlug("qi", "weapon", "white"));
    expect(weapon).toBeDefined();
    const power = ratePower(weapon ?? { attack: 0, defense: 0, hp: 0, speed: 0 }, SCHEME_WEIGHTS);
    expect(Math.abs(power - Math.round(schemeBudgetPower(0) * 0.25))).toBeLessThanOrEqual(1);
    expect(ratePower(weapon ?? { attack: 0, defense: 0, hp: 0, speed: 0 }, SCHEME_WEIGHTS)).toBe(power);
  });

  it("keeps same-slot qualities proportional inside one major realm", () => {
    expect(equipmentPowerErrors(world.items)).toEqual([]);
    expect(stagePowerErrors(world)).toEqual([]);
    expect(validateContent(world)).toEqual({ errors: [], warnings: [] });
    expect(scheme.skills.filter((skill) => skill.slug.startsWith("skill_qi_atk_heaven"))[0]?.attack).toBe(1800);
  });

  it("finishes the early standard characters against their mid bosses in 8 to 12 seconds", () => {
    const durations: number[] = [];
    for (const index of [1, 4, 7, 10, 13]) {
      const panel = standardPanel(index);
      const boss = bossOf(index);
      const result = simulateBattle(
        { ...panel, interval: intervalOf(panel.speed) },
        { attack: boss.attack, defense: boss.defense, hp: boss.hp, interval: boss.interval },
        { timeLimitSeconds: SCHEME_TIME_LIMIT_SECONDS, defenseConstant: 1 },
      );
      expect(result.win).toBe(true);
      expect(result.durationSeconds).toBeLessThanOrEqual(12);
      durations.push(result.durationSeconds);
    }
    expect(durations[0]).toBeGreaterThanOrEqual(8);
    expect(durations[1]).toBeGreaterThanOrEqual(8);
    for (let index = 1; index < durations.length; index += 1) {
      const previous = durations[index - 1];
      const current = durations[index];
      if (previous === undefined || current === undefined) {
        throw new Error("中期首领用时没有算出来");
      }
      expect(current).toBeLessThan(previous);
    }
  });

  it("lets a puppet 5 percent stronger win and a puppet 5 percent weaker lose", () => {
    const panel = standardPanel(1);
    const scale = (factor: number) => ({
      attack: panel.attack * factor,
      defense: panel.defense * factor,
      hp: panel.hp * factor,
      speed: panel.speed * factor,
      interval: intervalOf(panel.speed * factor),
    });
    const weaker = scale(0.95);
    const stronger = scale(1.05);
    expect(ratePower(stronger, SCHEME_WEIGHTS)).toBeGreaterThan(ratePower(panel, SCHEME_WEIGHTS) * 1.05 - 1);
    expect(simulateBattle(stronger, weaker, { timeLimitSeconds: SCHEME_TIME_LIMIT_SECONDS, defenseConstant: 1 }).win).toBe(true);
    expect(simulateBattle(weaker, stronger, { timeLimitSeconds: SCHEME_TIME_LIMIT_SECONDS, defenseConstant: 1 }).win).toBe(false);
    expect(hitDamage(panel.attack * 2, panel.defense * 2, 1)).toBeCloseTo(hitDamage(panel.attack, panel.defense, 1) * 2);
  });
});
