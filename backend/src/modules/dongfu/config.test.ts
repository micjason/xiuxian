import { describe, expect, it } from "vitest";
import { DEFAULT_DONGFU, dongfuConfigFromInput, dongfuReferencedItemSlugs, requireDongfu } from "./config.js";

describe("dongfuConfigFromInput", () => {
  it("accepts factory defaults", () => {
    const parsed = dongfuConfigFromInput(DEFAULT_DONGFU);
    expect(parsed.plotCount).toBe(4);
    expect(parsed.alchemyQueueLength).toBe(2);
    expect(parsed.seeds).toHaveLength(2);
    expect(parsed.recipes).toHaveLength(3);
    expect(dongfuReferencedItemSlugs(parsed)).toEqual(
      expect.arrayContaining(["seed_lingcao", "herb_lingcao", "pill_cultivate", "herb_qingxin"]),
    );
  });

  it("defaults missing spiritStones to 0", () => {
    const raw = {
      ...DEFAULT_DONGFU,
      recipes: [{ ...DEFAULT_DONGFU.recipes[0], spiritStones: undefined }],
    };
    expect(dongfuConfigFromInput(raw).recipes[0]?.spiritStones).toBe(0);
  });

  it("rejects bad plotCount / empty tables / duplicate slugs", () => {
    expect(() => dongfuConfigFromInput({ ...DEFAULT_DONGFU, plotCount: 0 })).toThrow(/地块数/);
    expect(() => dongfuConfigFromInput({ ...DEFAULT_DONGFU, seeds: [] })).toThrow(/至少配置一种种子/);
    expect(() =>
      dongfuConfigFromInput({
        ...DEFAULT_DONGFU,
        seeds: [DEFAULT_DONGFU.seeds[0]!, DEFAULT_DONGFU.seeds[0]!],
      }),
    ).toThrow(/种子编号重复/);
  });

  it("fills allocation defaults for a 0060-shaped config", () => {
    const parsed = dongfuConfigFromInput({
      plotCount: 4,
      alchemyQueueLength: 2,
      seeds: DEFAULT_DONGFU.seeds,
      recipes: DEFAULT_DONGFU.recipes,
    });
    expect(parsed.startingServants).toBe(4);
    expect(parsed.startingWood).toBe(32);
    expect(parsed.startingSeeds).toEqual([
      { itemSlug: "seed_lingcao", quantity: 8 },
      { itemSlug: "seed_qingxin", quantity: 4 },
    ]);
    expect(parsed.seedOffers).toHaveLength(2);
    expect(parsed.gardenReducePercent).toBe(5);
    expect(parsed.minDurationPercent).toBe(20);
    expect(parsed.woodItemSlug).toBe("wood_lingmu");
    expect(parsed.gardenUpgrades.map((row) => row.toLevel)).toEqual([2, 3, 4]);
    expect(parsed.alchemyUpgrades).toHaveLength(2);
  });

  it("rejects a broken upgrade ladder and a cap below the base", () => {
    expect(() =>
      dongfuConfigFromInput({
        ...DEFAULT_DONGFU,
        gardenUpgrades: [{ toLevel: 3, wood: 1, spiritStones: 0, bonus: 1 }],
      }),
    ).toThrow(/连续/);
    expect(() => dongfuConfigFromInput({ ...DEFAULT_DONGFU, maxPlotCount: 2 })).toThrow(/地块上限/);
    expect(() => dongfuConfigFromInput({ ...DEFAULT_DONGFU, gardenReducePercent: 101 })).toThrow(/缩短百分比/);
  });

  it("rejects invalid effect combinations", () => {
    expect(() =>
      dongfuConfigFromInput({
        ...DEFAULT_DONGFU,
        recipes: [{ ...DEFAULT_DONGFU.recipes[0]!, effect: { cultivationGain: 10, buffStat: "attack", buffBp: 100, durationSeconds: 10 } }],
      }),
    ).toThrow(/不能同时/);
    expect(() =>
      dongfuConfigFromInput({
        ...DEFAULT_DONGFU,
        recipes: [{ ...DEFAULT_DONGFU.recipes[0]!, effect: { buffStat: "hp", buffBp: 100, durationSeconds: 10 } }],
      }),
    ).toThrow(/attack 或 defense/);
  });
});

describe("requireDongfu", () => {
  it("maps missing / invalid to CONTENT_NOT_PUBLISHED", () => {
    expect(() => requireDongfu(null)).toThrow(/尚未发布/);
    try {
      requireDongfu({ plotCount: 0, alchemyQueueLength: 2, seeds: DEFAULT_DONGFU.seeds, recipes: DEFAULT_DONGFU.recipes });
      expect.fail("should throw");
    } catch (cause) {
      expect(cause).toMatchObject({ code: "CONTENT_NOT_PUBLISHED" });
    }
  });
});
