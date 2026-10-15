import { describe, expect, it } from "vitest";
import { settleTicks } from "./settle.js";

describe("settleTicks", () => {
  it("keeps the leftover seconds that do not fill a tick", () => {
    const last = new Date("2026-10-08T00:00:00.000Z");
    const result = settleTicks({
      cultivation: 0,
      lastSettledAt: last,
      now: new Date(last.getTime() + 10_000),
      tickSeconds: 3,
      gainPerTick: 2,
      bonusBp: 0,
      offlineCapSeconds: 28800,
    });
    expect(result.cultivation).toBe(6);
    expect(result.lastSettledAt.toISOString()).toBe(new Date(last.getTime() + 9_000).toISOString());
  });

  it("does not grant cultivation until seconds and gain are configured", () => {
    const last = new Date("2026-10-08T00:00:00.000Z");
    const now = new Date(last.getTime() + 60_000);
    const result = settleTicks({
      cultivation: 5,
      lastSettledAt: last,
      now,
      tickSeconds: 0,
      gainPerTick: 0,
      bonusBp: 0,
      offlineCapSeconds: 28800,
    });
    expect(result.cultivation).toBe(5);
    expect(result.countedSeconds).toBe(0);
  });

  it("discards time beyond the offline cap", () => {
    const last = new Date("2026-10-08T00:00:00.000Z");
    const now = new Date(last.getTime() + 100_000);
    const result = settleTicks({
      cultivation: 0,
      lastSettledAt: last,
      now,
      tickSeconds: 1,
      gainPerTick: 1,
      bonusBp: 0,
      offlineCapSeconds: 10,
    });
    expect(result.hitCap).toBe(true);
    expect(result.cultivation).toBe(10);
    expect(result.lastSettledAt.toISOString()).toBe(now.toISOString());
  });

  it("applies a +15% bonus at 1 point per second to the whole duration: 8h => 33,120 (not 28,800)", () => {
    const last = new Date("2026-10-08T00:00:00.000Z");
    const result = settleTicks({
      cultivation: 0,
      lastSettledAt: last,
      now: new Date(last.getTime() + 8 * 3600 * 1000),
      tickSeconds: 1,
      gainPerTick: 1,
      bonusBp: 1500,
      offlineCapSeconds: 28800,
    });
    expect(result.cultivation).toBe(33120);
    expect(result.gained).toBe(33120);
    expect(result.remainderBp).toBe(0);
    expect(result.hitCap).toBe(false);
    expect(result.countedSeconds).toBe(28800);
  });

  it.each([
    { name: "30 min x1 x1.05", seconds: 1800, gain: 1, bonusBp: 500, cap: 28800, expected: 1890 },
    { name: "foundation 2h x3 x1.15", seconds: 7200, gain: 3, bonusBp: 1500, cap: 28800, expected: 24840 },
    { name: "foundation 10h capped to 8h x3 x1.15", seconds: 36000, gain: 3, bonusBp: 1500, cap: 28800, expected: 99360 },
    { name: "core 8h x9 x1.3", seconds: 28800, gain: 9, bonusBp: 3000, cap: 28800, expected: 336960 },
    { name: "core 4 min x9 x1.3", seconds: 240, gain: 9, bonusBp: 3000, cap: 28800, expected: 2808 },
  ])("matches the design table: $name", ({ seconds, gain, bonusBp, cap, expected }) => {
    const last = new Date("2026-10-08T00:00:00.000Z");
    const result = settleTicks({
      cultivation: 0,
      lastSettledAt: last,
      now: new Date(last.getTime() + seconds * 1000),
      tickSeconds: 1,
      gainPerTick: gain,
      bonusBp,
      offlineCapSeconds: cap,
    });
    expect(result.cultivation).toBe(expected);
  });

  it("does not use floats: 900 s x 3 x 1.15 is exactly 3105 (a float multiply would give 3104.9999999999995)", () => {
    const last = new Date("2026-10-08T00:00:00.000Z");
    const result = settleTicks({
      cultivation: 0,
      lastSettledAt: last,
      now: new Date(last.getTime() + 900_000),
      tickSeconds: 1,
      gainPerTick: 3,
      bonusBp: 1500,
      offlineCapSeconds: 28800,
    });
    expect(result.cultivation).toBe(3105);
  });

  it("carries the fraction between settlements: 300 polls of 3 s at 1/s +15% give 1,035 in total, same as one 900 s settlement", () => {
    const start = new Date("2026-10-08T00:00:00.000Z");
    let state = { cultivation: 0, lastSettledAt: start, remainderBp: 0 };
    for (let poll = 1; poll <= 300; poll += 1) {
      const result = settleTicks({
        ...state,
        now: new Date(start.getTime() + poll * 3000),
        tickSeconds: 1,
        gainPerTick: 1,
        bonusBp: 1500,
        offlineCapSeconds: 28800,
      });
      state = { cultivation: result.cultivation, lastSettledAt: result.lastSettledAt, remainderBp: result.remainderBp };
    }
    expect(state.cultivation).toBe(1035);
    expect(state.remainderBp).toBe(0);
    const once = settleTicks({
      cultivation: 0,
      lastSettledAt: start,
      now: new Date(start.getTime() + 900_000),
      tickSeconds: 1,
      gainPerTick: 1,
      bonusBp: 1500,
      offlineCapSeconds: 28800,
    });
    expect(once.cultivation).toBe(1035);
  });

  it("is split-invariant for 1 s polls and for irregular gaps at +15%, x3", () => {
    const start = new Date("2026-10-08T00:00:00.000Z");
    const gaps = [1, 2, 3, 3, 7, 1, 5, 11, 3, 3, 3, 40, 1, 1, 2];
    let state = { cultivation: 0, lastSettledAt: start, remainderBp: 0 };
    let at = 0;
    for (const gap of gaps) {
      at += gap;
      const result = settleTicks({ ...state, now: new Date(start.getTime() + at * 1000), tickSeconds: 1, gainPerTick: 3, bonusBp: 1500, offlineCapSeconds: 28800 });
      state = { cultivation: result.cultivation, lastSettledAt: result.lastSettledAt, remainderBp: result.remainderBp };
    }
    expect(state.cultivation).toBe(Math.floor((at * 3 * 11500) / 10000));
    expect(state.remainderBp).toBe((at * 3 * 11500) % 10000);
  });

  it("keeps the remainder under 10000 and accepts a fractional bonusBp by rounding it once", () => {
    const last = new Date("2026-10-08T00:00:00.000Z");
    const result = settleTicks({
      cultivation: 10,
      lastSettledAt: last,
      now: new Date(last.getTime() + 7_000),
      tickSeconds: 1,
      gainPerTick: 1,
      bonusBp: 1725.4,
      offlineCapSeconds: 28800,
      remainderBp: 9999,
    });
    // 7 x 11725 + 9999 = 92074 => 9 points, remainder 2074
    expect(result.gained).toBe(9);
    expect(result.cultivation).toBe(19);
    expect(result.remainderBp).toBe(2074);
    expect(result.remainderBp).toBeGreaterThanOrEqual(0);
    expect(result.remainderBp).toBeLessThan(10000);
  });

  it("keeps the remainder when time runs backwards, nothing elapsed, or the cap is hit", () => {
    const last = new Date("2026-10-08T00:00:00.000Z");
    const base = { cultivation: 0, lastSettledAt: last, tickSeconds: 1, gainPerTick: 1, bonusBp: 1500, offlineCapSeconds: 10, remainderBp: 4321 };
    expect(settleTicks({ ...base, now: last }).remainderBp).toBe(4321);
    expect(settleTicks({ ...base, now: new Date(last.getTime() - 5000) }).remainderBp).toBe(4321);
    const capped = settleTicks({ ...base, now: new Date(last.getTime() + 100_000) });
    expect(capped.hitCap).toBe(true);
    expect(capped.countedSeconds).toBe(10);
    // 10 x 11500 + 4321 = 119321
    expect(capped.gained).toBe(11);
    expect(capped.remainderBp).toBe(9321);
    expect(capped.lastSettledAt.toISOString()).toBe(new Date(last.getTime() + 100_000).toISOString());
  });

  it("with tickSeconds > 1 settles whole ticks only and carries the fraction by ticks", () => {
    const last = new Date("2026-10-08T00:00:00.000Z");
    const result = settleTicks({
      cultivation: 0,
      lastSettledAt: last,
      now: new Date(last.getTime() + 10_000),
      tickSeconds: 3,
      gainPerTick: 1,
      bonusBp: 1500,
      offlineCapSeconds: 28800,
    });
    // 3 ticks x 1 x 11500 = 34500 => 3 points, remainder 4500; 1 s left over stays in lastSettledAt
    expect(result.gained).toBe(3);
    expect(result.remainderBp).toBe(4500);
    expect(result.lastSettledAt.toISOString()).toBe(new Date(last.getTime() + 9_000).toISOString());
  });

  it("treats a missing or invalid remainder as zero", () => {
    const last = new Date("2026-10-08T00:00:00.000Z");
    const base = { cultivation: 0, lastSettledAt: last, now: new Date(last.getTime() + 10_000), tickSeconds: 1, gainPerTick: 1, bonusBp: 0, offlineCapSeconds: 28800 };
    expect(settleTicks(base).cultivation).toBe(10);
    expect(settleTicks({ ...base, remainderBp: -5 }).cultivation).toBe(10);
    expect(settleTicks({ ...base, remainderBp: Number.NaN }).cultivation).toBe(10);
  });
});
