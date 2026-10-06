import { describe, expect, it } from "vitest";
import { listOperations } from "../operations/record.js";
import { withDb } from "../../test/db.js";
import { createAdmin, loginAdmin, loginPlayer, readSession, registerPlayer } from "./service.js";

const now = new Date("2026-10-06T08:00:00.000Z");

describe("auth", () => {
  it("registers a player and reads the session", async () => {
    await withDb(async (db) => {
      const created = await registerPlayer(db, {
        username: "player-one",
        password: "correct-horse",
        now,
      });
      const session = await readSession(db, created.token, now);
      expect(session).toEqual({
        actorType: "player",
        actorId: created.playerId,
        actorName: "player-one",
      });
    });
  });

  it("rejects a bad password without storing it", async () => {
    await withDb(async (db) => {
      await registerPlayer(db, { username: "player-two", password: "correct-horse", now });
      const result = await loginPlayer(db, {
        username: "player-two",
        password: "wrong-password",
        now,
      });
      expect(result).toEqual({ ok: false, reason: "bad_password" });
      const rows = await listOperations(db, {
        name: "player-two",
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
      await createAdmin(db, { username: "root-admin", password: "admin-secret" });
      const result = await loginAdmin(db, {
        username: "root-admin",
        password: "admin-secret",
        now,
      });
      expect(result.ok).toBe(true);
      if (!result.ok) {
        return;
      }
      const session = await readSession(db, result.token, now);
      expect(session?.actorType).toBe("admin");
      expect(session?.actorName).toBe("root-admin");
    });
  });
});
