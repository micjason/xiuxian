import { and, isNotNull, lt, or } from "drizzle-orm";
import { sessions } from "../../db/schema.js";
import type { Db } from "../operations/record.js";

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

export async function purgeOldSessions(db: Db, now: Date): Promise<void> {
  const cutoff = new Date(now.getTime() - WEEK_MS);
  await db.delete(sessions).where(
    or(lt(sessions.expiresAt, cutoff), and(isNotNull(sessions.revokedAt), lt(sessions.revokedAt, cutoff))),
  );
}

export function startSessionCleanup(db: Db, now: () => Date = () => new Date()): () => void {
  const timer = setInterval(() => {
    void purgeOldSessions(db, now());
  }, 60 * 60 * 1000);
  timer.unref();
  return () => clearInterval(timer);
}
