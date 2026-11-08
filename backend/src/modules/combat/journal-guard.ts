import { and, eq, sql } from "drizzle-orm";
import { idempotencyKeys } from "../../db/schema.js";
import type { Tx } from "../../db/tx.js";
import { AppError } from "../../shared/errors.js";
/** Called while the player's row lock is held. Prevents legacy endpoints/second devices moving fog or granting a second boss during playback. */
export async function hasUnsettledCombat(tx: Tx, playerId: string): Promise<boolean> {
  const [row] = await tx.select({ key: idempotencyKeys.key }).from(idempotencyKeys).where(and(eq(idempotencyKeys.playerId, playerId), eq(idempotencyKeys.endpoint, "combat-session"), sql`${idempotencyKeys.response}->'result' = 'null'::jsonb`)).limit(1);
  return Boolean(row);
}
export async function requireNoCombat(tx: Tx, playerId: string): Promise<void> {
  if (await hasUnsettledCombat(tx, playerId)) throw new AppError("INVALID_INPUT", "请先结束当前战斗");
}
