import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { eq } from "drizzle-orm";
import { animationPacks } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { composeCells } from "./frames.js";
import {
  defaultManifest,
  missingSlots,
  SLOT_LABEL,
  SLOT_NAMES,
  type AnimationManifest,
  type SlotName,
  type TimelineFrame,
} from "./playback.js";

export const PLAYER_PACK_ID = "player";
const MAX_BYTES = 50 * 1024 * 1024;

export function animationRoot(): string {
  return process.env.ANIMATION_PACK_DIR ?? path.join(process.cwd(), "var", "animation-packs");
}

export function assertFrameName(name: string): string {
  if (!/^\d{2}\.png$/.test(name)) {
    throw new AppError("INVALID_INPUT", "帧文件名不正确");
  }
  return name;
}

export function isSlotName(value: string): value is SlotName {
  return (SLOT_NAMES as readonly string[]).includes(value);
}

export type SlotAssignment = { source: "extract" | "pack"; names: string[] };

export type PackParams = {
  facing: 1 | -1;
  displayHeight: number;
  hitDelaySeconds: number;
  slots: Record<SlotName, { frameDurationMs: number; lungePx: number; loop: boolean }>;
};

export function readParams(manifest: AnimationManifest, input: unknown): PackParams {
  const body = (input ?? {}) as {
    facing?: unknown;
    displayHeight?: unknown;
    hitDelaySeconds?: unknown;
    slots?: Partial<Record<SlotName, { frameDurationMs?: unknown; lungePx?: unknown; loop?: unknown }>>;
  };
  const facing = body.facing === -1 ? -1 : body.facing === 1 ? 1 : manifest.facing;
  if (body.facing !== undefined && body.facing !== 1 && body.facing !== -1) {
    throw new AppError("INVALID_INPUT", "朝向只能是朝右或朝左");
  }
  const displayHeight = numberIn(body.displayHeight, manifest.displayHeight, 120, 270, "角色高度");
  const hitDelaySeconds = numberIn(body.hitDelaySeconds, manifest.hitDelaySeconds, 0.4, 3, "技能命中时刻");
  const slots = {} as PackParams["slots"];
  for (const name of SLOT_NAMES) {
    const current = manifest.slots[name];
    const patch = body.slots?.[name] ?? {};
    const loop = name === "down" || name === "victory" ? false : patch.loop === undefined ? current.loop : patch.loop === true;
    slots[name] = {
      frameDurationMs: numberIn(patch.frameDurationMs, current.frameDurationMs, 30, 400, `${name} 每帧时长`),
      lungePx: numberIn(patch.lungePx, current.lungePx, 0, 80, `${name} 冲刺距离`),
      loop,
    };
  }
  return { facing, displayHeight, hitDelaySeconds, slots };
}

function numberIn(value: unknown, fallback: number, min: number, max: number, label: string): number {
  if (value === undefined) return fallback;
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed) || parsed < min || parsed > max) {
    throw new AppError("INVALID_INPUT", `${label}要在 ${min} 到 ${max} 之间`);
  }
  return parsed;
}

export function applyParams(manifest: AnimationManifest, params: PackParams): AnimationManifest {
  const next = structuredClone(manifest);
  next.facing = params.facing;
  next.displayHeight = params.displayHeight;
  next.hitDelaySeconds = params.hitDelaySeconds;
  for (const name of SLOT_NAMES) {
    const slot = next.slots[name];
    const patch = params.slots[name];
    slot.frameDurationMs = patch.frameDurationMs;
    slot.lungePx = patch.lungePx;
    slot.loop = patch.loop;
    slot.holdLast = name === "down" || name === "victory";
  }
  return next;
}

export async function readPlayerPack(db: Db): Promise<{ manifest: AnimationManifest; updatedAt: string } | null> {
  const [row] = await db.select().from(animationPacks).where(eq(animationPacks.id, PLAYER_PACK_ID)).limit(1);
  if (!row) return null;
  return { manifest: row.manifest as AnimationManifest, updatedAt: row.updatedAt.toISOString() };
}

export function assertUploadSize(bytes: number): void {
  if (bytes > MAX_BYTES) {
    throw new AppError("INVALID_INPUT", "单个文件要在 50MB 以内");
  }
}

