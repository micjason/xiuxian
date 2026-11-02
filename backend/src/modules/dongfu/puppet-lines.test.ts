import { describe, expect, it } from "vitest";
import { DEFAULT_PUPPET } from "./config.js";
import {
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
    // meat +6*2.5 -2*2 = +15-4 = +11 → 111
    expect(after.lines.meat.stored).toBeCloseTo(111, 5);
    expect(after.lines.wood.stored).toBeCloseTo(2, 5);
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

  it("does not exceed storage cap", () => {
    const start = defaultPuppetProgress(DEFAULT_PUPPET, new Date("2026-11-02T00:00:00.000Z"));
    start.lines.meat.workers = 6;
    start.lines.wood.workers = 0;
    start.lines.meat.stored = storageCap(DEFAULT_PUPPET, "meat", 1) - 1;
    const after = settlePuppetLines(start, DEFAULT_PUPPET, new Date("2026-11-02T10:00:00.000Z"));
    expect(after.lines.meat.stored).toBe(storageCap(DEFAULT_PUPPET, "meat", 1));
    const dto = buildPuppetDto(after, DEFAULT_PUPPET, 8);
    expect(dto.lines.find((l) => l.id === "meat")?.stoppedReason).toBe("storage_full");
  });

  it("upgrade cost scales with hours of prod knob", () => {
    expect(upgradeCostOf(DEFAULT_PUPPET, "wood", 1)).toBe(Math.ceil(2 * 1.0 * 2.5));
    expect(upgradeCostOf(DEFAULT_PUPPET, "meat", 1)).toBe(Math.ceil(6 * 2.5 * 2.5));
  });
});
