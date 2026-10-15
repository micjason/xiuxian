import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals } from "../../db/schema.js";
import { withDb, insertStartingRealm } from "../../test/db.js";
import { readRules, saveRules } from "./rules.js";
import { DEFAULT_OPTIONAL_RULES, OPTIONAL_RULES } from "./combat-types.js";
import { loadCurrentWorld } from "./snapshot.js";
import { readGameRules } from "./rules.js";

const base = {
  offlineCapSeconds: 28800,
  bagCapacity: 20,
  attackWeight: 4.7,
  defenseWeight: 1.6,
  hpWeight: 0.95,
  speedWeight: 2.6,
  minInterval: 0.5,
  challengeCooldownSeconds: 0,
  timeLimitSeconds: 45,
  defenseConstant: 1,
  speedBase: 100,
  recommendedPowerMargin: 1.05,
};

describe("combat-system rules are admin-configurable with table defaults", () => {
  it("old content without the new keys reads the defaults (15 s, 300 s, 2 s, 5 per day, 05:00, 3 per wave, 2 s, 3 s)", async () => {
    await withDb(async (db) => {
      await insertStartingRealm(db);
      const rules = await readRules(db);
      expect(rules).toMatchObject(DEFAULT_OPTIONAL_RULES);
      expect(DEFAULT_OPTIONAL_RULES).toEqual({ onlineGapSeconds: 15, offlinePopupMinSeconds: 300, ultAutoCastWindowSeconds: 2, bossDailyRewardCount: 5, dayStartHour: 5, waveSize: 3, waveTransitionSeconds: 2, reviveSeconds: 3 });
      const world = await loadCurrentWorld(db);
      expect(readGameRules(world!)).toMatchObject(DEFAULT_OPTIONAL_RULES);
    });
  });

  it("saves, reads back and keeps the values when a later save omits them", async () => {
    await withDb(async (db) => {
      await insertStartingRealm(db);
      const saved = await saveRules(db, { ...base, onlineGapSeconds: 20, offlinePopupMinSeconds: 600, ultAutoCastWindowSeconds: 3, bossDailyRewardCount: 5, dayStartHour: 4, waveSize: 4, waveTransitionSeconds: 1.5, reviveSeconds: 5 }, null);
      expect(saved).toMatchObject({ onlineGapSeconds: 20, offlinePopupMinSeconds: 600, ultAutoCastWindowSeconds: 3, bossDailyRewardCount: 5, dayStartHour: 4, waveSize: 4, waveTransitionSeconds: 1.5, reviveSeconds: 5 });
      const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1));
      expect(row?.combat?.onlineGapSeconds).toBe(20);
      const again = await saveRules(db, { ...base }, null);
      expect(again).toMatchObject({ onlineGapSeconds: 20, waveSize: 4, reviveSeconds: 5 });
    });
  });

  it("rejects out-of-range and non-integer values with a Chinese message", async () => {
    await withDb(async (db) => {
      await insertStartingRealm(db);
      await expect(saveRules(db, { ...base, onlineGapSeconds: 0 }, null)).rejects.toThrow(/在线判定间隔/);
      await expect(saveRules(db, { ...base, dayStartHour: 24 }, null)).rejects.toThrow(/每日重置整点/);
      await expect(saveRules(db, { ...base, waveSize: 2.5 }, null)).rejects.toThrow(/每波怪物数要填整数/);
      await expect(saveRules(db, { ...base, bossDailyRewardCount: -1 }, null)).rejects.toThrow(/首领每日奖励次数/);
      expect(Object.keys(OPTIONAL_RULES)).toHaveLength(8);
    });
  });
});
