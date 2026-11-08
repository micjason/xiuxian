import { describe, it, expect } from "vitest";
import { finishDecision } from "./session-policy.js";
describe("authoritative settlement policy", () => {
  it("retreat fails without rewards regardless of the precomputed winner", () => {
    expect(finishDecision({ win: true, reason: "win", durationSeconds: 20, log: [] }, "retreat", false, 1, 3)).toMatchObject({ win: false, reason: "retreat", durationSeconds: 1 });
  });
  it("rejects first-clear skip and finishing faster than allowed playback", () => {
    const battle = { win: true, reason: "win" as const, durationSeconds: 20, log: [] };
    expect(() => finishDecision(battle, "skip", false, 0, 3)).toThrow();
    expect(() => finishDecision(battle, "complete", false, 2, 3)).toThrow();
    expect(finishDecision(battle, "complete", false, 7, 3)).toBe(battle);
    expect(finishDecision(battle, "recover", false, 0, 3)).toBe(battle);
    expect(finishDecision(battle, "skip", true, 0, 3)).toBe(battle);
  });
});
