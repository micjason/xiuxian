import { desc, eq } from "drizzle-orm";
import { contentCurrent, contentVersions } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { diffSnapshots } from "./snapshot-diff.js";
import { loadDraftSnapshot } from "./snapshot.js";
import type { ContentSnapshot } from "./validate.js";

/** 已发布版本列表（不含快照正文）。只读。 */
export async function listContentVersions(db: Db) {
  const [current] = await db.select().from(contentCurrent).where(eq(contentCurrent.id, 1)).limit(1);
  const rows = await db
    .select({
      version: contentVersions.version,
      checksum: contentVersions.checksum,
      note: contentVersions.note,
      publishedBy: contentVersions.publishedBy,
      publishedAt: contentVersions.publishedAt,
      sourceVersion: contentVersions.sourceVersion,
    })
    .from(contentVersions)
    .orderBy(desc(contentVersions.version));
  return {
    currentVersion: current?.version ?? null,
    versions: rows.map((row) => ({ ...row, isCurrent: row.version === (current?.version ?? null) })),
  };
}

type Ref = "draft" | "current" | number;

function parseRef(value: unknown, fallback: Ref): Ref {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  if (value === "draft" || value === "current") {
    return value;
  }
  const version = Number(value);
  if (!Number.isInteger(version) || version < 1) {
    throw new AppError("INVALID_INPUT", "版本号不正确");
  }
  return version;
}

async function snapshotOf(db: Db, ref: Ref): Promise<Partial<ContentSnapshot> | null> {
  if (ref === "draft") {
    return loadDraftSnapshot(db);
  }
  let version: number | null;
  if (ref === "current") {
    const [current] = await db.select().from(contentCurrent).where(eq(contentCurrent.id, 1)).limit(1);
    version = current?.version ?? null;
  } else {
    version = ref;
  }
  if (version === null) {
    return null;
  }
  const [row] = await db.select().from(contentVersions).where(eq(contentVersions.version, version)).limit(1);
  if (!row) {
    throw new AppError("NOT_FOUND", `没有版本 ${version}`);
  }
  return row.snapshot as Partial<ContentSnapshot>;
}

/** 比较任意两个版本，或版本和草稿。默认比较「当前发布版」和「草稿」，用来在发布前列出改动。只读。 */
export async function diffContent(db: Db, query: { from?: unknown; to?: unknown }) {
  const from = parseRef(query.from, "current");
  const to = parseRef(query.to, "draft");
  const before = await snapshotOf(db, from);
  const after = await snapshotOf(db, to);
  if (!after) {
    throw new AppError("NOT_FOUND", "没有可比较的内容");
  }
  return { from, to, ...diffSnapshots(before, after) };
}
