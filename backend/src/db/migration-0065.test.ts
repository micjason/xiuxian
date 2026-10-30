import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const text = readFileSync(new URL("../../drizzle/0065_drop_realm_ult.sql", import.meta.url), "utf8");

describe("migration 0065 drop realm ult", () => {
  it("drops the four content_realms ult columns", () => {
    expect(text).toContain('DROP COLUMN IF EXISTS "ult_name"');
    expect(text).toContain('DROP COLUMN IF EXISTS "ult_damage_mult_bp"');
    expect(text).toContain('DROP COLUMN IF EXISTS "ult_cooldown_seconds"');
    expect(text).toContain('DROP COLUMN IF EXISTS "ult_first_cooldown_seconds"');
    expect(text).toContain("content_realms");
  });

  it("is registered in the journal after 0064", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string; when: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0065_drop_realm_ult");
    const prev = journal.entries.find((entry) => entry.tag === "0064_offline_loot");
    expect(row).toBeTruthy();
    expect(prev).toBeTruthy();
    expect(row!.when).toBeGreaterThan(prev!.when);
    expect(row!.when).toBeGreaterThan(1800400000000);
  });
});
