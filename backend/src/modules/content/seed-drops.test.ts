import { describe, expect, it } from "vitest";
import {
  DEFAULT_SEED_DROPS,
  resolveSeedDrops,
  rollSeedDropsForKill,
  seedDropsFromInput,
  seedDropsOf,
} from "./seed-drops.js";

describe("seed-drops", () => {
  it("parses admin percent rows into chanceBp and accepts itemId as slug", () => {
    expect(
      seedDropsFromInput([
        { itemId: "seed_lingcao", chancePercent: 8, minCount: 1, maxCount: 2 },
        { itemSlug: "seed_qingxin", chanceBp: 400, minCount: 1, maxCount: 1 },
      ]),
    ).toEqual([
      { itemSlug: "seed_lingcao", chanceBp: 800, minCount: 1, maxCount: 2 },
      { itemSlug: "seed_qingxin", chanceBp: 400, minCount: 1, maxCount: 1 },
    ]);
  });

  it("rejects duplicates and bad ranges", () => {
    expect(() => seedDropsFromInput([{ itemId: "seed_lingcao", chancePercent: 1, minCount: 1, maxCount: 1 }, { itemId: "seed_lingcao", chancePercent: 1, minCount: 1, maxCount: 1 }])).toThrow("重复");
    expect(() => seedDropsFromInput([{ itemId: "seed_lingcao", chancePercent: 101, minCount: 1, maxCount: 1 }])).toThrow("概率");
    expect(() => seedDropsFromInput([{ itemId: "seed_lingcao", chancePercent: 1, minCount: 3, maxCount: 2 }])).toThrow("最多数量");
  });

  it("merges global + per-stage override (null = global, [] = none)", () => {
    const global = DEFAULT_SEED_DROPS;
    expect(resolveSeedDrops(null, global)).toEqual(global);
    expect(resolveSeedDrops(undefined, global)).toEqual(global);
    expect(resolveSeedDrops([], global)).toEqual([]);
    expect(resolveSeedDrops([{ itemSlug: "seed_lingcao", chanceBp: 10000, minCount: 2, maxCount: 2 }], global)).toEqual([
      { itemSlug: "seed_lingcao", chanceBp: 10000, minCount: 2, maxCount: 2 },
    ]);
  });

  it("seedDropsOf falls back to defaults on garbage", () => {
    expect(seedDropsOf(null)).toEqual(DEFAULT_SEED_DROPS);
    expect(seedDropsOf({ nope: true })).toEqual(DEFAULT_SEED_DROPS);
    expect(seedDropsOf([{ itemSlug: "seed_lingcao", chanceBp: 10, minCount: 1, maxCount: 1 }, { bad: true }])).toEqual([
      { itemSlug: "seed_lingcao", chanceBp: 10, minCount: 1, maxCount: 1 },
    ]);
  });

  it("rolls each entry independently per kill", () => {
    const entries = [
      { itemSlug: "seed_lingcao", chanceBp: 10000, minCount: 1, maxCount: 1 },
      { itemSlug: "seed_qingxin", chanceBp: 0, minCount: 1, maxCount: 1 },
    ];
    expect(rollSeedDropsForKill(entries, () => 0)).toEqual([{ itemSlug: "seed_lingcao", quantity: 1 }]);
    // chanceBp 5000, random 5000 → miss (>= chance)
    expect(rollSeedDropsForKill([{ itemSlug: "seed_lingcao", chanceBp: 5000, minCount: 1, maxCount: 1 }], () => 5000)).toEqual([]);
    // hit when random < chance
    expect(rollSeedDropsForKill([{ itemSlug: "seed_lingcao", chanceBp: 5000, minCount: 2, maxCount: 2 }], () => 4999)).toEqual([
      { itemSlug: "seed_lingcao", quantity: 2 },
    ]);
  });
});
