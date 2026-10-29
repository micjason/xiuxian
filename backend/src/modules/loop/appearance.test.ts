import { describe, expect, it } from "vitest";
import { appearanceOf } from "./appearance.js";

const gear = (slug: string, slot: string, quality: string) => ({ slug, kind: "equipment", slot, quality });

describe("appearanceOf", () => {
  it("returns null when nothing is worn", () => {
    expect(appearanceOf([gear("robe", "clothes", "blue")], [{ itemSlug: "robe", equippedSlot: null }])).toBeNull();
  });

  it("uses the clothes quality for all three texture sets", () => {
    expect(
      appearanceOf(
        [gear("robe", "clothes", "purple"), gear("blade", "weapon", "white")],
        [
          { itemSlug: "robe", equippedSlot: "clothes" },
          { itemSlug: "blade", equippedSlot: "weapon" },
        ],
      ),
    ).toEqual({
      quality: "purple",
      previewKey: "preview_purple",
      meditateKey: "meditate_purple",
      avatarKey: "avatar_purple",
      avatarRoundKey: "avatar_purple_round",
    });
  });

  it("uses the highest worn quality when clothes are empty, including green and orange", () => {
    expect(
      appearanceOf(
        [gear("helm", "helmet", "green"), gear("blade", "weapon", "orange")],
        [
          { itemSlug: "helm", equippedSlot: "helmet" },
          { itemSlug: "blade", equippedSlot: "weapon" },
        ],
      )?.quality,
    ).toBe("orange");
  });
});
