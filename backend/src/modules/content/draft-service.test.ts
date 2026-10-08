import { describe, expect, it } from "vitest";
import { contentKnownSlugs } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import { withDb } from "../../test/db.js";
import { deleteDraftItem, saveDraftDropTable, saveDraftItem, saveDraftSkill } from "./draft-service.js";

describe("draft service", () => {
  it("rejects a missing skill reference and a published slug", async () => {
    await withDb(async (db) => {
      await expect(
        saveDraftItem(db, { slug: "breath_book", displayName: "吐纳书", kind: "skill_book", skillSlug: "missing" }, null),
      ).rejects.toBeInstanceOf(AppError);
      await saveDraftSkill(db, { slug: "breath", displayName: "吐纳", role: "heart", cultivateBonusBp: 1000 }, null);
      await saveDraftItem(db, { slug: "breath_book", displayName: "吐纳书", kind: "skill_book", skillSlug: "breath" }, null);
      await saveDraftItem(db, { slug: "wood_sword", displayName: "木剑", kind: "equipment", slot: "weapon", attack: 4 }, null);
      await expect(
        saveDraftDropTable(
          db,
          { slug: "drop_first", displayName: "首通", entries: [{ itemSlug: "missing", chanceBp: 10000, minQty: 1, maxQty: 1 }] },
          null,
        ),
      ).rejects.toBeInstanceOf(AppError);
      await saveDraftDropTable(
        db,
        { slug: "drop_first", displayName: "首通", entries: [{ itemSlug: "wood_sword", chanceBp: 10000, minQty: 1, maxQty: 1 }] },
        null,
      );
      await db.insert(contentKnownSlugs).values({ kind: "item", slug: "wood_sword" });
      await expect(deleteDraftItem(db, "wood_sword")).rejects.toMatchObject({ code: "SLUG_PUBLISHED" });
      await deleteDraftItem(db, "breath_book");
    });
  });
});