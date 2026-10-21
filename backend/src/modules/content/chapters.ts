/**
 * 章节（第三批）后台读写：content_chapters。
 * 章末关 = chief_stage_slug（手动指定）或本章 sortOrder 最大的一关（自动）；背景 bg_key、章节首领特效 boss_fx 只能选 art-keys.ts 里的值。
 */
import { randomBytes } from "node:crypto";
import { eq } from "drizzle-orm";
import { contentChapters, contentStages } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { CHAPTER_BATTLE_BG_KEY_SET, CHAPTER_BG_KEY_SET, CHAPTER_BOSS_FX_SET } from "./art-keys.js";
import { chiefStageOf } from "./stage-order.js";

const SLUG = /^[a-z][a-z0-9_]{1,47}$/;

export type ChapterInput = {
  slug?: string;
  displayName?: string;
  sortOrder?: number;
  bgKey?: string;
  bossFx?: string;
  /** 第四批：首领战斗页背景；null / 空 = 跟随 bgKey */
  battleBgKey?: string | null;
  /** null / 空 = 自动（本章 sortOrder 最大的一关） */
  chiefStageSlug?: string | null;
  enabled?: boolean;
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export async function listChapters(db: Db) {
  const [chapters, stages] = await Promise.all([db.select().from(contentChapters), db.select().from(contentStages)]);
  return chapters
    .sort((left, right) => left.sortOrder - right.sortOrder || left.slug.localeCompare(right.slug))
    .map((row) => {
      const chief = chiefStageOf({ slug: row.slug, chiefStageSlugSetting: row.chiefStageSlug ?? null }, stages);
      const own = stages
        .filter((stage) => stage.chapterSlug === row.slug)
        .sort((left, right) => left.sortOrder - right.sortOrder || left.requiredRealmOrder - right.requiredRealmOrder || left.slug.localeCompare(right.slug));
      return {
        id: row.slug,
        displayName: row.displayName,
        sortOrder: row.sortOrder,
        bgKey: row.bgKey,
        bossFx: row.bossFx,
        battleBgKey: row.battleBgKey ?? null,
        /** 后台手动指定的章末关（null = 自动） */
        chiefStageSlug: row.chiefStageSlug ?? null,
        /** 实际的章末关 */
        effectiveChiefStageSlug: chief,
        enabled: row.enabled,
        stages: own.map((stage) => ({ id: stage.slug, displayName: stage.displayName, sortOrder: stage.sortOrder, realmCode: stage.requiredRealmOrder, chief: stage.slug === chief })),
        updatedAt: row.updatedAt,
      };
    });
}

async function checkChief(db: Db, chapterSlug: string, chief: string | null) {
  if (!chief) {
    return;
  }
  const [stage] = await db.select().from(contentStages).where(eq(contentStages.slug, chief)).limit(1);
  if (!stage || stage.chapterSlug !== chapterSlug) {
    throw new AppError("INVALID_INPUT", "章末关要选这一章里的关卡");
  }
}

function readFields(input: ChapterInput, current: typeof contentChapters.$inferSelect | null) {
  const displayName = input.displayName === undefined ? (current?.displayName ?? "") : text(input.displayName);
  if (!displayName) {
    throw new AppError("INVALID_INPUT", "请填写章节名称");
  }
  const bgKey = input.bgKey === undefined ? current?.bgKey : text(input.bgKey);
  if (!bgKey || !CHAPTER_BG_KEY_SET.has(bgKey)) {
    throw new AppError("INVALID_INPUT", `背景要从 ${[...CHAPTER_BG_KEY_SET].join(" / ")} 里选`);
  }
  const bossFx = input.bossFx === undefined ? (current?.bossFx ?? "default") : text(input.bossFx);
  if (!CHAPTER_BOSS_FX_SET.has(bossFx)) {
    throw new AppError("INVALID_INPUT", `首领特效只能是 ${[...CHAPTER_BOSS_FX_SET].join(" / ")}`);
  }
  const battleBgKey = input.battleBgKey === undefined ? (current?.battleBgKey ?? null) : text(input.battleBgKey) || null;
  if (battleBgKey && !CHAPTER_BATTLE_BG_KEY_SET.has(battleBgKey)) {
    throw new AppError("INVALID_INPUT", `战斗背景要从 ${[...CHAPTER_BATTLE_BG_KEY_SET].join(" / ")} 里选（留空 = 跟随章节背景）`);
  }
  let sortOrder = current?.sortOrder ?? 0;
  if (input.sortOrder !== undefined && input.sortOrder !== null) {
    sortOrder = Number(input.sortOrder);
    if (!Number.isInteger(sortOrder) || sortOrder < 0 || sortOrder > 100000) {
      throw new AppError("INVALID_INPUT", "章节顺序要填 0 到 100000 的整数");
    }
  }
  const chiefStageSlug = input.chiefStageSlug === undefined ? (current?.chiefStageSlug ?? null) : text(input.chiefStageSlug) || null;
  const enabled = input.enabled === undefined ? (current?.enabled ?? true) : input.enabled === true;
  return { displayName, bgKey, bossFx, battleBgKey, sortOrder, chiefStageSlug, enabled };
}

export async function createChapter(db: Db, input: ChapterInput, adminId: string | null) {
  let slug = text(input.slug);
  if (slug) {
    if (!SLUG.test(slug)) {
      throw new AppError("INVALID_INPUT", "章节编号只能用小写字母、数字和下划线，字母开头");
    }
    const [exists] = await db.select().from(contentChapters).where(eq(contentChapters.slug, slug)).limit(1);
    if (exists) {
      throw new AppError("INVALID_INPUT", "章节编号已经存在");
    }
  } else {
    slug = `c${randomBytes(6).toString("hex")}`;
  }
  const fields = readFields(input, null);
  if (input.sortOrder === undefined) {
    const rows = await db.select({ sortOrder: contentChapters.sortOrder }).from(contentChapters);
    fields.sortOrder = rows.reduce((max, row) => Math.max(max, row.sortOrder), 0) + 1;
  }
  await checkChief(db, slug, fields.chiefStageSlug);
  await db.insert(contentChapters).values({ slug, ...fields, updatedAt: new Date(), updatedBy: adminId });
  return { id: slug };
}

export async function updateChapter(db: Db, id: string, input: ChapterInput, adminId: string | null) {
  const [current] = await db.select().from(contentChapters).where(eq(contentChapters.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个章节");
  }
  const fields = readFields(input, current);
  await checkChief(db, id, fields.chiefStageSlug);
  await db.update(contentChapters).set({ ...fields, updatedAt: new Date(), updatedBy: adminId }).where(eq(contentChapters.slug, id));
  return { id };
}

export async function deleteChapter(db: Db, id: string) {
  const [current] = await db.select().from(contentChapters).where(eq(contentChapters.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个章节");
  }
  const used = await db.select({ slug: contentStages.slug }).from(contentStages).where(eq(contentStages.chapterSlug, id));
  if (used.length > 0) {
    throw new AppError("INVALID_INPUT", `还有 ${used.length} 个关卡属于这一章，请先把它们移到别的章节`);
  }
  await db.delete(contentChapters).where(eq(contentChapters.slug, id));
  return { ok: true };
}
