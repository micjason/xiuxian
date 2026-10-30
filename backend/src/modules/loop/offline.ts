import { and, desc, eq, isNull, lt, or } from "drizzle-orm";
import type { Tx } from "../../db/tx.js";
import { playerOfflineReports } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";

export type OfflineLootItem = {
  itemSlug: string;
  quantity: number;
  quality: string | null;
  idle?: boolean;
  seed?: boolean;
};

export type OfflineReportInput = {
  playerId: string;
  startedAt: Date;
  endedAt: Date;
  seconds: number;
  countedSeconds: number;
  hitCap: boolean;
  gained: number;
  baseGained: number;
  realmSlug: string;
  loot?: OfflineLootItem[];
  bagFullSkipped?: boolean;
};

/**
 * 离线结算记录：每一段离线（两次结算间隔超过在线判定）都入库，供客户端弹“闭关归来”和以后对账。
 * 基础修为 = 计入的节拍数 × 每次获得修为；功法加成 = 实际入账 − 基础（余数携带可能让两者差 1 以内）。
 */
export async function recordOfflineReport(tx: Tx, input: OfflineReportInput) {
  const bonusGained = Math.max(0, input.gained - input.baseGained);
  const [row] = await tx
    .insert(playerOfflineReports)
    .values({
      playerId: input.playerId,
      startedAt: input.startedAt,
      endedAt: input.endedAt,
      seconds: input.seconds,
      countedSeconds: input.countedSeconds,
      hitCap: input.hitCap,
      gained: input.gained,
      baseGained: Math.min(input.baseGained, input.gained),
      bonusGained,
      realmSlug: input.realmSlug,
      loot: input.loot ?? [],
      bagFullSkipped: Boolean(input.bagFullSkipped),
    })
    .returning();
  return row;
}

/** 还没点“已读”的最新一条离线记录（没有就是 null）。 */
export async function pendingOfflineReport(tx: Tx, playerId: string) {
  const [row] = await tx
    .select()
    .from(playerOfflineReports)
    .where(and(eq(playerOfflineReports.playerId, playerId), isNull(playerOfflineReports.acknowledgedAt)))
    .orderBy(desc(playerOfflineReports.createdAt), desc(playerOfflineReports.startedAt))
    .limit(1);
  return row ?? null;
}

/**
 * “已读”确认：只是不再弹窗，没有领取（修为在结算时已经入账）。重复确认没有副作用；
 * 同时把更早的未读记录也标成已读，避免连着弹好几个窗。别人的记录按“不存在”处理。
 */
export async function acknowledgeOfflineReport(tx: Tx, playerId: string, reportId: string, now: Date) {
  const [row] = await tx
    .select()
    .from(playerOfflineReports)
    .where(and(eq(playerOfflineReports.id, reportId), eq(playerOfflineReports.playerId, playerId)))
    .limit(1);
  if (!row) {
    throw new AppError("NOT_FOUND", "没有这条离线记录");
  }
  await tx
    .update(playerOfflineReports)
    .set({ acknowledgedAt: now })
    .where(and(eq(playerOfflineReports.playerId, playerId), isNull(playerOfflineReports.acknowledgedAt), or(eq(playerOfflineReports.id, row.id), lt(playerOfflineReports.createdAt, row.createdAt))));
  return { ok: true, id: row.id, acknowledged: true };
}
