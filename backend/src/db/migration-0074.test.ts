import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("migration 0074 slot-bound enhance", () => {
  it("adds player_slot_enhances, migrates equipped levels, clears item levels, steeps costGrowth", () => {
    const sql = readFileSync(new URL("../../drizzle/0074_slot_bound_enhance.sql", import.meta.url), "utf8");
    expect(sql).toContain("player_slot_enhances");
    expect(sql).toContain("enhance_level");
    expect(sql).toContain("slotBound");
    expect(sql).toContain("1.4");
    expect(sql).toContain('UPDATE "player_items" SET "enhance_level" = 0');
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string; when: number; idx: number }[];
    };
    const row = journal.entries.find((e) => e.tag === "0074_slot_bound_enhance");
    expect(row).toBeTruthy();
    expect(row!.when).toBe(1801400000000);
    expect(row!.idx).toBe(64);
    // #60 已合入：0073 与 0074 并存，勿互相覆盖
    const auto = journal.entries.find((e) => e.tag === "0073_auto_decompose_qualities");
    expect(auto).toBeTruthy();
    expect(auto!.idx).toBe(63);
  });
});
