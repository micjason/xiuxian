import { describe, expect, it } from "vitest";
import { defaultManifest, frameIndexAt, lungeAt, missingSlots, poseAt } from "./playback.js";

describe("animation playback", () => {
  it("holds the last frame of an action that does not loop", () => {
    expect(frameIndexAt({ frameCount: 4, frameDurationMs: 100, loop: false }, 0)).toBe(0);
    expect(frameIndexAt({ frameCount: 4, frameDurationMs: 100, loop: false }, 250)).toBe(2);
    expect(frameIndexAt({ frameCount: 4, frameDurationMs: 100, loop: false }, 5000)).toBe(3);
  });

  it("wraps a looping idle", () => {
    expect(frameIndexAt({ frameCount: 3, frameDurationMs: 100, loop: true }, 350)).toBe(0);
  });

  it("lunges forward and returns within the action", () => {
    expect(lungeAt(24, 0, 400)).toBe(0);
    expect(lungeAt(24, 200, 400)).toBe(24);
    expect(lungeAt(24, 400, 400)).toBe(0);
  });

  it("plays idle, then attack, then a skill that lands on the hit delay", () => {
    const manifest = defaultManifest();
    manifest.hitDelaySeconds = 1;
    manifest.slots.attack.frames = ["00.png", "01.png"];
    manifest.slots.cast.frames = ["00.png"];
    manifest.slots.skill.frames = ["00.png"];
    manifest.slots.hit.frames = ["00.png"];
    manifest.slots.victory.frames = ["00.png"];
    manifest.slots.projectile.frames = ["00.png", "01.png"];
    manifest.slots.impact.frames = ["00.png"];

    expect(poseAt(manifest, 0).slot).toBe("idle");
    expect(poseAt(manifest, 1000).slot).toBe("attack");
    expect(poseAt(manifest, 1000).lungePx).toBeGreaterThan(0);

    const casting = poseAt(manifest, 1700 + 200);
    expect(casting.slot).toBe("cast");
    expect(casting.projectile).toBeNull();

    const flying = poseAt(manifest, 1700 + 800);
    expect(flying.slot).toBe("skill");
    expect(flying.projectile).not.toBeNull();
    expect(flying.projectile!).toBeGreaterThan(0);
    expect(flying.projectile!).toBeLessThan(1);

    const impact = poseAt(manifest, 1700 + 1000);
    expect(impact.slot).toBe("hit");
    expect(impact.projectile).toBeNull();
    expect(impact.impact).toBe(true);

    expect(poseAt(manifest, 1700 + 1000 + 500).slot).toBe("victory");
  });

  it("names the body slots that still have no frames", () => {
    const manifest = defaultManifest();
    expect(missingSlots(manifest)).toEqual(["idle", "attack", "cast", "skill", "hit", "down", "victory"]);
    manifest.slots.idle.frames = ["00.png"];
    expect(missingSlots(manifest)).not.toContain("idle");
  });
});
