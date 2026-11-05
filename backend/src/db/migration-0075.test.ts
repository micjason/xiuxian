import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("migration 0075 fog p0", () => {
  it("adds player_fog_runs and seeds 问心谷 fog_wenxin_valley", () => {
    const sql = readFileSync(new URL("../../drizzle/0075_fog_p0.sql", import.meta.url), "utf8");
    expect(sql).toContain("player_fog_runs");
    expect(sql).toContain("fog_wenxin_valley");
    expect(sql).toContain("m_slime");
    expect(sql).toContain("e_herb");
    expect(sql).toContain('"travelPointsMax": 20');
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string; when: number; idx: number }[];
    };
    const row = journal.entries.find((e) => e.tag === "0075_fog_p0");
    expect(row).toBeTruthy();
    expect(row!.when).toBe(1801500000000);
    expect(row!.idx).toBe(65);
  });
});
