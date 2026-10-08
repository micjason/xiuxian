import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { eq } from "drizzle-orm";
import { appReleases } from "../../db/schema.js";
import type { Db } from "../operations/record.js";

const PUBLIC_BASE = process.env.PUBLIC_BASE_URL ?? "http://101.132.74.32";

export function apkDirectory(): string {
  return process.env.APK_DIR ?? path.join(process.cwd(), "var", "apks");
}

export async function listReleases(db: Db) {
  return db.select().from(appReleases).orderBy(appReleases.versionCode);
}

export async function saveRelease(
  db: Db,
  input: {
    versionName: string;
    versionCode: number;
    releaseNotes: string;
    forceUpdate: boolean;
    bytes: Buffer;
  },
) {
  if (!input.versionName || input.versionCode <= 0 || input.bytes.length === 0) {
    throw new Error("invalid release");
  }
  const sha256 = createHash("sha256").update(input.bytes).digest("hex");
  const storedName = `${input.versionCode}.apk`;
  await mkdir(apkDirectory(), { recursive: true });
  await writeFile(path.join(apkDirectory(), storedName), input.bytes);
  await db.update(appReleases).set({ isCurrent: false }).where(eq(appReleases.isCurrent, true));
  const [created] = await db
    .insert(appReleases)
    .values({
      versionName: input.versionName,
      versionCode: input.versionCode,
      releaseNotes: input.releaseNotes,
      forceUpdate: input.forceUpdate,
      sha256,
      sizeBytes: input.bytes.length,
      storedName,
      isCurrent: true,
    })
    .returning();
  if (!created) {
    throw new Error("release insert failed");
  }
  return created;
}

export async function currentRelease(db: Db) {
  const [row] = await db.select().from(appReleases).where(eq(appReleases.isCurrent, true)).limit(1);
  return row ?? null;
}

export function manifestFor(release: {
  versionName: string;
  versionCode: number;
  releaseNotes: string;
  forceUpdate: boolean;
  sha256: string;
  sizeBytes: number;
}) {
  return {
    version: release.versionName,
    version_code: release.versionCode,
    minimum_version: release.forceUpdate ? release.versionName : "0.1.0",
    force_update: release.forceUpdate,
    apk_url: `${PUBLIC_BASE}/apk/xiuxian.apk`,
    apk_size: release.sizeBytes,
    apk_sha256: release.sha256,
    release_notes: release.releaseNotes,
  };
}

export function openCurrentApk(storedName: string) {
  return createReadStream(path.join(apkDirectory(), storedName));
}

export async function readCurrentApk(storedName: string) {
  return readFile(path.join(apkDirectory(), storedName));
}
