import { AppError } from "../../shared/errors.js";
import {
  ACTION_IDS,
  MAX_FRAME_MS,
  MIN_FRAME_MS,
  type ActionId,
  type BattlePreviewDocument,
  type HitMode,
  type PreviewClip,
  type PreviewFrame,
  type Side,
} from "./strike.js";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FRAME_NAME = /^\d{2}\.png$/;

export function parseDocument(input: unknown): BattlePreviewDocument {
  const body = asRecord(input);
  if (body.schemaVersion !== 1) {
    throw new AppError("INVALID_INPUT", "这份草稿版本不对，没有写入");
  }
  const clips = parseClips(body.clips);
  const clipIds = new Set(clips.map((clip) => clip.id));
  const characterClipId = parseClipRef(body.characterClipId, clipIds, "当前角色");
  const opponentClipId = parseClipRef(body.opponentClipId, clipIds, "演示对手");
  return {
    schemaVersion: 1,
    characterClipId,
    opponentClipId,
    characterSide: parseSide(body.characterSide, "当前角色站位"),
    attackerSide: parseSide(body.attackerSide, "谁出招"),
    demoNumber: parseDemoNumber(body.demoNumber),
    attackLeadMs: parseOptionalMs(body.attackLeadMs, "出招开始"),
    projectileFrame: parseFrameNumber(body.projectileFrame, "飞出物对齐"),
    projectileShiftMs: parseShift(body.projectileShiftMs, "飞出物早晚"),
    hitMode: parseHitMode(body.hitMode),
    hitFrame: parseFrameNumber(body.hitFrame, "命中对齐"),
    hitShiftMs: parseShift(body.hitShiftMs, "命中早晚"),
    impactOffsetMs: parseShift(body.impactOffsetMs, "爆开早晚"),
    numberOffsetMs: parseShift(body.numberOffsetMs, "演示数字早晚"),
    defenderHitOffsetMs: parseShift(body.defenderHitOffsetMs, "受击早晚"),
    clips,
  };
}

export function parseKeepIds(input: unknown): string[] {
  const body = asRecord(input);
  if (!Array.isArray(body.keep)) return [];
  return body.keep.filter((id): id is string => typeof id === "string" && UUID.test(id));
}

function parseClips(input: unknown): PreviewClip[] {
  if (!Array.isArray(input)) throw new AppError("INVALID_INPUT", "素材列表不正确");
  if (input.length > 12) throw new AppError("INVALID_INPUT", "素材最多 12 套");
  const clips = input.map(parseClip);
  const ids = new Set<string>();
  for (const clip of clips) {
    if (ids.has(clip.id)) throw new AppError("INVALID_INPUT", "素材编号重复");
    ids.add(clip.id);
  }
  return clips;
}

function parseClip(input: unknown): PreviewClip {
  const body = asRecord(input);
  if (typeof body.id !== "string" || !UUID.test(body.id)) {
    throw new AppError("INVALID_INPUT", "素材编号不正确");
  }
  if (typeof body.name !== "string" || body.name.trim().length === 0 || body.name.length > 40) {
    throw new AppError("INVALID_INPUT", "素材名称要在 1 到 40 个字");
  }
  if (!Array.isArray(body.frames)) throw new AppError("INVALID_INPUT", "帧列表不正确");
  if (body.frames.length > 96) throw new AppError("INVALID_INPUT", "一套素材最多 96 帧");
  const frames = body.frames.map(parseFrame);
  const frameIds = new Set<string>();
  const names = new Set<string>();
  for (const frame of frames) {
    if (frameIds.has(frame.id)) throw new AppError("INVALID_INPUT", "帧编号重复");
    if (names.has(frame.name)) throw new AppError("INVALID_INPUT", "同一套素材里的帧文件名重复");
    frameIds.add(frame.id);
    names.add(frame.name);
  }
  return { id: body.id, name: body.name.trim(), frames };
}

function parseFrame(input: unknown): PreviewFrame {
  const body = asRecord(input);
  if (typeof body.id !== "string" || !UUID.test(body.id)) {
    throw new AppError("INVALID_INPUT", "帧编号不正确");
  }
  if (typeof body.name !== "string" || !FRAME_NAME.test(body.name)) {
    throw new AppError("INVALID_INPUT", "帧文件名不正确");
  }
  if (typeof body.hidden !== "boolean") throw new AppError("INVALID_INPUT", "隐藏标记不正确");
  if (typeof body.durationMs !== "number" || !Number.isInteger(body.durationMs) || body.durationMs < MIN_FRAME_MS || body.durationMs > MAX_FRAME_MS) {
    throw new AppError("INVALID_INPUT", `每帧时长要在 ${MIN_FRAME_MS} 到 ${MAX_FRAME_MS} 毫秒之间`);
  }
  return {
    id: body.id,
    name: body.name,
    hidden: body.hidden,
    durationMs: body.durationMs,
    action: parseAction(body.action),
  };
}

function parseAction(input: unknown): ActionId | null {
  if (input == null) return null;
  if (typeof input === "string" && (ACTION_IDS as readonly string[]).includes(input)) return input as ActionId;
  throw new AppError("INVALID_INPUT", "动作只能是待机、出招、受击、飞出物或打中爆开");
}

function parseClipRef(input: unknown, ids: Set<string>, label: string): string | null {
  if (input == null) return null;
  if (typeof input !== "string" || !UUID.test(input) || !ids.has(input)) {
    throw new AppError("INVALID_INPUT", `${label}指向的素材不在这份草稿里`);
  }
  return input;
}

function parseSide(input: unknown, label: string): Side {
  if (input === "left" || input === "right") return input;
  throw new AppError("INVALID_INPUT", `${label}只能是左或右`);
}

function parseHitMode(input: unknown): HitMode {
  if (input === "attackFrame" || input === "projectileArrive") return input;
  throw new AppError("INVALID_INPUT", "命中对齐方式不正确");
}

function parseDemoNumber(input: unknown): string {
  if (typeof input !== "string") throw new AppError("INVALID_INPUT", "演示数字要写成文字");
  const text = input.trim();
  if (text.length < 1 || text.length > 8) throw new AppError("INVALID_INPUT", "演示数字用 1 到 8 个字");
  if (/[\r\n]/.test(text)) throw new AppError("INVALID_INPUT", "演示数字不能换行");
  return text;
}

function parseFrameNumber(input: unknown, label: string): number {
  if (typeof input !== "number" || !Number.isInteger(input) || input < 1 || input > 96) {
    throw new AppError("INVALID_INPUT", `${label}要是第几帧，从 1 开始`);
  }
  return input;
}

function parseOptionalMs(input: unknown, label: string): number | null {
  if (input == null) return null;
  return parseShift(input, label);
}

function parseShift(input: unknown, label: string): number {
  if (typeof input !== "number" || !Number.isInteger(input) || input < -60000 || input > 60000) {
    throw new AppError("INVALID_INPUT", `${label}要在 -60000 到 60000 毫秒之间`);
  }
  return input;
}

function asRecord(input: unknown): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new AppError("INVALID_INPUT", "草稿内容不正确");
  }
  return input as Record<string, unknown>;
}
