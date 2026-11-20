import { describe, expect, it } from "vitest";
import { buildApp } from "../../app.js";
import { animationPacks } from "../../db/schema.js";
import { createAdmin } from "../auth/service.js";
import { defaultManifest } from "./playback.js";
import { withDb } from "../../test/db.js";

describe("animation timeline", () => {
  it("saves frame order and hidden flags without removing the frame", async () => {
    await withDb(async (db) => {
      await createAdmin(db, { username: "timeline_admin", password: "admin-secret" });
      const manifest = defaultManifest();
      manifest.slots.idle.frames = ["00.png", "01.png"];
      await db.insert(animationPacks).values({
        id: "player",
        name: "玩家",
        subject: "player",
        manifest,
        updatedAt: new Date("2026-11-18T00:00:00.000Z"),
      });
      const app = await buildApp(db);
      const login = await app.inject({
        method: "POST",
        url: "/admin/auth/login",
        payload: { username: "timeline_admin", password: "admin-secret" },
      });
      const headers = { authorization: `Bearer ${login.json().token as string}` };
      const saved = await app.inject({
        method: "PUT",
        url: "/admin/animation-packs/player/timeline",
        headers,
        payload: {
          frameDurationMs: 100,
          frames: [
            { id: "b", slot: "idle", name: "01.png", hidden: false },
            { id: "a", slot: "idle", name: "00.png", hidden: true },
          ],
        },
      });
      expect(saved.statusCode).toBe(200);
      expect(saved.json().manifest.timeline).toEqual([
        { id: "b", slot: "idle", name: "01.png", hidden: false },
        { id: "a", slot: "idle", name: "00.png", hidden: true },
      ]);
      expect(saved.json().manifest.slots.idle.frames).toEqual(["00.png", "01.png"]);
      await app.close();
    });
  });
});
