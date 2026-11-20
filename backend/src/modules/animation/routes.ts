import { randomUUID } from "node:crypto";
import { createReadStream } from "node:fs";
import { access, mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import type { FastifyInstance } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { framesFromPngs, framesFromVideo } from "./extract.js";
import { defaultManifest, missingSlots, SLOT_LABEL, SLOT_NAMES, type SlotName } from "./playback.js";
import {
  animationRoot,
  applyParams,
  assertFrameName,
  assertUploadSize,
  cellDir,
  isSlotName,
  loadReference,
  materializeSlot,
  packFile,
  readParams,
  readPlayerPack,
  readTimeline,
  saveManifest,
  saveTimeline,
  sourceDir,
  writeNumbered,
  type SlotAssignment,
} from "./store.js";

type SlotBody = {
  source?: unknown;
  names?: unknown;
  frameDurationMs?: unknown;
  lungePx?: unknown;
  loop?: unknown;
};

type PackBody = {
  extractId?: unknown;
  facing?: unknown;
  displayHeight?: unknown;
  hitDelaySeconds?: unknown;
  slots?: Partial<Record<SlotName, SlotBody>>;
};

export async function registerAnimationRoutes(app: FastifyInstance, deps: { db: Db; now: () => Date }): Promise<void> {
  app.get("/admin/animation-packs/player", async () => {
    const pack = await readPlayerPack(deps.db);
    return pack ?? { manifest: null, updatedAt: null };
  });

  app.post("/admin/animation-packs/player/extract", async (request) => {
    const pngs: { filename: string; bytes: Buffer }[] = [];
    let video: { filename: string; bytes: Buffer } | null = null;
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
    const extractId = randomUUID();
    const dir = path.join(animationRoot(), "_extract", extractId);
    const frames = video ? await writeVideo(dir, video) : await framesFromPngs(pngs, dir);
    return { extractId, frames };
  });

  app.post("/admin/animation-packs/player/compose", async (request) => {
    const body = request.body as PackBody;
    const previewId = randomUUID();
    const built = await buildSlots(body);
    const slots: Partial<Record<SlotName, string[]>> = {};
    for (const item of built) {
      if (item.cells.length === 0) continue;
      slots[item.slot] = await writeNumbered(path.join(animationRoot(), "_preview", previewId, item.slot), item.cells);
    }
    return { previewId, slots };
  });

  app.post("/admin/animation-packs/player", async (request) => {
    const body = request.body as PackBody;
    const current = await readPlayerPack(deps.db);
    const base = current?.manifest ?? defaultManifest();
    const params = readParams(base, body);
    const built = await buildSlots(body, params.displayHeight);
    const manifest = applyParams(base, params);
    for (const item of built) {
      manifest.slots[item.slot].frames = item.cells.map((_, index) => `${String(index).padStart(2, "0")}.png`);
    }
    const missing = missingSlots(manifest);
    if (missing.length > 0) {
      throw new AppError("INVALID_INPUT", `还缺这些动作：${missing.map((slot) => SLOT_LABEL[slot]).join("、")}`, { missing });
    }
    const root = animationRoot();
    for (const item of built) {
      if (item.cells.length === 0) {
        await rm(cellDir(root, item.slot), { recursive: true, force: true });
        await rm(sourceDir(root, item.slot), { recursive: true, force: true });
        continue;
      }
      await writeNumbered(cellDir(root, item.slot), item.cells);
      await writeNumbered(sourceDir(root, item.slot), item.sources);
    }
    await saveManifest(deps.db, manifest, deps.now());
    return { manifest, updatedAt: deps.now().toISOString() };
  });

  app.put("/admin/animation-packs/player/timeline", async (request) => {
    const body = request.body as { frames?: unknown; frameDurationMs?: unknown };
    const frames = readTimeline(body.frames);
    const frameDurationMs = body.frameDurationMs === undefined ? undefined : Number(body.frameDurationMs);
    if (frameDurationMs !== undefined && (!Number.isFinite(frameDurationMs) || frameDurationMs < 30 || frameDurationMs > 400)) {
      throw new AppError("INVALID_INPUT", "每帧时长要在 30 到 400 毫秒之间");
    }
    const manifest = await saveTimeline(deps.db, frames, frameDurationMs, deps.now());
    return { manifest, updatedAt: deps.now().toISOString() };
  });

  app.get("/admin/animation-packs/player/files/:slot/:name", async (request, reply) => {
    const { slot, name } = request.params as { slot: string; name: string };
    return sendPng(reply, packFile(animationRoot(), "cell", slot, name));
  });

  app.get("/admin/animation-packs/extract/:id/:name", async (request, reply) => {
    const { id, name } = request.params as { id: string; name: string };
    if (!/^[0-9a-f-]{36}$/i.test(id)) throw new AppError("NOT_FOUND", "没有这次抽帧");
    assertFrameName(name);
    return sendPng(reply, path.join(animationRoot(), "_extract", id, name));
  });

  app.get("/admin/animation-packs/preview/:id/:slot/:name", async (request, reply) => {
    const { id, slot, name } = request.params as { id: string; slot: string; name: string };
    if (!/^[0-9a-f-]{36}$/i.test(id) || !isSlotName(slot)) throw new AppError("NOT_FOUND", "没有这张预览");
    assertFrameName(name);
    return sendPng(reply, path.join(animationRoot(), "_preview", id, slot, name));
  });
}

async function writeVideo(dir: string, video: { filename: string; bytes: Buffer }): Promise<string[]> {
  await mkdir(dir, { recursive: true });
  const input = path.join(dir, `source${path.extname(video.filename) || ".mp4"}`);
  await writeFile(input, video.bytes);
  try {
    return await framesFromVideo(input, dir);
  } finally {
    await rm(input, { force: true });
  }
}

async function buildSlots(body: PackBody, displayHeight?: number): Promise<{ slot: SlotName; sources: Buffer[]; cells: Buffer[] }[]> {
  const root = animationRoot();
  const assignments = readAssignments(body);
  const reference = await loadReference(root, assignments.idle, stringOrUndefined(body.extractId));
  const params = readParams(defaultManifest(), body);
  params.displayHeight = displayHeight ?? params.displayHeight;
  const built: { slot: SlotName; sources: Buffer[]; cells: Buffer[] }[] = [];
  for (const slot of SLOT_NAMES) {
    const made = await materializeSlot(root, slot, assignments[slot], stringOrUndefined(body.extractId), params.displayHeight, reference);
    built.push({ slot, ...made });
  }
  return built;
}

function readAssignments(body: PackBody): Record<SlotName, SlotAssignment> {
  const assignments = {} as Record<SlotName, SlotAssignment>;
  for (const slot of SLOT_NAMES) {
    const raw = body.slots?.[slot];
    const names = Array.isArray(raw?.names) ? raw.names.filter((name): name is string => typeof name === "string") : [];
    assignments[slot] = { source: raw?.source === "pack" ? "pack" : "extract", names };
  }
  return assignments;
}

function stringOrUndefined(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

async function sendPng(reply: { type: (value: string) => void; send: (payload: unknown) => unknown }, file: string) {
  try {
    await access(file);
  } catch {
    throw new AppError("NOT_FOUND", "这张帧不在");
  }
  reply.type("image/png");
  return reply.send(createReadStream(file));
}
