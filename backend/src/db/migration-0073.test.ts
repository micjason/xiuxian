/**
 * 迁移 0073：player_states.auto_decompose_qualities（默认白绿蓝）。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { playerStates, players } from "./schema.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0073_auto_decompose_qualities.sql", import.meta.url), "utf8");

async function migrate(db: TestDb) {
  for (const statement of text.split("--> statement-breakpoint").map((part) => part.replace(/^--.*$/gm, "").trim()).filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

describe("migration 0073 (挂机自动分解品质)", () => {
  it("is in the journal right after 0072", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { idx: number; tag: string; when: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0073_auto_decompose_qualities");
    const prev = journal.entries.find((entry) => entry.tag === "0072_dongfu_puppet_forge");
    expect(row?.idx).toBe(63);
    expect(row?.when).toBe(1801300000000);
    expect(row!.when).toBeGreaterThan(prev!.when);
  });

  it("adds the column with default white/green/blue; running twice is a no-op", async () => {
    await withDb(async (db) => {
      // 先确保列在（测试库可能还没跑过 0073）；可重复执行。
      await migrate(db);
      const [player] = await db.insert(players).values({ username: "m73", passwordHash: "x" }).returning();
      await db.insert(playerStates).values({
        playerId: player!.id,
        cultivation: 0,
        realmSlug: "r",
        lastSettledAt: new Date(),
      });
      const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, player!.id));
      expect(state?.autoDecomposeQualities).toEqual(["white", "green", "blue"]);
      await migrate(db);
      const [again] = await db.select().from(playerStates).where(eq(playerStates.playerId, player!.id));
      expect(again?.autoDecomposeQualities).toEqual(["white", "green", "blue"]);
    });
  });
});
