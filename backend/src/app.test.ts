import { describe, expect, it } from "vitest";
import { createAdmin } from "./modules/auth/service.js";
import { withDb } from "./test/db.js";
import { buildApp } from "./app.js";

describe("buildApp", { timeout: 30_000 }, () => {
  it("serves register, publish, and progress without an admin signup route", async () => {
    await withDb(async (db) => {
      await createAdmin(db, { username: "app-admin", password: "admin-secret" });
      const app = await buildApp(db);
      const health = await app.inject({ method: "GET", url: "/healthz" });
      expect(health.statusCode).toBe(200);
      expect(health.json().ok).toBe(true);
      const missing = await app.inject({
        method: "POST",
        url: "/admin/auth/register",
        payload: { username: "other", password: "nope" },
      });
      expect(missing.statusCode).toBe(404);

      const registered = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: { username: "app-player", password: "correct-horse" },
      });
      expect(registered.statusCode).toBe(200);
      const playerToken = registered.json().token as string;

      const adminLogin = await app.inject({
        method: "POST",
        url: "/admin/auth/login",
        payload: { username: "app-admin", password: "admin-secret" },
      });
      expect(adminLogin.statusCode).toBe(200);
      const adminToken = adminLogin.json().token as string;

      const saved = await app.inject({
        method: "PUT",
        url: "/admin/content/realms/mortal",
        headers: { authorization: `Bearer ${adminToken}` },
        payload: {
          displayName: "凡人",
          sortOrder: 0,
          gainPerSecond: 2,
          breakthroughCost: 360,
          nextSlug: "qi_early",
          attack: 10,
          defense: 6,
          hp: 50,
          speed: 0,
        },
      });
      expect(saved.statusCode).toBe(200);
      const savedNext = await app.inject({
        method: "PUT",
        url: "/admin/content/realms/qi_early",
        headers: { authorization: `Bearer ${adminToken}` },
        payload: {
          displayName: "炼气初期",
          sortOrder: 1,
          gainPerSecond: 4,
          breakthroughCost: 1200,
          nextSlug: null,
          attack: 16,
          defense: 10,
          hp: 70,
          speed: 0,
        },
      });
      expect(savedNext.statusCode).toBe(200);
      const published = await app.inject({
        method: "POST",
        url: "/admin/content/publish",
        headers: { authorization: `Bearer ${adminToken}` },
      });
      expect(published.statusCode).toBe(200);

      const denied = await app.inject({
        method: "POST",
        url: "/admin/content/publish",
        headers: { authorization: `Bearer ${playerToken}` },
      });
      expect(denied.statusCode).toBe(403);

      const me = await app.inject({
        method: "GET",
        url: "/me",
        headers: { authorization: `Bearer ${playerToken}` },
      });
      expect(me.statusCode).toBe(200);
      expect(me.json().realmName).toBe("凡人");
      await app.close();
    });
  });
});
