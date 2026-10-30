import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentItems, contentRealms, playerItems } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { buildScheme, gearSlug } from "./numeric-scheme.js";
import { readGearQualityFactors, removeMajorGear, saveGearQualityFactors, syncGear, updateGearPiece } from "./gear.js";

describe("gear quality factors", () => {
  it("stores the default factors and rewrites every piece when a factor changes", async () => {
    await withDb(async (db) => {
      const scheme = buildScheme();
      await db.insert(contentRealms).values(scheme.realms.filter((realm) => realm.majorName === "炼气"));
      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "qi_early",
        offlineCapSeconds: 36000,
        bagCapacity: 20,
        powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
        combat: {
          minInterval: 0.5,
          challengeCooldownSeconds: 0,
          timeLimitSeconds: 20,
          defenseConstant: 1,
          speedBase: 100,
          recommendedPowerMargin: 1.05,
        },
      });

      const defaults = await readGearQualityFactors(db);
      expect(defaults).toEqual({ white: 1, green: 1.15, blue: 1.3, purple: 1.5, orange: 1.8 });

      await syncGear(db, null);
      const whiteSlug = gearSlug("qi", "weapon", "white");
      const orangeSlug = gearSlug("qi", "weapon", "orange");
      const [white] = await db.select().from(contentItems).where(eq(contentItems.slug, whiteSlug));
      const [orange] = await db.select().from(contentItems).where(eq(contentItems.slug, orangeSlug));
      const schemeWhite = scheme.items.find((item) => item.slug === whiteSlug);
      expect(white).toMatchObject({
        attack: schemeWhite?.attack,
        defense: 0,
        hp: 0,
        speed: 0,
        slot: "weapon",
        quality: "white",
        requiredRealmOrder: 1,
      });
      expect(orange?.attack).toBeCloseTo((schemeWhite?.attack ?? 0) * 1.8, 1);
      const pieces = await db.select().from(contentItems);
      expect(pieces.filter((item) => item.kind === "equipment")).toHaveLength(30);

      await updateGearPiece(db, whiteSlug, { displayName: "青锋", description: "自己起的名字", iconKey: "sword" }, null);
      await saveGearQualityFactors(db, { white: 1, green: 1.15, blue: 1.3, purple: 1.5, orange: 2 }, null);
      const [renamed] = await db.select().from(contentItems).where(eq(contentItems.slug, whiteSlug));
      const [orangeAfter] = await db.select().from(contentItems).where(eq(contentItems.slug, orangeSlug));
      expect(renamed).toMatchObject({ displayName: "青锋", description: "自己起的名字", iconKey: "sword", attack: schemeWhite?.attack });
      expect((orangeAfter?.attack ?? 0) / (renamed?.attack || 1)).toBeCloseTo(2, 1);
      expect(await readGearQualityFactors(db)).toMatchObject({ orange: 2 });
    });
  });

  it("refuses a missing factor and a factor that is not above zero", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({
        slug: "qi_early",
        displayName: "炼气初期",
        majorName: "炼气",
        sortOrder: 1,
        nextRealmSlug: null,
        baseAttack: 10,
        baseDefense: 10,
        baseHp: 33,
        baseSpeed: 0,
        baseInterval: 1.5,
      });
      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "qi_early",
        powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
        gearQualityFactors: { white: 1, green: 1.15, blue: 1.3, purple: 1.5, orange: 1.8 },
      });
      await expect(saveGearQualityFactors(db, { white: 1, green: 1.15, blue: 1.3, purple: 1.5 }, null)).rejects.toThrow(
        "请填写橙品质系数",
      );
      await expect(
        saveGearQualityFactors(db, { white: 0, green: 1.15, blue: 1.3, purple: 1.5, orange: 1.8 }, null),
      ).rejects.toThrow("白品质系数必须大于 0");
    });
  });

  it("keeps generated gear when someone still holds a piece of that major", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({
        slug: "qi_early",
        displayName: "炼气初期",
        majorName: "炼气",
        majorKey: "qi",
        sortOrder: 1,
        nextRealmSlug: null,
        baseAttack: 10,
        baseDefense: 10,
        baseHp: 33,
        baseSpeed: 0,
        baseInterval: 1.5,
      });
      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "qi_early",
        offlineCapSeconds: 36000,
        bagCapacity: 20,
        powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
        gearQualityFactors: { white: 1, green: 1.15, blue: 1.3, purple: 1.5, orange: 1.8 },
        combat: {
          minInterval: 0.5,
          challengeCooldownSeconds: 0,
          timeLimitSeconds: 20,
          defenseConstant: 1,
          speedBase: 100,
          recommendedPowerMargin: 1.05,
        },
      });
      await syncGear(db, null);
      const player = await registerPlayer(db, { username: "holder", password: "correct-horse", now: new Date("2026-10-13T00:00:00.000Z") });
      await db.insert(playerItems).values({
        playerId: player.playerId,
        itemSlug: gearSlug("qi", "weapon", "white"),
        isStack: false,
        quantity: 1,
        source: "test",
        acquiredAt: new Date("2026-10-13T00:00:00.000Z"),
      });
      await expect(removeMajorGear(db, "qi")).rejects.toThrow("还有人拿着这一阶的装备");
      const [kept] = await db.select().from(contentItems).where(eq(contentItems.slug, gearSlug("qi", "weapon", "white")));
      expect(kept?.displayName).toBeTruthy();
    });
  });
});
