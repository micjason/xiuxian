/**
 * 迷雾秘境后台草稿：读写 content_globals.fog。
 */
import { eq } from "drizzle-orm";
import { contentGlobals } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { DEFAULT_FOG, fogConfigFromInput, type FogConfig } from "./config.js";

export async function readFogView(db: Db) {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  return { config: row?.fog ?? null, starting: DEFAULT_FOG };
}

export async function saveFogConfig(db: Db, input: unknown, adminId: string | null) {
  const [current] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  if (!current) {
    throw new AppError("INVALID_INPUT", "请先新建境界");
  }
  const config = fogConfigFromInput(input);
  await db
    .update(contentGlobals)
    .set({ fog: config, updatedAt: new Date(), updatedBy: adminId })
    .where(eq(contentGlobals.id, 1));
  return readFogView(db);
}

export type { FogConfig };
