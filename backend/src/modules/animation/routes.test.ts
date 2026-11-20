import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, describe, expect, it } from "vitest";
import { buildApp } from "../../app.js";
import { createAdmin } from "../auth/service.js";
import { withDb } from "../../test/db.js";

const root = await mkdtemp(path.join(tmpdir(), "xiuxian-anim-"));
process.env.ANIMATION_PACK_DIR = root;

afterAll(async () => {
  await rm(root, { recursive: true, force: true });
});

async function sprite(): Promise<Buffer> {
  const raw = Buffer.alloc(32 * 48 * 4);
  for (let y = 16; y < 48; y += 1) {
    for (let x = 10; x < 22; x += 1) {
      const offset = (y * 32 + x) * 4;
      raw[offset] = 30;
      raw[offset + 1] = 30;
      raw[offset + 2] = 30;
      raw[offset + 3] = 255;
    }
  }
  return sharp(raw, { raw: { width: 32, height: 48, channels: 4 } }).png().toBuffer();
}

function multipart(files: Buffer[]): { payload: Buffer; headers: Record<string, string> } {
  const boundary = "----animtest";
  const chunks: Buffer[] = [];
  files.forEach((file, index) => {
    chunks.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="files"; filename="${index}.png"\r\nContent-Type: image/png\r\n\r\n`,
      ),
    );
    chunks.push(file);
    chunks.push(Buffer.from("\r\n"));
  });
  chunks.push(Buffer.from(`--${boundary}--\r\n`));
  return {
    payload: Buffer.concat(chunks),
    headers: { "content-type": `multipart/form-data; boundary=${boundary}` },
  };
}

describe("animation pack routes", () => {
  it("saves the current player pack and refuses a pack that is missing a body slot", async () => {
    await withDb(async (db) => {
      await createAdmin(db, { username: "anim_admin", password: "admin-secret" });
      const app = await buildApp(db);
      const denied = await app.inject({ method: "GET", url: "/admin/animation-packs/player" });
      expect(denied.statusCode).toBe(401);

      const login = await app.inject({
        method: "POST",
        url: "/admin/auth/login",
        payload: { username: "anim_admin", password: "admin-secret" },
      });
      const headers = { authorization: `Bearer ${login.json().token as string}` };
      const empty = await app.inject({ method: "GET", url: "/admin/animation-packs/player", headers });
      expect(empty.json()).toEqual({ manifest: null, updatedAt: null });

      const png = await sprite();
      const form = multipart([png]);
      const uploaded = await app.inject({
        method: "POST",
        url: "/admin/animation-packs/player/extract",
        headers: { ...headers, ...form.headers },
        payload: form.payload,
      });
      expect(uploaded.statusCode).toBe(200);
      const extractId = uploaded.json().extractId as string;

      const slot = (names: string[]) => ({ source: "extract", names, frameDurationMs: 80, lungePx: 0, loop: false });
      const incomplete = await app.inject({
        method: "POST",
        url: "/admin/animation-packs/player",
        headers,
        payload: { extractId, displayHeight: 200, slots: { idle: { ...slot(["00.png"]), loop: true } } },
      });
      expect(incomplete.statusCode).toBe(400);
      expect(incomplete.json().error.message).toContain("普攻");

      const slots = {
        idle: { ...slot(["00.png"]), loop: true },
        attack: { ...slot(["00.png"]), lungePx: 24 },
        cast: slot(["00.png"]),
        skill: { ...slot(["00.png"]), lungePx: 18 },
        hit: slot(["00.png"]),
        down: slot(["00.png"]),
        victory: slot(["00.png"]),
      };
      const saved = await app.inject({
        method: "POST",
        url: "/admin/animation-packs/player",
        headers,
        payload: { extractId, displayHeight: 200, hitDelaySeconds: 1.21, facing: 1, slots },
      });
      expect(saved.statusCode).toBe(200);
      expect(saved.json().manifest.slots.attack.lungePx).toBe(24);
      expect(saved.json().manifest.slots.idle.frames).toEqual(["00.png"]);

      const file = await app.inject({ method: "GET", url: "/admin/animation-packs/player/files/idle/00.png", headers });
      expect(file.statusCode).toBe(200);
      expect(file.headers["content-type"]).toContain("image/png");
      await app.close();
    });
  });
});
