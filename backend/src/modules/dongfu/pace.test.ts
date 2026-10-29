import { describe, expect, it } from "vitest";
import { durationFactor, effectiveDurationMs, facilitySize, rescaleReadyAt, upgradeOffer, type UpgradeTier } from "./pace.js";

const GARDEN: UpgradeTier[] = [
  { toLevel: 2, wood: 8, spiritStones: 0, bonus: 1 },
  { toLevel: 3, wood: 16, spiritStones: 0, bonus: 1 },
];

describe("durationFactor", () => {
  it("shortens by percent per servant and floors at the minimum", () => {
    expect(durationFactor(0, 5, 20)).toBe(1);
    expect(durationFactor(4, 5, 20)).toBe(0.8);
    expect(effectiveDurationMs(60, 0.8)).toBe(48_000);
    expect(durationFactor(20, 5, 20)).toBe(0.2);
    expect(durationFactor(-3, 5, 20)).toBe(1);
  });
});

describe("rescaleReadyAt", () => {
  const started = new Date("2026-10-29T00:00:00.000Z");

  it("keeps progress and applies the new factor to the remainder", () => {
    const ready = new Date(started.getTime() + 60_000);
    const now = new Date(started.getTime() + 30_000);
    const next = rescaleReadyAt({ now, startedAt: started, readyAt: ready, baseSeconds: 60, factor: 0.8 });
    expect(next.toISOString()).toBe(new Date(now.getTime() + 24_000).toISOString());
  });

  it("leaves an already mature plot mature", () => {
    const ready = new Date(started.getTime() + 60_000);
    const now = new Date(started.getTime() + 90_000);
    const next = rescaleReadyAt({ now, startedAt: started, readyAt: ready, baseSeconds: 60, factor: 1 });
    expect(next.toISOString()).toBe(ready.toISOString());
  });
});

describe("facility upgrades", () => {
  it("adds bonus only for tiers already reached", () => {
    expect(facilitySize(4, 1, GARDEN, 12)).toBe(4);
    expect(facilitySize(4, 2, GARDEN, 12)).toBe(5);
    expect(facilitySize(4, 3, GARDEN, 3)).toBe(3);
  });

  it("reports why the next tier cannot be bought", () => {
    expect(upgradeOffer({ level: 1, tiers: GARDEN, base: 4, max: 12, woodHave: 8, spiritStones: 0 }).canUpgrade).toBe(true);
    expect(upgradeOffer({ level: 1, tiers: GARDEN, base: 4, max: 12, woodHave: 7, spiritStones: 0 })).toMatchObject({
      canUpgrade: false,
      reason: "灵木不足",
    });
    expect(upgradeOffer({ level: 3, tiers: GARDEN, base: 4, max: 12, woodHave: 99, spiritStones: 0 })).toMatchObject({
      canUpgrade: false,
      reason: "已满级",
      next: null,
    });
    expect(upgradeOffer({ level: 2, tiers: GARDEN, base: 4, max: 5, woodHave: 99, spiritStones: 0 })).toMatchObject({
      canUpgrade: false,
      reason: "已达上限",
    });
  });
});
