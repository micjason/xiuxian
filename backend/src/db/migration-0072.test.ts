import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("migration 0072 dongfu puppet forge", () => {
  it("adds puppet_state, forge table, items, grant source", () => {
    const sql = readFileSync(new URL("../../drizzle/0072_dongfu_puppet_forge.sql", import.meta.url), "utf8");
    expect(sql).toContain('ADD COLUMN IF NOT EXISTS "puppet_state"');
    expect(sql).toContain("player_dongfu_forge");
    expect(sql).toContain("puppet_meat");
    expect(sql).toContain("puppet_stone");
    expect(sql).toContain("dongfu_forge");
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string }[];
    };
    expect(journal.entries.some((e) => e.tag === "0072_dongfu_puppet_forge")).toBe(true);
  });
});
