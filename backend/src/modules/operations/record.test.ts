import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { listOperations, writeCrash, writeOperation } from "./record.js";
import { withDb } from "../../test/db.js";

describe("operation records", () => {
  it("stores a row and drops password fields", async () => {
    await withDb(async (db) => {
      const at = new Date("2026-10-06T00:00:00.000Z");
      await writeOperation(db, {
        at,
        actorType: "player",
        actorId: null,
        actorName: "甲",
        action: "settle",
        result: "failure",
        reason: "missing_release",
        summary: { password: "secret", before: 1 },
      });
      const rows = await listOperations(db, {
        name: "甲",
        from: new Date("2026-10-05T00:00:00.000Z"),
        to: new Date("2026-10-07T00:00:00.000Z"),
      });
      expect(rows).toHaveLength(1);
      expect(rows[0]?.summary).toEqual({ before: 1 });
      expect(JSON.stringify(rows[0])).not.toContain("secret");
    });
  });
});

describe("writeCrash", () => {
  it("writes the message and omits secrets", async () => {
    const dir = await mkdtemp(path.join(tmpdir(), "xiuxian-crash-"));
    const filePath = path.join(dir, "crash.log");
    writeCrash({ password: "secret", message: "boom" }, filePath);
    const text = await readFile(filePath, "utf8");
    expect(text).toContain("boom");
    expect(text).not.toContain("secret");
  });
});
