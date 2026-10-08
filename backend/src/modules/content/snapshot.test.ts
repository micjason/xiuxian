import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentRealms } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { publishSnapshot } from "./snapshot.js";

describe("publishSnapshot", () => {
  it("rejects an empty draft and publishes a valid realm chain", async () => {
    await withDb(async (db) => {
      await expect(publishSnapshot(db, "first", null, new Date("2026-10-08T00:00:00.000Z"))).rejects.toThrow(/发布校验未通过/);
      await db.insert(contentGlobals).values({ id: 1 });
      await db.insert(contentRealms).values({
        slug: "mortal",
        displayName: "凡人",
        sortOrder: 0,
        nextRealmSlug: null,
        baseRateBp: 10000,
        minRateBp: 10000,
        maxRateBp: 10000,
      });
      const published = await publishSnapshot(db, "第一版", null, new Date("2026-10-08T00:00:00.000Z"));
      expect(published.version).toBe(1);
      const again = await publishSnapshot(db, "第二版", null, new Date("2026-10-08T01:00:00.000Z"));
      expect(again.version).toBe(2);
      const rows = await db.select().from(contentRealms).where(eq(contentRealms.slug, "mortal"));
      expect(rows).toHaveLength(1);
    });
  });
});
