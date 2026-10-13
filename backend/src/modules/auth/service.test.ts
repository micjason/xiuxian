import { describe, expect, it } from "vitest";
import { listOperations } from "../operations/record.js";
import { insertStartingRealm, withDb } from "../../test/db.js";
import { createAdmin, loginAdmin, loginPlayer, readSession, registerPlayer, revokeSession } from "./service.js";
import { AppError } from "../../shared/errors.js";
import { admins } from "../../db/schema.js";
import { eq } from "drizzle-orm";

const now = new Date("2026-10-06T08:00:00.000Z");

describe("auth", () => {
  it("registers a player and reads the session", async () => {
    await withDb(async (db) => {
      await insertStartingRealm(db);
      const created = await registerPlayer(db, {
        username: "player_one",
        password: "correct-horse",
        now,
      });
      const session = await readSession(db, created.token, now);
      expect(session).toEqual({
        actorType: "player",
        actorId: created.playerId,
        actorName: "player_one",
      });
    });
  });

  it("rejects a bad password without storing it", async () => {
    await withDb(async (db) => {
      await insertStartingRealm(db);
      await registerPlayer(db, { username: "player_two", password: "correct-horse", now });
      const result = await loginPlayer(db, {
        username: "player_two",
        password: "wrong-password",
        now,
      });
      expect(result).toEqual({ ok: false, reason: "bad_password" });
      const rows = await listOperations(db, {
        name: "player_two",
        action: "login",
        from: new Date("2026-10-05T00:00:00.000Z"),
        to: new Date("2026-10-07T00:00:00.000Z"),
      });
      const failed = rows.filter((row) => row.result === "failure");
      expect(failed.length).toBeGreaterThan(0);
      expect(JSON.stringify(failed)).not.toContain("wrong-password");
      expect(JSON.stringify(failed)).not.toContain("correct-horse");
    });
  });

  it("logs an admin in after createAdmin", async () => {
    await withDb(async (db) => {
      await createAdmin(db, { username: "root_admin", password: "admin-secret" });
      const result = await loginAdmin(db, {
        username: "root_admin",
        password: "admin-secret",
        now,
      });
      expect(result.ok).toBe(true);
      if (!result.ok) {
        return;
      }
      const session = await readSession(db, result.token, now);
      expect(session?.actorType).toBe("admin");
      expect(session?.actorName).toBe("root_admin");
    });
  });

  it("treats usernames as case-insensitive and revokes a logged-out token", async () => {
    await withDb(async (db) => {
      await insertStartingRealm(db);
      await registerPlayer(db, { username: "CaseUser", password: "correct-horse", now });
      await expect(registerPlayer(db, { username: "caseuser", password: "correct-horse", now })).rejects.toBeInstanceOf(
        AppError,
      );
      const loggedIn = await loginPlayer(db, { username: "CASEUSER", password: "correct-horse", now });
      expect(loggedIn.ok).toBe(true);
      if (!loggedIn.ok) {
        return;
      }
      expect(await readSession(db, loggedIn.token, now)).not.toBeNull();
      await revokeSession(db, loggedIn.token, now);
      expect(await readSession(db, loggedIn.token, now)).toBeNull();
    });
  });

  it("expires an admin session after twelve hours and keeps a player session", async () => {
    await withDb(async (db) => {
      await insertStartingRealm(db);
      const player = await registerPlayer(db, { username: "long_player", password: "correct-horse", now });
      await createAdmin(db, { username: "short_admin", password: "admin-secret", role: "designer" });
      const admin = await loginAdmin(db, { username: "short_admin", password: "admin-secret", now });
      expect(admin.ok).toBe(true);
      if (!admin.ok) {
        return;
      }
      const later = new Date(now.getTime() + 13 * 60 * 60 * 1000);
      expect(await readSession(db, player.token, later)).not.toBeNull();
      expect(await readSession(db, admin.token, later)).toBeNull();
      const [row] = await db.select().from(admins).where(eq(admins.username, "short_admin")).limit(1);
      expect(row?.role).toBe("designer");
    });
  });
});
