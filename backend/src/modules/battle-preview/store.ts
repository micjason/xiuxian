import { access, mkdir, readdir, rm } from "node:fs/promises";
import path from "node:path";
import { eq } from "drizzle-orm";
import { battlePreviewDrafts } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import type { BattlePreviewDocument } from "./strike.js";

export const DRAFT_ID = "current";
const CLIP_DIR = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function battlePreviewRoot(): string {
  const configured = process.env.BATTLE_PREVIEW_DIR?.trim();
  if (configured) return configured;
  return path.join(process.cwd(), "var", "battle-preview-drafts");
}

export function clipDirectory(clipId: string): string {
  if (!CLIP_DIR.test(clipId)) throw new AppError("INVALID_INPUT", "素材编号不正确");
  return path.join(battlePreviewRoot(), clipId);
}

export function frameFile(clipId: string, name: string): string {
  if (!/^\d{2}\.png$/.test(name)) throw new AppError("INVALID_INPUT", "帧文件名不正确");
  return path.join(clipDirectory(clipId), name);
}

export async function readDraft(db: Db): Promise<{ document: BattlePreviewDocument; updatedAt: string } | null> {
  const [row] = await db.select().from(battlePreviewDrafts).where(eq(battlePreviewDrafts.id, DRAFT_ID)).limit(1);
  if (!row) return null;
  return {
    document: row.document as BattlePreviewDocument,
    updatedAt: row.updatedAt.toISOString(),
  };
}

export async function writeDraft(
  db: Db,
  document: BattlePreviewDocument,
  now: Date,
): Promise<{ document: BattlePreviewDocument; updatedAt: string }> {
  await db
    .insert(battlePreviewDrafts)
    .values({ id: DRAFT_ID, document, updatedAt: now })
    .onConflictDoUpdate({
      target: battlePreviewDrafts.id,
      set: { document, updatedAt: now },
    });
  return { document, updatedAt: now.toISOString() };
}

export async function assertClipFiles(document: BattlePreviewDocument): Promise<void> {
  for (const clip of document.clips) {
    for (const frame of clip.frames) {
      try {
        await access(frameFile(clip.id, frame.name));
      } catch {
        throw new AppError("INVALID_INPUT", `素材「${clip.name}」缺了 ${frame.name}，草稿没有写入`);
      }
    }
  }
}

/** 只删草稿目录里不再被保留的素材夹，不动动画包目录。 */
export async function pruneClipDirectories(keep: ReadonlySet<string>): Promise<void> {
  const root = battlePreviewRoot();
  await mkdir(root, { recursive: true });
  const names = await readdir(root);
  await Promise.all(
    names.map(async (name) => {
      if (keep.has(name) || !CLIP_DIR.test(name)) return;
      await rm(path.join(root, name), { recursive: true, force: true });
    }),
  );
}
