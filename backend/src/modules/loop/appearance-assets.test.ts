import { describe, expect, it } from "vitest";
import { missingOutfitAssets, outfitAssetRefs, OUTFIT_QUALITIES } from "./appearance.js";

describe("outfit asset validation (换装 A)", () => {
  it("expects five qualities × four keys", () => {
    expect(outfitAssetRefs()).toHaveLength(OUTFIT_QUALITIES.length * 4);
    expect(outfitAssetRefs().map((row) => row.key)).toEqual(
      expect.arrayContaining([
        "preview_white",
        "meditate_green",
        "avatar_blue",
        "avatar_purple_round",
        "preview_orange",
      ]),
    );
  });

  it("warns only for missing keys (read-only)", () => {
    const present = outfitAssetRefs()
      .filter((row) => row.quality !== "orange")
      .map((row) => row.relativePath);
    const missing = missingOutfitAssets(present);
    expect(missing.every((row) => row.quality === "orange")).toBe(true);
    expect(missing.map((row) => row.key).sort()).toEqual([
      "avatar_orange",
      "avatar_orange_round",
      "meditate_orange",
      "preview_orange",
    ]);
  });

  it("reports nothing when the full set is present", () => {
    expect(missingOutfitAssets(outfitAssetRefs().map((row) => row.relativePath))).toEqual([]);
  });
});
