import { describe, expect, it } from "vitest";
import { MAJOR_PREFILL_MULT, SEED_MAJOR_LAYERS, scaleMajorLayers } from "./realm-major.js";

describe("realm major prefill (§17)", () => {
  it("uses 炼气 seed when there is no previous major", () => {
    expect(scaleMajorLayers(null)).toEqual(SEED_MAJOR_LAYERS);
  });

  it("scales gain/atk/def/hp/cost ×3 and speed +10 from the previous major", () => {
    const prev = [
      { gainPerTick: 9, breakthroughCost: 252000, attack: 92, defense: 31, hp: 920, speed: 10 },
      { gainPerTick: 9, breakthroughCost: 504000, attack: 41, defense: 14, hp: 410, speed: 0 },
      { gainPerTick: 9, breakthroughCost: 0, attack: 49, defense: 16, hp: 490, speed: 0 },
    ];
    const next = scaleMajorLayers(prev);
    expect(MAJOR_PREFILL_MULT).toMatchObject({ gain: 3, stat: 3, cost: 3, speedBonus: 10 });
    expect(next[0]).toEqual({
      gainPerTick: 27,
      breakthroughCost: 756000,
      attack: 276,
      defense: 93,
      hp: 2760,
      speed: 20,
    });
    expect(next[2]).toMatchObject({ breakthroughCost: 0, speed: 10 });
  });
});
