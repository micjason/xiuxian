import { describe, expect, it } from "vitest";
import { rollDrops } from "./drops.js";

describe("rollDrops", () => {
  it("rolls each drop on its own and can hit both or neither", () => {
    const drops = [
      { itemSlug: "herb", chance: 50, quantity: 2 },
      { itemSlug: "book", chance: 50, quantity: 1 },
    ];
    expect(rollDrops(drops, () => 0)).toEqual([
      { itemSlug: "herb", quantity: 2 },
      { itemSlug: "book", quantity: 1 },
    ]);
    expect(rollDrops(drops, () => 0.99)).toEqual([]);
  });

  it("never drops chance 0 and always drops chance 100", () => {
    const drops = [
      { itemSlug: "none", chance: 0, quantity: 1 },
      { itemSlug: "always", chance: 100, quantity: 3 },
    ];
    expect(rollDrops(drops, () => 0)).toEqual([{ itemSlug: "always", quantity: 3 }]);
    expect(rollDrops(drops, () => 0.99)).toEqual([{ itemSlug: "always", quantity: 3 }]);
  });
});
