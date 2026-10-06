import { describe, expect, it } from "vitest";
import { breakthrough, settleCultivation } from "./progress-rules.js";

describe("settleCultivation", () => {
  it("caps elapsed time and adds cultivation", () => {
    const result = settleCultivation({
      cultivation: 10,
      elapsedSeconds: 100,
      gainPerSecond: 2,
      offlineCapSeconds: 40,
    });
    expect(result).toEqual({ cultivation: 90, countedSeconds: 40, gained: 80 });
  });

  it("treats negative elapsed time as zero", () => {
    const result = settleCultivation({
      cultivation: 10,
      elapsedSeconds: -5,
      gainPerSecond: 2,
      offlineCapSeconds: 40,
    });
    expect(result.gained).toBe(0);
    expect(result.cultivation).toBe(10);
  });
});

describe("breakthrough", () => {
  it("spends cultivation and moves to the next realm", () => {
    expect(breakthrough({ cultivation: 400, cost: 360, nextSlug: "qi_early" })).toEqual({
      ok: true,
      cultivation: 40,
      nextSlug: "qi_early",
    });
  });

  it("rejects a realm with no next slug", () => {
    expect(breakthrough({ cultivation: 999, cost: 1, nextSlug: null })).toEqual({
      ok: false,
      reason: "max_realm",
    });
  });

  it("rejects when cultivation is short", () => {
    expect(breakthrough({ cultivation: 10, cost: 360, nextSlug: "qi_early" })).toEqual({
      ok: false,
      reason: "not_enough",
    });
  });
});
