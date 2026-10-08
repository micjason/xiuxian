import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentRealms, contentVersions } from "../../db/schema.js";
import { registerPlayer } from "../auth/service.js";
import { syncFromSnapshot } from "../player/service.js";
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
        gainPerTick: 2,
        tickSeconds: 1,
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
      const player = await registerPlayer(db, { username: "syncer", password: "correct-horse", now: new Date("2026-10-08T02:00:00.000Z") });
      const synced = await syncFromSnapshot(db, player.playerId, new Date("2026-10-08T02:00:10.000Z"));
      const [stored] = await db.select().from(contentVersions);
      expect(JSON.stringify(stored?.snapshot)).toContain("gainPerTick");
      expect(synced.cultivation).toBeGreaterThan(0);
      expect(synced.contentVersion).toBe(2);
    });
  });
});
