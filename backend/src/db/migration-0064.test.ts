import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const text = readFileSync(new URL("../../drizzle/0064_offline_loot.sql", import.meta.url), "utf8");

describe("migration 0064 offline loot", () => {
  it("adds loot jsonb and bag_full_skipped on player_offline_reports", () => {
    expect(text).toContain('ADD COLUMN IF NOT EXISTS "loot"');
    expect(text).toContain('ADD COLUMN IF NOT EXISTS "bag_full_skipped"');
    expect(text).toContain("player_offline_reports");
  });

  it("is registered in the journal after 0063", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string; when: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0064_offline_loot");
    const prev = journal.entries.find((entry) => entry.tag === "0063_skill_cast_config");
    expect(row).toBeTruthy();
    expect(prev).toBeTruthy();
    expect(row!.when).toBeGreaterThan(prev!.when);
  });
});
