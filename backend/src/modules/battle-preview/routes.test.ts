import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import sharp from "sharp";
import { afterAll, describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { buildApp } from "../../app.js";
import { animationPacks, contentVersions, playerStates } from "../../db/schema.js";
import { createAdmin, registerPlayer } from "../auth/service.js";
import { insertStartingRealm, withDb } from "../../test/db.js";
import { emptyDocument, type BattlePreviewDocument } from "./strike.js";

const root = await mkdtemp(path.join(tmpdir(), "xiuxian-battle-preview-"));
const animationRoot = await mkdtemp(path.join(tmpdir(), "xiuxian-anim-untouched-"));
process.env.BATTLE_PREVIEW_DIR = root;
process.env.ANIMATION_PACK_DIR = animationRoot;

afterAll(async () => {
  await rm(root, { recursive: true, force: true });
  await rm(animationRoot, { recursive: true, force: true });
});

const now = new Date("2026-11-21T00:00:00.000Z");
const clipId = "22222222-2222-4222-8222-222222222222";
const frameId = "33333333-3333-4333-8333-333333333333";

async function png(): Promise<Buffer> {
  return sharp({
    create: { width: 8, height: 8, channels: 4, background: { r: 20, g: 40, b: 80, alpha: 1 } },
  })
    .png()
    .toBuffer();
}

function multipart(files: { name: string; bytes: Buffer; type: string }[]): { payload: Buffer; headers: Record<string, string> } {
  const boundary = "----previewtest";
  const chunks: Buffer[] = [];
  for (const file of files) {
    chunks.push(
      Buffer.from(
        `--${boundary}\r\nContent-Disposition: form-data; name="files"; filename="${file.name}"\r\nContent-Type: ${file.type}\r\n\r\n`,
      ),
    );
    chunks.push(file.bytes);
    chunks.push(Buffer.from("\r\n"));
  }
  chunks.push(Buffer.from(`--${boundary}--\r\n`));
  return {
    payload: Buffer.concat(chunks),
    headers: { "content-type": `multipart/form-data; boundary=${boundary}` },
  };
}

function draftWith(fileName: string): BattlePreviewDocument {
  const doc = emptyDocument();
  doc.characterClipId = clipId;
  doc.opponentClipId = clipId;
  doc.demoNumber = "123";
  doc.clips = [
    {
      id: clipId,
      name: "主角普通攻击",
      frames: [
        { id: frameId, name: fileName, hidden: true, durationMs: 120, action: "attack" },
        { id: "33333333-3333-4333-8333-333333333334", name: "01.png", hidden: false, durationMs: 90, action: "idle" },
      ],
    },
  ];
  return doc;
}

describe("battle preview draft routes", () => {
  it("stores a draft apart from the live animation pack and published content", async () => {
    await withDb(async (db) => {
      await createAdmin(db, { username: "preview_admin", password: "admin-secret" });
      await insertStartingRealm(db);
      const player = await registerPlayer(db, { username: "preview_player", password: "correct-horse", now });
      await db.insert(animationPacks).values({
        id: "player",
        name: "当前动画",
        subject: "player",
        manifest: { marker: "live-pack" },
        updatedAt: new Date("2026-01-01T00:00:00.000Z"),
      });
      await db.insert(contentVersions).values({
        snapshot: { marker: "published" },
        checksum: "keep",
        note: "已发布",
        publishedAt: new Date("2026-01-01T00:00:00.000Z"),
      });
      const app = await buildApp(db, () => now);
      const denied = await app.inject({ method: "GET", url: "/admin/battle-preview/draft" });
      expect(denied.statusCode).toBe(401);

      const playerCall = await app.inject({
        method: "PUT",
        url: "/admin/battle-preview/draft",
        headers: { authorization: `Bearer ${player.token}` },
        payload: emptyDocument(),
      });
      expect(playerCall.statusCode).toBe(403);

      const login = await app.inject({
        method: "POST",
        url: "/admin/auth/login",
        payload: { username: "preview_admin", password: "admin-secret" },
      });
      const headers = { authorization: `Bearer ${login.json().token as string}` };
      const image = await png();
      const form = multipart([
        { name: "b.png", bytes: image, type: "image/png" },
        { name: "a.png", bytes: image, type: "image/png" },
      ]);
      const uploaded = await app.inject({
        method: "POST",
        url: "/admin/battle-preview/clips",
        headers: { ...headers, ...form.headers },
        payload: form.payload,
      });
      expect(uploaded.statusCode).toBe(200);
      const clip = uploaded.json().clip as { id: string; frames: { name: string; durationMs: number; action: null }[] };
      expect(clip.frames.map((frame) => frame.name)).toEqual(["00.png", "01.png"]);
      expect(clip.frames[0]?.durationMs).toBe(83);
      expect(clip.frames[0]?.action).toBeNull();

      const doc = draftWith("00.png");
      doc.clips[0]!.id = clip.id;
      doc.characterClipId = clip.id;
      doc.opponentClipId = clip.id;
      doc.clips[0]!.frames[1]!.name = "01.png";
      const orphan = path.join(root, "44444444-4444-4444-8444-444444444444");
      await mkdir(orphan, { recursive: true });
      await writeFile(path.join(orphan, "00.png"), image);

      const saved = await app.inject({
        method: "PUT",
        url: "/admin/battle-preview/draft",
        headers,
        payload: doc,
      });
      expect(saved.statusCode).toBe(200);
      expect(saved.json().draft.demoNumber).toBe("123");
      expect(saved.json().draft.clips[0].frames[0]).toMatchObject({ hidden: true, durationMs: 120, action: "attack" });
      expect(saved.json().draft.clips[0].frames[1]).toMatchObject({ hidden: false, durationMs: 90, action: "idle" });
      const playback = await app.inject({ method: "GET", url: "/api/v1/battle-preview/playback" });
      expect(playback.statusCode).toBe(200);
      expect(playback.json().actions.idle).toEqual([{ clipId: clip.id, name: "01.png", durationMs: 90 }]);
      expect(playback.json().actions.attack).toEqual([]);
      const frame = await app.inject({ method: "GET", url: `/api/v1/battle-preview/frames/${clip.id}/01.png` });
      expect(frame.statusCode).toBe(200);

      const again = await app.inject({ method: "GET", url: "/admin/battle-preview/draft", headers });
      expect(again.json().draft.clips[0].frames.map((frame: { name: string }) => frame.name)).toEqual(["00.png", "01.png"]);
      const dirs = await readdir(root);
      expect(dirs).toContain(clip.id);
      expect(dirs).not.toContain("44444444-4444-4444-8444-444444444444");
      expect(dirs.some((name) => name.includes("animation"))).toBe(false);

      const picture = await app.inject({
        method: "GET",
        url: `/admin/battle-preview/clips/${clip.id}/frames/00.png`,
        headers,
      });
      expect(picture.statusCode).toBe(200);
      expect(picture.headers["content-type"]).toContain("image/png");

      const broken = structuredClone(saved.json().draft) as BattlePreviewDocument;
      broken.clips[0]!.frames[0]!.durationMs = 10;
      const rejected = await app.inject({
        method: "PUT",
        url: "/admin/battle-preview/draft",
        headers,
        payload: broken,
      });
      expect(rejected.statusCode).toBe(400);
      const kept = await app.inject({ method: "GET", url: "/admin/battle-preview/draft", headers });
      expect(kept.json().draft.clips[0].frames[0].durationMs).toBe(120);

      const text = multipart([{ name: "note.txt", bytes: Buffer.from("nope"), type: "text/plain" }]);
      const badUpload = await app.inject({
        method: "POST",
        url: "/admin/battle-preview/clips",
        headers: { ...headers, ...text.headers },
        payload: text.payload,
      });
      expect(badUpload.statusCode).toBe(400);
      expect(badUpload.json().error.message).toContain("png");

      const fakePng = multipart([{ name: "broken.png", bytes: Buffer.from("not-a-png"), type: "image/png" }]);
      const unreadable = await app.inject({
        method: "POST",
        url: "/admin/battle-preview/clips",
        headers: { ...headers, ...fakePng.headers },
        payload: fakePng.payload,
      });
      expect(unreadable.statusCode).toBe(400);
      expect(unreadable.json().error.message).toContain("读不出来");

      const pack = await db.select().from(animationPacks).where(eq(animationPacks.id, "player"));
      expect(pack[0]?.manifest).toEqual({ marker: "live-pack" });
      const published = await db.select().from(contentVersions);
      expect(published).toHaveLength(1);
      expect(published[0]?.note).toBe("已发布");
      const states = await db.select().from(playerStates);
      expect(states).toHaveLength(1);
      expect(states[0]?.playerId).toBe(player.playerId);

      await app.close();
    });
  });
});
