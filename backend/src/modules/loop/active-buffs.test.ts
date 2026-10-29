import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentItems, playerItems, playerStates, players } from "../../db/schema.js";
import { applyPrototypeV12 } from "../content/prototype-v12.js";
import { loadDraftSnapshot } from "../content/snapshot.js";
import { withDb } from "../../test/db.js";
import { withTransaction } from "../../db/tx.js";
import { applyActiveBuff, applyBuffsToStats, listActiveBuffs, sumActiveBuffs } from "./active-buffs.js";
import { combatStats, useItem } from "./actions.js";
import { readFileSync } from "node:fs";
import { sql } from "drizzle-orm";

const start = new Date("2026-10-29T05:00:00.000Z");

async function ensureBuffSchema(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
  const text = readFileSync(new URL("../../../drizzle/0048_player_active_buffs.sql", import.meta.url), "utf8");
  for (const part of text.split("--> statement-breakpoint").map((p) => p.replace(/^--.*$/gm, "").trim()).filter(Boolean)) {
    await db.execute(sql.raw(part));
  }
}

describe("active buffs (临时属性丹)", () => {
  it("sums same-stat buffBp and multiplies combat attack/defense", () => {
    expect(sumActiveBuffs([
      { id: "1", buffStat: "attack", buffBp: 1000, startedAt: start, expiresAt: start, sourceItemSlug: "pill_atk_temp" },
      { id: "2", buffStat: "attack", buffBp: 500, startedAt: start, expiresAt: start, sourceItemSlug: "pill_atk_temp" },
      { id: "3", buffStat: "defense", buffBp: 2000, startedAt: start, expiresAt: start, sourceItemSlug: "pill_def_temp" },
    ])).toEqual({ attackBp: 1500, defenseBp: 2000 });
  });

  it("applyActiveBuff writes row; expired rows are ignored; combat stats get the boost; useItem consumes pill", async () => {
    await withDb(async (db) => {
      await ensureBuffSchema(db);
      await applyPrototypeV12(db);
      await db.insert(contentItems).values({
        slug: "pill_atk_temp",
        displayName: "攻击临时丹",
        kind: "pill",
        quality: "blue",
        stackable: true,
        effect: { buffStat: "attack", buffBp: 1000, durationSeconds: 300 },
      }).onConflictDoUpdate({
        target: contentItems.slug,
        set: { kind: "pill", effect: { buffStat: "attack", buffBp: 1000, durationSeconds: 300 } },
      });
      await db.insert(contentItems).values({
        slug: "pill_def_temp",
        displayName: "防御临时丹",
        kind: "pill",
        quality: "blue",
        stackable: true,
        effect: { buffStat: "defense", buffBp: 1000, durationSeconds: 300 },
      }).onConflictDoUpdate({
        target: contentItems.slug,
        set: { kind: "pill", effect: { buffStat: "defense", buffBp: 1000, durationSeconds: 300 } },
      });

      const world = await loadDraftSnapshot(db);
      const [player] = await db.insert(players).values({ username: "buff1", usernameLower: "buff1", passwordHash: "x" }).returning();
      await db.insert(playerStates).values({ playerId: player!.id, cultivation: 0, spiritStones: 0, realmSlug: "lianqi_1", lastSettledAt: start });
      const [pill] = await db
        .insert(playerItems)
        .values({ playerId: player!.id, itemSlug: "pill_atk_temp", isStack: true, quantity: 2, source: "test", acquiredAt: start })
        .returning();

      // two buffs same stat → sum
      await withTransaction(db, async (tx) => {
        await applyActiveBuff(tx, { playerId: player!.id, buffStat: "attack", buffBp: 1000, durationSeconds: 300, sourceItemSlug: "pill_atk_temp", now: start });
        await applyActiveBuff(tx, { playerId: player!.id, buffStat: "attack", buffBp: 500, durationSeconds: 300, sourceItemSlug: "pill_atk_temp", now: start });
      });
      const active = await listActiveBuffs(db as never, player!.id, start);
      expect(sumActiveBuffs(active).attackBp).toBe(1500);

      const base = combatStats(world, "lianqi_1", [], []);
      const boosted = applyBuffsToStats(base, sumActiveBuffs(active), world);
      expect(boosted.attack).toBeCloseTo(base.attack * 1.15, 5);
      expect(boosted.defense).toBe(base.defense);

      // expired ignored
      const later = new Date(start.getTime() + 400_000);
      expect(await listActiveBuffs(db as never, player!.id, later)).toEqual([]);

      // useItem consumes one stack and writes another buff
      const used = await withTransaction(db, (tx) => useItem(tx, world as never, player!.id, pill!.id, start));
      expect(used.used).toMatchObject({ itemSlug: "pill_atk_temp", buffStat: "attack", buffBp: 1000 });
      const bag = await db.select().from(playerItems).where(eq(playerItems.playerId, player!.id));
      expect(bag.find((row) => row.itemSlug === "pill_atk_temp")?.quantity).toBe(1);
      expect(used.state.activeBuffs?.some((row: { buffStat: string }) => row.buffStat === "attack")).toBe(true);
      expect(used.state.attack).toBeGreaterThan(base.attack);
    });
  });
});
