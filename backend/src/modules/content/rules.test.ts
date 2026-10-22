import { describe, expect, it } from "vitest";
import { readGameRules, rulesForSave, rulesFromInput } from "./rules.js";
import type { ContentSnapshot } from "./validate.js";

const input = {
  offlineCapSeconds: 3600,
  bagCapacity: 20,
  attackWeight: 4.7,
  defenseWeight: 1.6,
  hpWeight: 0.95,
  speedWeight: 2.6,
  baseInterval: 1.5,
  minInterval: 0.5,
  challengeCooldownSeconds: 0,
  timeLimitSeconds: 20,
  defenseConstant: 1,
  speedBase: 100,
  recommendedPowerMargin: 1.05,
};

function world(combat: Record<string, number>): ContentSnapshot {
  return {
    globals: {
      startingRealmSlug: "mortal",
      starterItems: [],
      offlineCapSeconds: 3600,
      bagCapacity: 20,
      powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
      combat,
    },
    realms: [],
    stages: [],
    dropTables: [],
    items: [],
    skills: [],
  };
}

describe("game rules", () => {
  it("keeps k and the recommended power margin and drops the old factors", () => {
    const rules = rulesFromInput(input);
    expect(rules.defenseConstant).toBe(1);
    expect(rules.recommendedPowerMargin).toBe(1.05);
    expect(Object.keys(rules)).not.toContain("playerDefenseFactor");
    expect(Object.keys(rules)).not.toContain("bossDamageFloor");
  });

  it("refuses zero k and zero margin", () => {
    expect(() => rulesFromInput({ ...input, defenseConstant: 0 })).toThrow("防御常数 k必须大于 0");
    expect(() => rulesFromInput({ ...input, recommendedPowerMargin: 0 })).toThrow("推荐战力倍数必须大于 0");
  });

  it("asks the admin to fill the new fields on an old world", () => {
    const old = world({ baseInterval: 1.5, minInterval: 0.5, challengeCooldownSeconds: 0, timeLimitSeconds: 20, speedBase: 100, playerDefenseFactor: 0.4 });
    expect(() => readGameRules(old)).toThrow("请先在后台填写：防御常数 k、推荐战力倍数");
  });

  it("keeps bag size and cooldown when the combat page does not send them", () => {
    const saved = rulesForSave(
      {
        attackWeight: 4.7,
        defenseWeight: 1.6,
        hpWeight: 0.95,
        speedWeight: 2.6,
        baseInterval: 1.5,
        minInterval: 0.5,
        defenseConstant: 1,
        speedBase: 100,
      },
      { offlineCapSeconds: 36000, bagCapacity: 20, combat: { challengeCooldownSeconds: 0, timeLimitSeconds: 20, recommendedPowerMargin: 1.05 } },
    );
    expect(rulesFromInput(saved)).toMatchObject({ offlineCapSeconds: 36000, bagCapacity: 20, challengeCooldownSeconds: 0, timeLimitSeconds: 20, defenseConstant: 1, recommendedPowerMargin: 1.05 });
  });

  it("reads a complete world", () => {
    const rules = readGameRules(
      world({
        baseInterval: 1.5,
        minInterval: 0.5,
        challengeCooldownSeconds: 0,
        timeLimitSeconds: 20,
        defenseConstant: 1,
        speedBase: 100,
        recommendedPowerMargin: 1.05,
      }),
    );
    expect(rules).toMatchObject({ defenseConstant: 1, recommendedPowerMargin: 1.05, speedBase: 100, timeLimitSeconds: 20 });
  });
});
