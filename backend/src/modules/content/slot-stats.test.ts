import { describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { contentGlobals, contentItems, contentRealms } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { DEFAULT_TUNING, tuningFromInput, tuningOf } from "./tuning.js";
import { listGear, previewGearParams, splitGearBudget, syncGear } from "./gear.js";
import { saveGearParams } from "./config-overview.js";
import { buildScheme } from "./numeric-scheme.js";

const weights = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };
const budget = { attack: 300, defense: 250, hp: 1000, speed: 120 };

describe("slotStats tuning", () => {
  it("defaults match live GEAR_SLOTS combos and rejects empty slot", () => {
    expect(tuningOf(null).slotStats).toEqual(DEFAULT_TUNING.slotStats);
    expect(tuningFromInput({}).slotStats.weapon).toEqual(["attack"]);
    expect(() => tuningFromInput({ slotStats: { ...DEFAULT_TUNING.slotStats, weapon: [] } })).toThrow("至少选 1");
    expect(() => tuningFromInput({ slotStats: { ...DEFAULT_TUNING.slotStats, weapon: ["magic"] } })).toThrow("攻击");
  });

  it("splitGearBudget honors stats override", () => {
    const withSpeed = splitGearBudget({ budget, slotKey: "weapon", factor: 1, weights, speedFactor: 1, stats: ["attack", "speed"] });
    expect(withSpeed.attack).toBeGreaterThan(0);
    expect(withSpeed.speed).toBeGreaterThan(0);
    expect(withSpeed.defense).toBe(0);
    const attackOnly = splitGearBudget({ budget, slotKey: "weapon", factor: 1, weights, speedFactor: 1, stats: ["attack"] });
    expect(attackOnly.speed).toBe(0);
    expect(attackOnly.attack).toBeGreaterThan(withSpeed.attack);
  });

  it("saveGearParams persists slotStats and regenerates; preview does not write", async () => {
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
      await syncGear(db, null);
      const before = await listGear(db);
      expect(before.params.slotStats.weapon).toEqual(["attack"]);

      const preview = await previewGearParams(db, {
        slotStats: { ...DEFAULT_TUNING.slotStats, weapon: ["attack", "defense"] },
      });
      expect(preview.samples.find((row) => row.slot === "weapon")?.defense).toBeGreaterThan(0);
      const still = await listGear(db);
      expect(still.params.slotStats.weapon).toEqual(["attack"]);

      await saveGearParams(db, { slotStats: { ...DEFAULT_TUNING.slotStats, weapon: ["attack", "defense"] } }, null);
      const after = await listGear(db);
      expect(after.params.slotStats.weapon).toEqual(["attack", "defense"]);
      const [weapon] = await db.select().from(contentItems).where(eq(contentItems.slug, "gear_qi_weapon_white"));
      expect(weapon!.defense).toBeGreaterThan(0);
    });
  });
});
