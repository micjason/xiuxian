import { describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { contentDropEntries, contentDropTables } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { applyPrototypeV12 } from "./prototype-v12.js";
import { deleteDraftDropTable, listDraftDropTables, saveDraftDropTable } from "./draft-service.js";

describe("drop tables admin", () => {
  it("lists tables with entries and stage references", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const rows = await listDraftDropTables(db);
      expect(rows.length).toBeGreaterThan(0);
      const boss = rows.find((row) => row.id === "proto_boss");
      expect(boss).toBeTruthy();
      expect(boss!.stageRefs.some((ref) => ref.roles.includes("boss"))).toBe(true);
      expect(boss!.stageRefs[0]?.displayName).toBeTruthy();
    });
  });

  it("saves entries live and refuses delete while referenced", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      await saveDraftDropTable(
        db,
        {
          slug: "proto_boss",
          displayName: "原型首领掉落",
          entries: [{ itemSlug: "enh_stone_low", chanceBp: 5000, minQty: 1, maxQty: 2 }],
        },
        null,
      );
      const [entry] = await db.select().from(contentDropEntries).where(eq(contentDropEntries.dropTableSlug, "proto_boss"));
      expect(entry).toMatchObject({ itemSlug: "enh_stone_low", chanceBp: 5000, minQty: 1, maxQty: 2 });
      const listed = await listDraftDropTables(db);
      expect(listed.find((row) => row.id === "proto_boss")?.entries[0]?.itemName).toContain("突破石");
      await expect(deleteDraftDropTable(db, "proto_boss")).rejects.toThrow(/关卡引用/);
      await saveDraftDropTable(db, { slug: "orphan_drop", displayName: "无引用表", entries: [] }, null);
      await deleteDraftDropTable(db, "orphan_drop");
      const orphan = await db.select().from(contentDropTables).where(eq(contentDropTables.slug, "orphan_drop"));
      expect(orphan).toEqual([]);
    });
  });
});
