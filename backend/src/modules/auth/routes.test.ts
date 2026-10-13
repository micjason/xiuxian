import { describe, expect, it } from "vitest";
import { buildApp } from "../../app.js";
import { insertStartingRealm, withDb } from "../../test/db.js";
import { createAdmin } from "./service.js";

const now = new Date("2026-10-08T08:00:00.000Z");

describe("auth routes", () => {
  it("rejects a bad username, a duplicate, and a logged-out token", async () => {
    await withDb(async (db) => {
      await insertStartingRealm(db);
      const app = await buildApp(db, () => now);
      const invalid = await app.inject({
        method: "POST",
        url: "/api/v1/auth/register",
        payload: { username: "a", password: "correct-horse" },
      });
      expect(invalid.statusCode).toBe(400);
      expect(invalid.json().error.code).toBe("INVALID_INPUT");

      const created = await app.inject({
        method: "POST",
        url: "/api/v1/auth/register",
        payload: { username: "route_user", password: "correct-horse" },
      });
      expect(created.statusCode).toBe(200);
      const token = created.json().token as string;

      const taken = await app.inject({
        method: "POST",
        url: "/api/v1/auth/register",
        payload: { username: "ROUTE_USER", password: "correct-horse" },
      });
      expect(taken.statusCode).toBe(409);
      expect(taken.json().error.code).toBe("USERNAME_TAKEN");

      const wrong = await app.inject({
        method: "POST",
        url: "/api/v1/auth/login",
        payload: { username: "missing_user", password: "correct-horse" },
      });
      const wrongPassword = await app.inject({
        method: "POST",
        url: "/api/v1/auth/login",
        payload: { username: "route_user", password: "other-horse" },
      });
      expect(wrong.statusCode).toBe(401);
      expect(wrongPassword.statusCode).toBe(401);
      expect(wrong.json()).toEqual(wrongPassword.json());
      expect(wrong.json().error.code).toBe("INVALID_CREDENTIALS");

      const loggedOut = await app.inject({
        method: "POST",
        url: "/api/v1/auth/logout",
        headers: { authorization: `Bearer ${token}` },
      });
      expect(loggedOut.statusCode).toBe(200);
      const me = await app.inject({
        method: "GET",
        url: "/api/v1/me",
        headers: { authorization: `Bearer ${token}` },
      });
      expect(me.statusCode).toBe(401);
      await app.close();
    });
  });

  it("returns 429 after the login limit", async () => {
    await withDb(async (db) => {
      const app = await buildApp(db, () => now);
      for (let i = 0; i < 10; i += 1) {
        const response = await app.inject({
          method: "POST",
          url: "/auth/login",
          payload: { username: "nobody", password: "wrong-pass" },
        });
        expect(response.statusCode).toBe(401);
      }
      const limited = await app.inject({
        method: "POST",
        url: "/auth/login",
        payload: { username: "nobody", password: "wrong-pass" },
      });
      expect(limited.statusCode).toBe(429);
      expect(limited.json().error.code).toBe("RATE_LIMITED");
      await app.close();
    });
  });

  it("logs an admin out", async () => {
    await withDb(async (db) => {
      await createAdmin(db, { username: "logout_admin", password: "admin-secret" });
      const app = await buildApp(db, () => now);
      const login = await app.inject({
        method: "POST",
        url: "/admin/auth/login",
        payload: { username: "logout_admin", password: "admin-secret" },
      });
      const token = login.json().token as string;
      const logout = await app.inject({
        method: "POST",
        url: "/api/v1/admin/auth/logout",
        headers: { authorization: `Bearer ${token}` },
      });
      expect(logout.statusCode).toBe(200);
      const players = await app.inject({
        method: "GET",
        url: "/admin/players",
        headers: { authorization: `Bearer ${token}` },
      });
      expect(players.statusCode).toBe(401);
      await app.close();
    });
  });
});
