import { describe, expect, it } from "vitest";
import { contentRealms } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { runTrial } from "./trial.js";

describe("trial battle", () => {
  it("asks for a saved puppet instead of loose stats", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({ slug: "1", displayName: "凡人", sortOrder: 1, nextRealmSlug: null, baseAttack: 10, baseHp: 100 });
      await expect(runTrial(db, { boss: { attack: 12, defense: 0, hp: 150, interval: 1.5 } })).rejects.toMatchObject({
        message: "请选择人偶",
      });
      await expect(runTrial(db, { puppetIds: [], boss: { attack: 12, defense: 0, hp: undefined, interval: 1.5 } })).rejects.toMatchObject({
        message: "请选择人偶",
      });
    });
  });
});
