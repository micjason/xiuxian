import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { withDb } from "../test/db.js";
import { createAdmin, loginAdmin } from "../modules/auth/service.js";

describe("unified input errors", () => {
  it("returns INVALID_INPUT when a required field is missing", async () => {
    await withDb(async (db) => {
      const now = new Date("2026-10-08T12:00:00.000Z");
      await createAdmin(db, { username: "form_admin", password: "admin-secret" });
      const admin = await loginAdmin(db, { username: "form_admin", password: "admin-secret", now });
      if (!admin.ok) {
        throw new Error("admin login failed");
      }
      const app = await buildApp(db, () => now);
      const headers = { authorization: `Bearer ${admin.token}` };
      const cases = [
        { method: "GET" as const, url: "/api/v1/admin/operations" },
        { method: "POST" as const, url: "/api/v1/admin/repairs/preview", payload: {} },
        { method: "POST" as const, url: "/api/v1/admin/content/import", payload: {} },
        { method: "POST" as const, url: "/api/v1/admin/announcements", payload: {} },
      ];
      for (const item of cases) {
        const response = await app.inject({ ...item, headers });
        expect(response.statusCode, item.url).toBe(400);
        expect(response.json().error.code, item.url).toBe("INVALID_INPUT");
      }
      const missingRelease = await app.inject({ method: "GET", url: "/api/v1/update.json" });
      expect(missingRelease.statusCode).toBe(404);
      expect(missingRelease.json().error.code).toBe("NOT_FOUND");
      await app.close();
    });
  });
});
