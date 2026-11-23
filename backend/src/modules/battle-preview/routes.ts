import { randomUUID } from "node:crypto";
import { createReadStream } from "node:fs";
import { access, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import type { FastifyInstance } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { framesFromPngs, framesFromVideo } from "../animation/extract.js";
import { keyedPng } from "../animation/frames.js";
import { assertUploadSize } from "../animation/store.js";
import { parseDocument, parseKeepIds } from "./document.js";
import { assertClipFiles, clipDirectory, frameFile, pruneClipDirectories, readDraft, writeDraft } from "./store.js";
import { clientPlayback, DEFAULT_FRAME_MS, type PreviewClip, type PreviewFrame } from "./strike.js";

type Upload = { filename: string; bytes: Buffer };

export async function registerBattlePreviewRoutes(app: FastifyInstance, deps: { db: Db; now: () => Date }): Promise<void> {
  app.get("/admin/battle-preview/draft", async () => {
    const row = await readDraft(deps.db);
    return { draft: row?.document ?? null, updatedAt: row?.updatedAt ?? null };
  });

  app.get("/battle-preview/playback", async () => {
    const row = await readDraft(deps.db);
    return clientPlayback(row?.document ?? null);
  });

  app.get("/battle-preview/frames/:clipId/:name", async (request, reply) => {
    const { clipId, name } = request.params as { clipId: string; name: string };
    const file = frameFile(clipId, name);
    try {
      await access(file);
    } catch {
      throw new AppError("NOT_FOUND", "这张帧不在");
    }
    reply.type("image/png");
    return reply.send(createReadStream(file));
  });

  app.put("/admin/battle-preview/draft", async (request) => {
    const document = parseDocument(request.body);
    await assertClipFiles(document);
    const saved = await writeDraft(deps.db, document, deps.now());
    await pruneClipDirectories(new Set(saved.document.clips.map((clip) => clip.id)));
    return { draft: saved.document, updatedAt: saved.updatedAt };
  });

  app.post("/admin/battle-preview/prune", async (request) => {
    const saved = await readDraft(deps.db);
    const keep = new Set([...(saved?.document.clips.map((clip) => clip.id) ?? []), ...parseKeepIds(request.body)]);
    await pruneClipDirectories(keep);
    return { ok: true };
  });

  app.post("/admin/battle-preview/clips", async (request) => {
    const pngs: Upload[] = [];
    let video: Upload | null = null;
    for await (const part of request.parts()) {
      if (part.type !== "file") continue;
      const bytes = await part.toBuffer();
      assertUploadSize(bytes.length);
      const filename = part.filename || "frame.png";
      const lower = filename.toLowerCase();
      if (part.mimetype === "image/png" || lower.endsWith(".png")) {
        pngs.push({ filename, bytes });
      } else if (part.mimetype.startsWith("video/") || lower.endsWith(".mp4") || lower.endsWith(".webm") || lower.endsWith(".mov")) {
        if (video) throw new AppError("INVALID_INPUT", "一次上传一段视频");
        video = { filename, bytes };
      } else {
        throw new AppError("INVALID_INPUT", "只接收 png，或一段 mp4 / webm / mov");
      }
    }
    if (video && pngs.length > 0) throw new AppError("INVALID_INPUT", "视频和图片分开上传");
    if (!video && pngs.length === 0) throw new AppError("INVALID_INPUT", "没有收到文件");
    const clipId = randomUUID();
    const dir = clipDirectory(clipId);
    try {
      const names = video ? await writeVideo(dir, video) : await framesFromPngs(pngs, dir);
      await keyFrames(dir, names);
      const clip: PreviewClip = {
        id: clipId,
        name: clipTitle(video, pngs),
        frames: names.map((name) => frameRecord(name)),
      };
      return { clip };
    } catch (error) {
      await rm(dir, { recursive: true, force: true });
      if (error instanceof AppError) throw error;
      const message = error instanceof Error ? error.message : "";
      if (message.includes("unsupported image") || message.includes("Input buffer")) {
        throw new AppError("INVALID_INPUT", "这张图读不出来，请换一张 png");
      }
      throw error;
    }
  });

  app.delete("/admin/battle-preview/clips/:id", async (request) => {
    const { id } = request.params as { id: string };
    const saved = await readDraft(deps.db);
    if (saved?.document.clips.some((clip) => clip.id === id)) {
      throw new AppError("INVALID_INPUT", "这份素材还在已保存的草稿里。从列表去掉并保存草稿后才会删掉。");
    }
    await rm(clipDirectory(id), { recursive: true, force: true });
    return { ok: true };
  });

  app.get("/admin/battle-preview/clips/:clipId/frames/:name", async (request, reply) => {
    const { clipId, name } = request.params as { clipId: string; name: string };
    const file = frameFile(clipId, name);
    try {
      await access(file);
    } catch {
      throw new AppError("NOT_FOUND", "这张帧不在");
    }
    reply.type("image/png");
    return reply.send(createReadStream(file));
  });
}

function frameRecord(name: string): PreviewFrame {
  return {
    id: randomUUID(),
    name,
    hidden: false,
    durationMs: DEFAULT_FRAME_MS,
    action: null,
  };
}

function clipTitle(video: Upload | null, pngs: Upload[]): string {
  const raw = video?.filename ?? (pngs.length === 1 ? pngs[0]?.filename : `${pngs.length} 张图`);
  const base = path.basename(raw ?? "素材", path.extname(raw ?? ""));
  const cleaned = base.replace(/[^\p{L}\p{N}_ -]+/gu, "").trim();
  return (cleaned || "素材").slice(0, 40);
}

async function writeVideo(dir: string, video: Upload): Promise<string[]> {
  await mkdir(dir, { recursive: true });
  const input = path.join(dir, `source${path.extname(video.filename) || ".mp4"}`);
  await writeFile(input, video.bytes);
  try {
    return await framesFromVideo(input, dir);
  } finally {
    await rm(input, { force: true });
  }
}

async function keyFrames(dir: string, names: string[]): Promise<void> {
  for (const name of names) {
    const file = path.join(dir, name);
    const keyed = await keyedPng(await readFile(file));
    await writeFile(file, keyed);
  }
}
