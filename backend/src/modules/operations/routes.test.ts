import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { createAdmin, loginAdmin, registerPlayer } from "../auth/service.js";
import { withDb } from "../../test/db.js";
import { writeOperation } from "./record.js";
import { registerOperationRoutes } from "./routes.js";

const now = new Date("2026-10-06T10:00:00.000Z");

describe("operation routes", { timeout: 20_000 }, () => {
  it("lets an admin read a failed settle and rejects a player", async () => {
    await withDb(async (db) => {
      await createAdmin(db, { username: "auditor", password: "admin-secret" });
      const admin = await loginAdmin(db, { username: "auditor", password: "admin-secret", now });
      const player = await registerPlayer(db, { username: "甲", password: "correct-horse", now });
      if (!admin.ok) {
        throw new Error("admin login failed");
      }
      await writeOperation(db, {
        at: now,
        actorType: "player",
        actorId: player.playerId,
        actorName: "甲",
        action: "settle",
        result: "failure",
        reason: "missing_release",
        summary: { cultivation: 0 },
      });
      const app = Fastify();
      await registerOperationRoutes(app, { db, now: () => now });
      const found = await app.inject({
        method: "GET",
        url: "/admin/operations?name=甲&action=settle&from=2026-10-05T00:00:00.000Z&to=2026-10-07T00:00:00.000Z",
        headers: { authorization: `Bearer ${admin.token}` },
      });
      expect(found.statusCode).toBe(200);
      expect(found.json()).toEqual(
        expect.arrayContaining([expect.objectContaining({ reason: "missing_release", actorName: "甲" })]),
      );
      const denied = await app.inject({
        method: "GET",
        url: "/admin/operations?from=2026-10-05T00:00:00.000Z&to=2026-10-07T00:00:00.000Z",
        headers: { authorization: `Bearer ${player.token}` },
      });
      expect(denied.statusCode).toBe(403);
      await app.close();
    });
  });

  it("returns publish records without a player name", async () => {
    await withDb(async (db) => {
      await createAdmin(db, { username: "publisher-log", password: "admin-secret" });
      const admin = await loginAdmin(db, { username: "publisher-log", password: "admin-secret", now });
      if (!admin.ok) {
        throw new Error("admin login failed");
      }
      await writeOperation(db, {
        at: now,
        actorType: "admin",
        actorId: admin.adminId,
        actorName: "publisher-log",
        action: "publish",
        result: "success",
        summary: { releaseId: "new" },
      });
      const app = Fastify();
      await registerOperationRoutes(app, { db, now: () => now });
      const found = await app.inject({
        method: "GET",
        url: "/admin/operations?action=publish&from=2026-10-05T00:00:00.000Z&to=2026-10-07T00:00:00.000Z",
        headers: { authorization: `Bearer ${admin.token}` },
      });
      expect(found.statusCode).toBe(200);
      expect(found.json()).toEqual(
        expect.arrayContaining([expect.objectContaining({ action: "publish", actorName: "publisher-log" })]),
      );
      await app.close();
    });
  });
});
