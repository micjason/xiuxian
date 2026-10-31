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


  it("defaults missing discoverMode to starter and fills P1 trial/garden fields", () => {
    const raw = {
      plotCount: 4,
      alchemyQueueLength: 2,
      seeds: DEFAULT_DONGFU.seeds,
      recipes: [
        {
          recipeSlug: "pill_cultivate",
          outputItemSlug: "pill_cultivate",
          outputQty: 1,
          craftSeconds: 30,
          costs: [{ itemSlug: "herb_lingcao", count: 2 }],
        },
      ],
    };
    const parsed = dongfuConfigFromInput(raw);
    expect(parsed.recipes[0]?.discoverMode).toBe("starter");
    expect(parsed.alchemyTrialSlotCount).toBe(3);
    expect(parsed.alchemyTrialDailyLimit).toBe(20);
    expect(parsed.alchemyHintKeys).toEqual(["clash", "missing_main", "ratio_off", "near"]);
    expect(parsed.gardenAuraMax).toBe(5);
    expect(parsed.gardenAgeToAncientSeconds).toBe(86400);
    expect(parsed.gardenHastenItemSlug).toBeNull();
    expect(parsed.auraSources).toEqual([]);
  });

  it("accepts hidden recipe + seed ancient + auraSources", () => {
    const parsed = dongfuConfigFromInput({
      ...DEFAULT_DONGFU,
      seeds: [
        {
          seedSlug: "seed_lingcao",
          herbSlug: "herb_lingcao",
          growSeconds: 60,
          ancientHerbSlug: "herb_lingcao_wannian",
          ancientQty: 1,
          ageToAncientSeconds: 3600,
        },
      ],
      recipes: [
        {
          ...DEFAULT_DONGFU.recipes[0]!,
          discoverMode: "hidden",
          imperfectOutputItemSlug: "pill_cultivate_flawed",
          usageTag: "cultivate",
        },
      ],
      auraSources: [
        {
          sourceSlug: "item_lingqi_dew",
          kind: "consumable_item",
          itemSlug: "item_lingqi_dew",
          auraAdd: 1,
          lingshiCost: 0,
        },
      ],
    });
    expect(parsed.recipes[0]?.discoverMode).toBe("hidden");
    expect(parsed.recipes[0]?.imperfectOutputItemSlug).toBe("pill_cultivate_flawed");
    expect(parsed.seeds[0]?.ancientHerbSlug).toBe("herb_lingcao_wannian");
    expect(parsed.auraSources).toHaveLength(1);
    expect(dongfuReferencedItemSlugs(parsed)).toEqual(
      expect.arrayContaining(["herb_lingcao_wannian", "pill_cultivate_flawed", "item_lingqi_dew"]),
    );
  });

  it("rejects bad discoverMode", () => {
    expect(() =>
      dongfuConfigFromInput({
        ...DEFAULT_DONGFU,
        recipes: [{ ...DEFAULT_DONGFU.recipes[0]!, discoverMode: "locked" as "starter" }],
      }),
    ).toThrow(/discoverMode/);
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
