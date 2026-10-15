import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { sql } from "drizzle-orm";
import { playerStates, players } from "./schema.js";
import { withDb } from "../test/db.js";

describe("migration 0018", () => {
  it("adds cultivation_remainder_bp as a NOT NULL integer that defaults to 0", async () => {
    const text = readFileSync(new URL("../../drizzle/0018_cultivation_remainder.sql", import.meta.url), "utf8");
    expect(text).toContain('ADD COLUMN "cultivation_remainder_bp" integer DEFAULT 0 NOT NULL');
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as { entries: { idx: number; tag: string }[] };
    expect(journal.entries[18]).toMatchObject({ idx: 18, tag: "0018_cultivation_remainder" });
    await withDb(async (db) => {
      const columns = (await db.execute(
        sql`select data_type, is_nullable, column_default from information_schema.columns where table_name = 'player_states' and column_name = 'cultivation_remainder_bp'`,
      )) as unknown as { data_type: string; is_nullable: string; column_default: string }[];
      expect(columns[0]).toMatchObject({ data_type: "integer", is_nullable: "NO", column_default: "0" });
      const [player] = await db
        .insert(players)
        .values({ username: "m18", usernameLower: "m18", passwordHash: "x" })
        .returning({ id: players.id });
      await db.insert(playerStates).values({ playerId: player!.id, cultivation: 0, realmSlug: "r", lastSettledAt: new Date() });
      const [row] = await db.select().from(playerStates);
      expect(row?.cultivationRemainderBp).toBe(0);
    });
  });
});
