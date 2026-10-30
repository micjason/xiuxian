/**
 * 迁移 0063：content_skills 增加 cast_every_attacks / damage_mult_bp，默认对齐旧硬编码（每 4 次普攻、1.0× 伤害）。
 * when 必须 ≥ 1800300000000，且晚于 0062。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentSkills } from "./schema.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0063_skill_cast_config.sql", import.meta.url), "utf8");
const seed62 = readFileSync(new URL("../../drizzle/0062_outfit_skill_defaults.sql", import.meta.url), "utf8");

async function runSql(db: TestDb, raw: string) {
  for (const statement of raw
    .split("--> statement-breakpoint")
    .map((part) => part.replace(/^--.*$/gm, "").trim())
    .filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

describe("migration 0063 (技能施法节奏与伤害倍率)", () => {
  it("is journaled after 0062 with when ≥ 1800300000000", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as {
      entries: { tag: string; when: number; idx: number }[];
    };
    const row = journal.entries.find((entry) => entry.tag === "0063_skill_cast_config");
    const prev = journal.entries.find((entry) => entry.tag === "0062_outfit_skill_defaults");
    expect(row).toBeTruthy();
    expect(prev).toBeTruthy();
    expect(row!.when).toBeGreaterThanOrEqual(1800300000000);
    expect(row!.when).toBeGreaterThan(prev!.when);
    expect(row!.idx).toBeGreaterThan(prev!.idx);
  });

  it("adds columns with defaults matching old cast pacing and does not wipe later edits", async () => {
    await withDb(async (db) => {
      await runSql(db, seed62);
      await runSql(db, text);
      await runSql(db, text);
      const rows = await db.select().from(contentSkills);
      expect(rows.length).toBeGreaterThanOrEqual(1);
      expect(rows.every((row) => row.castEveryAttacks === 4 && row.damageMultBp === 10000)).toBe(true);

      await db.update(contentSkills).set({ castEveryAttacks: 2, damageMultBp: 15000 }).where(eq(contentSkills.slug, "skill_liekong"));
      await runSql(db, text);
      const [kept] = await db.select().from(contentSkills).where(eq(contentSkills.slug, "skill_liekong"));
      expect(kept).toMatchObject({ castEveryAttacks: 2, damageMultBp: 15000 });
    });
  });
});
