import { describe, expect, it } from "vitest";
import { piecePower } from "./power.js";

describe("piecePower", () => {
  it("matches the client formula", () => {
    expect(piecePower({ attack: 10, defense: 10, hp: 100, speed: 10 })).toBe(
      10 + 8 + 15 + 4,
    );
  });
});
