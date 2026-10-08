import Fastify from "fastify";
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { playerStates } from "../../db/schema.js";
import { authPlugin } from "../../plugins/auth.js";
import { createAdmin, loginAdmin, registerPlayer } from "../auth/service.js";
import { withDb } from "../../test/db.js";
import { applyRepair, previewRepair, registerRepair } from "./service.js";
import { registerRepairRoutes } from "./routes.js";

const now = new Date("2026-10-06T11:00:00.000Z");

registerRepair({
  name: "double-cultivation",
  async plan(_db, player) {
    return { cultivation: player.cultivation * 2 };
  },
});

async function cultivationOf(db: Parameters<typeof previewRepair>[0], playerId: string) {
  const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
  return state?.cultivation;
}

describe("repairs", { timeout: 30_000 }, () => {
  it("previews without writing, applies once, and rejects a stale preview", async () => {
    await withDb(async (db) => {
      const player = await registerPlayer(db, { username: "repair_me", password: "correct-horse", now });
      await db.update(playerStates).set({ cultivation: 10 }).where(eq(playerStates.playerId, player.playerId));
      const preview = await previewRepair(db, "double-cultivation");
      expect(await cultivationOf(db, player.playerId)).toBe(10);
      expect(preview.entries).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ playerId: player.playerId, before: 10, after: 20, status: "pending" }),
        ]),
      );
      const applied = await applyRepair(db, { id: "unused", name: "fixer" }, preview.previewId, now);
      expect(applied.applied).toBeGreaterThan(0);
      expect(await cultivationOf(db, player.playerId)).toBe(20);
      await applyRepair(db, { id: "unused", name: "fixer" }, preview.previewId, now);
      expect(await cultivationOf(db, player.playerId)).toBe(20);
    });
  });

  it("refuses to apply after cultivation changes", async () => {
    await withDb(async (db) => {
      const player = await registerPlayer(db, { username: "repair_stale", password: "correct-horse", now });
      await db.update(playerStates).set({ cultivation: 10 }).where(eq(playerStates.playerId, player.playerId));
      const preview = await previewRepair(db, "double-cultivation");
      await db.update(playerStates).set({ cultivation: 11 }).where(eq(playerStates.playerId, player.playerId));
      await expect(applyRepair(db, { id: "unused", name: "fixer" }, preview.previewId, now)).rejects.toThrow(/stale/);
      expect(await cultivationOf(db, player.playerId)).toBe(11);
    });
  });

  it("rejects an unknown repair and a player token", async () => {
    await withDb(async (db) => {
      await expect(previewRepair(db, "missing-repair")).rejects.toThrow(/unknown repair/);
      await createAdmin(db, { username: "repair_admin", password: "admin-secret" });
      const admin = await loginAdmin(db, { username: "repair_admin", password: "admin-secret", now });
      const player = await registerPlayer(db, { username: "repair_player", password: "correct-horse", now });
      if (!admin.ok) {
        throw new Error("admin login failed");
      }
      const app = Fastify();
      await authPlugin(db, () => now)(app);
      await registerRepairRoutes(app, { db, now: () => now });
      const denied = await app.inject({
        method: "POST",
        url: "/admin/repairs/preview",
        headers: { authorization: `Bearer ${player.token}` },
        payload: { name: "double-cultivation" },
      });
      expect(denied.statusCode).toBe(403);
      await app.close();
    });
  });
});
