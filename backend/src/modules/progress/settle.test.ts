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
});