export async function materializeSlot(
  root: string,
  slot: SlotName,
  assignment: SlotAssignment,
  extractId: string | undefined,
  displayHeight: number,
  reference: Buffer,
): Promise<{ sources: Buffer[]; cells: Buffer[] }> {
  if (assignment.names.length === 0) return { sources: [], cells: [] };
  const from = assignment.source === "extract" ? extractDir(root, extractId) : sourceDir(root, slot);
  const sources: Buffer[] = [];
  for (const name of assignment.names) {
    assertFrameName(name);
    sources.push(await readFile(path.join(from, name)));
  }
  const base = defaultManifest();
  const cells = await composeCells(sources, {
    cellW: base.cell.w,
    cellH: base.cell.h,
    footX: base.foot.x,
    footY: base.foot.y,
    bodyHeight: displayHeight,
    reference,
  });
  return { sources, cells };
}

export async function loadReference(
  root: string,
  assignment: SlotAssignment,
  extractId: string | undefined,
): Promise<Buffer> {
  if (assignment.names.length === 0) {
    throw new AppError("INVALID_INPUT", "要先指定待机帧，才能把其他动作对齐到同一只脚");
  }
  const from = assignment.source === "extract" ? extractDir(root, extractId) : sourceDir(root, "idle");
  assertFrameName(assignment.names[0] ?? "");
  return readFile(path.join(from, assignment.names[0] ?? ""));
}

function extractDir(root: string, extractId: string | undefined): string {
  if (!extractId || !/^[0-9a-f-]{36}$/i.test(extractId)) {
    throw new AppError("INVALID_INPUT", "抽帧结果已经失效，请重新上传");
  }
  return path.join(root, "_extract", extractId);
}

export function sourceDir(root: string, slot: SlotName): string {
  return path.join(root, PLAYER_PACK_ID, "_source", slot);
}

export function cellDir(root: string, slot: SlotName): string {
  return path.join(root, PLAYER_PACK_ID, slot);
}

export async function writeNumbered(dir: string, frames: Buffer[]): Promise<string[]> {
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });
  const names: string[] = [];
  for (let index = 0; index < frames.length; index += 1) {
    const name = `${String(index).padStart(2, "0")}.png`;
    await writeFile(path.join(dir, name), frames[index] ?? Buffer.alloc(0));
    names.push(name);
  }
  return names;
}

export function packFile(root: string, kind: "cell" | "source", slot: string, name: string): string {
  if (!isSlotName(slot)) throw new AppError("NOT_FOUND", "没有这个动作");
  assertFrameName(name);
  return path.join(kind === "cell" ? cellDir(root, slot) : sourceDir(root, slot), name);
}

export function readTimeline(input: unknown): TimelineFrame[] {
  if (!Array.isArray(input) || input.length === 0) {
    throw new AppError("INVALID_INPUT", "时间轴上还没有帧");
  }
  return input.map((item, index) => {
    const row = item as { id?: unknown; slot?: unknown; name?: unknown; hidden?: unknown };
    if (typeof row.slot !== "string" || !isSlotName(row.slot)) {
      throw new AppError("INVALID_INPUT", "时间轴里有无法识别的帧");
    }
    const name = assertFrameName(typeof row.name === "string" ? row.name : "");
    const id = typeof row.id === "string" && row.id.trim() ? row.id.trim() : `${row.slot}-${name}-${index}`;
    return { id, slot: row.slot, name, hidden: row.hidden === true };
  });
}

export async function saveTimeline(db: Db, frames: TimelineFrame[], frameDurationMs: number | undefined, now: Date) {
  const current = await readPlayerPack(db);
  if (!current) throw new AppError("NOT_FOUND", "还没有动画，先放进帧再调整顺序");
  const manifest = structuredClone(current.manifest);
  manifest.timeline = frames;
  if (frameDurationMs !== undefined) {
    for (const slot of SLOT_NAMES) manifest.slots[slot].frameDurationMs = frameDurationMs;
  }
  await db
    .insert(animationPacks)
    .values({ id: PLAYER_PACK_ID, name: "玩家", subject: "player", manifest, updatedAt: now })
    .onConflictDoUpdate({
      target: animationPacks.id,
      set: { manifest, updatedAt: now },
    });
  return manifest;
}

export async function saveManifest(db: Db, manifest: AnimationManifest, now: Date): Promise<void> {
  const missing = missingSlots(manifest);
  if (missing.length > 0) {
    throw new AppError("INVALID_INPUT", `还缺这些动作：${missing.map((slot) => SLOT_LABEL[slot]).join("、")}`, { missing });
  }
  await db
    .insert(animationPacks)
    .values({ id: PLAYER_PACK_ID, name: "玩家", subject: "player", manifest, updatedAt: now })
    .onConflictDoUpdate({
      target: animationPacks.id,
      set: { manifest, updatedAt: now },
    });
}
