import { describe, expect, it } from "vitest";
import { pickQuality, repeatRewardWeights, rollGearPiece, rollMonsterKillDrop } from "./monster-drops.js";

const seq = (...values: number[]) => {
  let index = 0;
  return (min: number, max: number) => {
    const value = values[index++] ?? 0;
    expect(value).toBeGreaterThanOrEqual(min);
    expect(value).toBeLessThan(max);
    return value;
  };
};
const qi = { white: 70, green: 25, blue: 5, purple: 0 };
const core = { white: 35, green: 40, blue: 20, purple: 5 };

describe("monster gear drops", () => {
  it("picks quality by weight boundaries (70/25/5/0)", () => {
    const pick = (roll: number) => pickQuality(qi, seq(roll));
    expect(pick(0)).toBe("white");
    expect(pick(69999)).toBe("white");
    expect(pick(70000)).toBe("green");
    expect(pick(94999)).toBe("green");
    expect(pick(95000)).toBe("blue");
    expect(pick(99999)).toBe("blue");
    expect(pickQuality({ white: 0, green: 0, blue: 0, purple: 0 }, seq())).toBeNull();
  });

  it("never rolls purple in the qi region and can in core (zero weight is impossible)", () => {
    for (let roll = 0; roll < 100000; roll += 7) {
      expect(pickQuality(qi, () => roll)).not.toBe("purple");
    }
    expect(pickQuality(core, seq(99999))).toBe("purple");
  });

  it("slot is an equal pick over the 6 slots", () => {
    const slots = [0, 1, 2, 3, 4, 5].map((n) => rollGearPiece("major1", qi, seq(0, n))!.slot);
    expect(slots).toEqual(["weapon", "clothes", "helmet", "gloves", "shoes", "accessory"]);
    expect(rollGearPiece("major1", qi, seq(0, 5))!.slug).toBe("gear_major1_accessory_white");
  });

  it("5% per kill: roll 499 drops, 500 does not", () => {
    const config = { chanceBp: 500, qualityWeights: core };
    expect(rollMonsterKillDrop("major3", config, seq(499, 70000, 0))).toMatchObject({ slug: "gear_major3_weapon_green" });
    expect(rollMonsterKillDrop("major3", config, seq(500))).toBeNull();
    expect(rollMonsterKillDrop("major3", null, seq())).toBeNull();
    expect(rollMonsterKillDrop("major3", { chanceBp: 0, qualityWeights: core }, seq())).toBeNull();
  });

  it("statistics: 200000 kills at 5% give ~10000 drops with the regional quality mix", () => {
    let state = 12345;
    const rand = (min: number, max: number) => {
      // mulberry32：确定性的伪随机，测试可重复
      state = (state + 0x6d2b79f5) | 0;
      let t = Math.imul(state ^ (state >>> 15), 1 | state);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return min + Math.floor((((t ^ (t >>> 14)) >>> 0) / 4294967296) * (max - min));
    };
    const counts: Record<string, number> = {};
    let drops = 0;
    const kills = 200000;
    for (let i = 0; i < kills; i += 1) {
      const drop = rollMonsterKillDrop("major2", { chanceBp: 500, qualityWeights: { white: 50, green: 35, blue: 13, purple: 2 } }, rand);
      if (drop) {
        drops += 1;
        counts[drop.quality] = (counts[drop.quality] ?? 0) + 1;
      }
    }
    expect(drops / kills).toBeGreaterThan(0.048);
    expect(drops / kills).toBeLessThan(0.052);
    expect((counts.white! / drops) * 100).toBeGreaterThan(47);
    expect((counts.white! / drops) * 100).toBeLessThan(53);
    expect((counts.purple! / drops) * 100).toBeGreaterThan(1.2);
    expect((counts.purple! / drops) * 100).toBeLessThan(2.8);
  });

  it("boss repeat reward merges white into green", () => {
    expect(repeatRewardWeights(qi)).toEqual({ white: 0, green: 95, blue: 5, purple: 0 });
    expect(rollGearPiece("major1", repeatRewardWeights(qi), seq(0, 0))!.quality).toBe("green");
  });
});
