import { describe, expect, it } from "vitest";
import { contentGlobals, contentRealms } from "../db/schema.js";
import { publishSnapshot } from "../modules/content/snapshot.js";
import { withDb } from "../test/db.js";
import { buildApp } from "../app.js";

describe("client version gate", () => {
  it("returns 426 when the client is older than the published minimum", async () => {
    await withDb(async (db) => {
      await db.insert(contentGlobals).values({ id: 1, minClientVersionCode: 30 });
      await db.insert(contentRealms).values({
        slug: "mortal",
        displayName: "凡人",
        sortOrder: 0,
        nextRealmSlug: null,
        baseRateBp: 10000,
        minRateBp: 10000,
        maxRateBp: 10000,
      });
      await publishSnapshot(db, "版本闸门", null, new Date("2026-10-08T00:00:00.000Z"));
      const app = await buildApp(db, () => new Date("2026-10-08T00:00:00.000Z"));
      const registered = await app.inject({
        method: "POST",
        url: "/api/v1/auth/register",
        payload: { username: "old_client", password: "correct-horse" },
      });
      const token = registered.json().token as string;
      const blocked = await app.inject({
        method: "GET",
        url: "/api/v1/me/state",
        headers: { authorization: `Bearer ${token}`, "x-client-version": "24" },
      });
      expect(blocked.statusCode).toBe(426);
      expect(blocked.json().error.code).toBe("CLIENT_TOO_OLD");
      const allowed = await app.inject({
        method: "GET",
        url: "/api/v1/me/state",
        headers: { authorization: `Bearer ${token}`, "x-client-version": "30" },
      });
      expect(allowed.statusCode).toBe(200);
      await app.close();
    });
  });
});
