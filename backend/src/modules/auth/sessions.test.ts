import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { sessions } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { registerPlayer } from "./service.js";
import { purgeOldSessions } from "./sessions.js";

describe("purgeOldSessions", () => {
  it("deletes sessions that expired or were revoked more than seven days ago", async () => {
    await withDb(async (db) => {
      const now = new Date("2026-10-08T00:00:00.000Z");
      const player = await registerPlayer(db, { username: "old_player", password: "correct-horse", now });
      const old = new Date(now.getTime() - 8 * 24 * 60 * 60 * 1000);
      await db.update(sessions).set({ expiresAt: old, revokedAt: old }).where(eq(sessions.actorId, player.playerId));
      await purgeOldSessions(db, now);
      const left = await db.select().from(sessions);
      expect(left).toHaveLength(0);
    });
  });
});
