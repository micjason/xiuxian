import { describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { contentGlobals, contentItems, contentRealms, playerStates } from "../../db/schema.js";
import { withTransaction } from "../../db/tx.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "../auth/service.js";
import { STARTING_ENHANCE_RULES } from "../content/enhance.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { setAutoDecompose, readState } from "./actions.js";
import {
  DEFAULT_AUTO_DECOMPOSE_QUALITIES,
  normalizeAutoDecomposeQualities,
  isAutoDecomposeGrantSource,
} from "./auto-decompose.js";

const now = new Date("2026-11-03T04:00:00.000Z");

describe("auto-decompose helpers", () => {
  it("normalizes qualities: default, filter, sort, dedupe", () => {
    expect(normalizeAutoDecomposeQualities(undefined)).toEqual(DEFAULT_AUTO_DECOMPOSE_QUALITIES);
    expect(normalizeAutoDecomposeQualities(["orange", "white", "white", "bogus", "blue"])).toEqual(["white", "blue", "orange"]);
    expect(normalizeAutoDecomposeQualities([])).toEqual([]);
    expect(isAutoDecomposeGrantSource("stage_drop")).toBe(true);
    expect(isAutoDecomposeGrantSource("admin_grant")).toBe(false);
  });
});

describe("setAutoDecompose / state", () => {
  it("saves qualities and exposes them on state; enabled maps to default or empty", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({
        slug: "1",
        displayName: "凡人",
        sortOrder: 1,
        nextRealmSlug: null,
        baseAttack: 10,
        baseDefense: 1,
        baseHp: 100,
        baseInterval: 1.5,
        tickSeconds: 1,
        gainPerTick: 1,
      });
      await db.insert(contentGlobals).values({
        id: 1,
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        enhance: STARTING_ENHANCE_RULES,
        powerWeights: { attack: 1, defense: 1, hp: 1, speed: 1 },
        combat: { minInterval: 0.5, defenseConstant: 1, recommendedPowerMargin: 1.05, challengeCooldownSeconds: 0, timeLimitSeconds: 45, speedBase: 100 },
      });
      await db.insert(contentItems).values({ slug: "refine_essence", displayName: "炼器精粹", kind: "material", quality: "orange", stackable: true });
      const player = await registerPlayer(db, { username: "ads", password: "correct-horse", now });
      const world = (await loadCurrentWorld(db))!;
      const cleared = await withTransaction(db, (tx) => setAutoDecompose(tx, world, player.playerId, { qualities: [] }, now));
      expect(cleared.state.autoDecompose).toBe(false);
      expect(cleared.state.autoDecomposeQualities).toEqual([]);
      const set = await withTransaction(db, (tx) => setAutoDecompose(tx, world, player.playerId, { qualities: ["purple", "white"] }, now));
      expect(set.state.autoDecomposeQualities).toEqual(["white", "purple"]);
      expect(set.state.autoDecompose).toBe(true);
      const viaBool = await withTransaction(db, (tx) => setAutoDecompose(tx, world, player.playerId, { enabled: true }, now));
      expect(viaBool.state.autoDecomposeQualities).toEqual(["white", "green", "blue"]);
      const off = await withTransaction(db, (tx) => setAutoDecompose(tx, world, player.playerId, { enabled: false }, now));
      expect(off.state.autoDecomposeQualities).toEqual([]);
      const [row] = await db.select().from(playerStates).where(eq(playerStates.playerId, player.playerId));
      expect(row?.autoDecompose).toBe(false);
      const state = await readState(db, player.playerId, now);
      expect(state.autoDecomposeQualities).toEqual([]);
    });
  });
});
