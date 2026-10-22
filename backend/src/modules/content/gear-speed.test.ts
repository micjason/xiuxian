import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentRealms } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { ratePower } from "../combat/stats.js";
import { DEFAULT_GEAR_SPEED_FACTOR, GEAR_SLOTS, gearSpeedFactorOf, splitGearBudget, syncGear } from "./gear.js";
import { gearSlug, buildScheme } from "./numeric-scheme.js";
import { readRules, rulesFromInput, rulesForSave, saveRules } from "./rules.js";

const weights = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };
const budget = { attack: 300, defense: 250, hp: 1000, speed: 120 };
const split = (slotKey: string, speedFactor?: number) => splitGearBudget({ budget, slotKey, factor: 1, weights, speedFactor });

describe("gear speed factor", () => {
  it("factor 1 is the old behaviour: speed and the other stat get the same number", () => {
    const shoes = split("shoes", 1);
    expect(shoes.speed).toBe(shoes.hp);
    const accessory = split("accessory", 1);
    expect(accessory.speed).toBe(accessory.attack);
  });

  it("scales speed on shoes and accessories and keeps the power of every piece", () => {
    for (const slot of ["shoes", "accessory"]) {
      const full = split(slot, 1);
      const slow = split(slot, 0.25);
      expect(slow.speed).toBeCloseTo(full.speed * 0.25, 1);
      expect(Math.abs(ratePower(slow, weights) - ratePower(full, weights))).toBeLessThanOrEqual(2);
    }
    // 鞋子的省下的战力补给气血，饰品补给攻击
    expect(split("shoes", 0.25).hp).toBeGreaterThan(split("shoes", 1).hp);
    expect(split("accessory", 0.25).attack).toBeGreaterThan(split("accessory", 1).attack);
  });

  it("factor 0 removes gear speed completely and still keeps the power", () => {
    const shoes = split("shoes", 0);
    expect(shoes.speed).toBe(0);
    expect(Math.abs(ratePower(shoes, weights) - ratePower(split("shoes", 1), weights))).toBeLessThanOrEqual(2);
  });

  it("does not touch slots without speed", () => {
    for (const slot of GEAR_SLOTS.filter((row) => !row.stats.includes("speed"))) {
      expect(split(slot.key, 0.1)).toEqual(split(slot.key, 1));
    }
  });

  it("uses a default when nothing is stored and rejects values outside 0..1", () => {
    expect(gearSpeedFactorOf(undefined)).toBe(DEFAULT_GEAR_SPEED_FACTOR);
    expect(gearSpeedFactorOf(0)).toBe(0);
    expect(gearSpeedFactorOf("0.5")).toBe(0.5);
    expect(() => gearSpeedFactorOf(-0.1)).toThrow("装备速度比例");
    expect(() => gearSpeedFactorOf(1.5)).toThrow("装备速度比例");
    expect(() => gearSpeedFactorOf("abc")).toThrow("装备速度比例");
  });
});

describe("gear speed factor in the rules", () => {
  const input = {
    offlineCapSeconds: 28800,
    bagCapacity: 20,
    attackWeight: 4.7,
    defenseWeight: 1.6,
    hpWeight: 0.95,
    speedWeight: 2.6,
    baseInterval: 1.5,
    minInterval: 0.5,
    challengeCooldownSeconds: 0,
    timeLimitSeconds: 45,
    defenseConstant: 1,
    speedBase: 100,
    recommendedPowerMargin: 1.05,
  };

  it("is optional in the input, defaults, and keeps the stored value when not sent", () => {
    expect(rulesFromInput(input).gearSpeedFactor).toBe(DEFAULT_GEAR_SPEED_FACTOR);
    expect(rulesFromInput({ ...input, gearSpeedFactor: 0.4 }).gearSpeedFactor).toBe(0.4);
    const saved = rulesForSave(input, { offlineCapSeconds: 1, bagCapacity: 1, combat: { gearSpeedFactor: 0.6 } });
    expect(rulesFromInput(saved).gearSpeedFactor).toBe(0.6);
    expect(() => rulesFromInput({ ...input, gearSpeedFactor: 2 })).toThrow("装备速度比例");
  });

  it("saving the rules regenerates the gear: shoes speed follows the factor", async () => {
    await withDb(async (db) => {
      const scheme = buildScheme();
      await db.insert(contentRealms).values(scheme.realms.filter((realm) => realm.majorName === "炼气"));
      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "qi_early",
        offlineCapSeconds: 28800,
        bagCapacity: 20,
        powerWeights: weights,
        combat: { minInterval: 0.5, challengeCooldownSeconds: 0, timeLimitSeconds: 45, defenseConstant: 1, speedBase: 100, recommendedPowerMargin: 1.05 },
      });
      // 老数据没存这个值：读出来是默认值
      expect((await readRules(db)).gearSpeedFactor).toBe(DEFAULT_GEAR_SPEED_FACTOR);

      await saveRules(db, { ...input, gearSpeedFactor: 1 }, null);
      const slug = gearSlug("qi", "shoes", "white");
      const [full] = await db.select().from(contentItems).where(eq(contentItems.slug, slug));
      await saveRules(db, { ...input, gearSpeedFactor: 0.5 }, null);
      const [half] = await db.select().from(contentItems).where(eq(contentItems.slug, slug));
      expect(full?.speed ?? 0).toBeGreaterThan(0);
      expect(half?.speed ?? 0).toBeCloseTo((full?.speed ?? 0) * 0.5, 1);
      expect(half?.hp ?? 0).toBeGreaterThan(full?.hp ?? 0);
      expect((await readRules(db)).gearSpeedFactor).toBe(0.5);

      // 不带这个字段再保存，沿用已存的值
      await saveRules(db, input, null);
      expect((await readRules(db)).gearSpeedFactor).toBe(0.5);
      await syncGear(db, null);
    });
  });
});
