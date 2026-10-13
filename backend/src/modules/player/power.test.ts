import { describe, expect, it } from "vitest";
import { piecePower } from "./power.js";

describe("piecePower", () => {
  it("uses the same weights as the rest of the game", () => {
    const weights = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };
    expect(piecePower({ attack: 10, defense: 10, hp: 100, speed: 10 }, weights)).toBe(
      Math.round(10 * 4.7 + 10 * 1.6 + 100 * 0.95 + 10 * 2.6),
    );
  });
});
