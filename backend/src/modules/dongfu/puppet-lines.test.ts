import { describe, expect, it } from "vitest";
import { DEFAULT_PUPPET } from "./config.js";
import {
  applyWarehouseGain,
  buildPuppetDto,
  defaultPuppetProgress,
  settlePuppetLines,
  storageCap,
  upgradeCostOf,
} from "./puppet-lines.js";

describe("puppet-lines settle", () => {
  it("produces meat and consumes meat for wood line", () => {
    const start = defaultPuppetProgress(DEFAULT_PUPPET, new Date("2026-11-02T00:00:00.000Z"));
    start.lines.meat.workers = 6;
    start.lines.wood.workers = 2;
    start.lines.herb.workers = 0;
    start.lines.stone.workers = 0;
    start.lines.meat.stored = 100;
    const after = settlePuppetLines(start, DEFAULT_PUPPET, new Date("2026-11-02T01:00:00.000Z"));
    // 肉：仓库衰减进账后再被木线吃 4
    const meatCap = storageCap(DEFAULT_PUPPET, "meat", 1);
    const meatAfterProd = applyWarehouseGain(100, meatCap, 6 * 2.5);
    expect(after.lines.meat.stored).toBeCloseTo(meatAfterProd - 4, 5);
    const woodCap = storageCap(DEFAULT_PUPPET, "wood", 1);
    expect(after.lines.wood.stored).toBeCloseTo(applyWarehouseGain(0, woodCap, 2 * 1.0), 5);
  });

  it("stops non-meat production when meat empty", () => {
    const start = defaultPuppetProgress(DEFAULT_PUPPET, new Date("2026-11-02T00:00:00.000Z"));
    start.lines.meat.workers = 0;
    start.lines.wood.workers = 4;
    start.lines.meat.stored = 0;
    const after = settlePuppetLines(start, DEFAULT_PUPPET, new Date("2026-11-02T02:00:00.000Z"));
    expect(after.lines.wood.stored).toBe(0);
    const dto = buildPuppetDto(after, DEFAULT_PUPPET, 8);
    expect(dto.meatStarved).toBe(true);
    expect(dto.lines.find((l) => l.id === "wood")?.stoppedReason).toBe("meat_empty");
  });

  it("approaches storage cap with diminishing yield (never exceeds)", () => {
    const start = defaultPuppetProgress(DEFAULT_PUPPET, new Date("2026-11-02T00:00:00.000Z"));
    start.lines.meat.workers = 6;
    start.lines.wood.workers = 0;
    start.lines.herb.workers = 0;
    start.lines.stone.workers = 0;
    const cap = storageCap(DEFAULT_PUPPET, "meat", 1);
    start.lines.meat.stored = cap - 1;
    const after = settlePuppetLines(start, DEFAULT_PUPPET, new Date("2026-11-02T10:00:00.000Z"));
    expect(after.lines.meat.stored).toBeLessThanOrEqual(cap);
    expect(after.lines.meat.stored).toBeGreaterThan(cap - 1);
    // 已接近满仓时瞬时产出接近 0
    const nearly = { ...after, lines: { ...after.lines, meat: { ...after.lines.meat, stored: cap } } };
    const dto = buildPuppetDto(nearly, DEFAULT_PUPPET, 8);
    const meat = dto.lines.find((l) => l.id === "meat");
    expect(meat?.stoppedReason).toBe("storage_full");
    expect(meat?.netPerHour).toBe(0);
  });

  it("warehouse fill reduces net before hard full", () => {
    const start = defaultPuppetProgress(DEFAULT_PUPPET, new Date("2026-11-02T00:00:00.000Z"));
    start.lines.meat.workers = 4;
    start.lines.wood.workers = 0;
    start.lines.herb.workers = 0;
    start.lines.stone.workers = 0;
    const cap = storageCap(DEFAULT_PUPPET, "meat", 1);
    start.lines.meat.stored = cap * 0.5;
    const dto = buildPuppetDto(start, DEFAULT_PUPPET, 8);
    const meat = dto.lines.find((l) => l.id === "meat");
    // 半仓：产出系数 0.5 → 4*2.5*0.5 = 5
    expect(meat?.netPerHour).toBeCloseTo(5, 5);
    expect(meat?.stoppedReason).toBe("");
  });

  it("upgrade cost scales with hours of prod knob", () => {
    expect(upgradeCostOf(DEFAULT_PUPPET, "wood", 1)).toBe(Math.ceil(2 * 1.0 * 2.5));
    expect(upgradeCostOf(DEFAULT_PUPPET, "meat", 1)).toBe(Math.ceil(6 * 2.5 * 2.5));
  });
});
