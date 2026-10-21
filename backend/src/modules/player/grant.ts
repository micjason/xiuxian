import { and, eq, inArray } from "drizzle-orm";
import type { Tx } from "../../db/tx.js";
import { contentItems, equipmentGrants, playerItems, players } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";

/**
 * 「发放指定装备」统一接口（ADMIN_SPEC §14）。关卡掉落、首领奖励、后台补发（以后活动、邮件）都走这里。
 * - 装备不堆叠：count 件 = count 个 player_items 实例（is_stack = false，source = 本次 source）。
 * - 幂等：requestId 全局唯一；同一个 requestId 再调用不再发，返回第一次生成、现在还在的实例。
 *   同一个 requestId 但玩家 / 装备 / 件数 / source 不一样 → GRANT_REQUEST_CONFLICT（409）。
 * - 行囊满照放（允许超出容量），不自动分解。
 * - 每次发放写一行 equipment_grants 流水（后台操作日志按 source 筛）。
 * 必须在调用方的事务里调用（tx），和调用方的其他写入一起提交或回滚。
 */
export const GRANT_SOURCES = ["stage_drop", "boss_first", "boss_repeat", "admin_grant", "event", "mail"] as const;
export type GrantSource = (typeof GRANT_SOURCES)[number];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** 一次最多发多少件（防止误填）。 */
export const GRANT_MAX_COUNT = 100;

export type GrantEquipmentInput = {
  /** 收件玩家 players.id（uuid） */
  playerId: string;
  /** 装备编号 content_items.slug（公式 gear_major1_weapon_blue，手动 gear_m_0001） */
  itemId: string;
  /** 件数，整数 1..GRANT_MAX_COUNT */
  count: number;
  source: GrantSource;
  /** 关卡 id / 首领 id / 补发单号 */
  sourceRef?: string | null;
  /** 幂等键，重复请求不重复发 */
  requestId: string;
  /** 只有 admin_grant 用：后台账号 */
  operator?: string | null;
  /** 只有 admin_grant 用 */
  reason?: string | null;
  /** 只有 admin_grant 用 */
  note?: string | null;
};

/** 生成的装备实例（player_items 行）。 */
export type GrantedEquipment = typeof playerItems.$inferSelect;

export async function grantEquipment(tx: Tx, input: GrantEquipmentInput): Promise<GrantedEquipment[]> {
  const requestId = typeof input.requestId === "string" ? input.requestId.trim() : "";
  if (!requestId) {
    throw new AppError("INVALID_INPUT", "缺少 requestId", { field: "requestId" });
  }
  if (typeof input.playerId !== "string" || !UUID.test(input.playerId)) {
    throw new AppError("INVALID_INPUT", "playerId 不正确", { field: "playerId" });
  }
  if (typeof input.itemId !== "string" || !input.itemId) {
    throw new AppError("INVALID_INPUT", "缺少 itemId", { field: "itemId" });
  }
  if (!GRANT_SOURCES.includes(input.source)) {
    throw new AppError("INVALID_INPUT", "source 不正确", { field: "source", allowed: GRANT_SOURCES });
  }
  if (!Number.isInteger(input.count) || input.count < 1 || input.count > GRANT_MAX_COUNT) {
    throw new AppError("INVALID_INPUT", `count 必须是 1..${GRANT_MAX_COUNT} 的整数`, { field: "count" });
  }

  // 已经发过（重复请求）：不再发。
  const replay = await replayGrant(tx, requestId, input);
  if (replay) {
    return replay;
  }

  // 先校验（只读），不让外键错误把调用方的事务弄坏。
  const [player] = await tx.select({ id: players.id }).from(players).where(eq(players.id, input.playerId));
  if (!player) {
    throw new AppError("NOT_FOUND", "玩家不存在", { field: "playerId" });
  }
  const [item] = await tx.select({ slug: contentItems.slug, kind: contentItems.kind, slot: contentItems.slot }).from(contentItems).where(eq(contentItems.slug, input.itemId));
  if (!item) {
    throw new AppError("NOT_FOUND", "装备不存在", { field: "itemId", itemId: input.itemId });
  }
  if (item.kind !== "equipment" || !item.slot) {
    throw new AppError("NOT_EQUIPMENT", undefined, { field: "itemId", itemId: input.itemId });
  }

  // 占 requestId（唯一索引）。并发的同号请求会在这里等前一个事务提交，然后什么都不插入 → 走重复请求分支。
  const [claimed] = await tx
    .insert(equipmentGrants)
    .values({
      requestId,
      playerId: input.playerId,
      itemSlug: input.itemId,
      count: input.count,
      source: input.source,
      sourceRef: input.sourceRef ?? null,
      operator: input.operator ?? null,
      reason: input.reason ?? null,
      note: input.note ?? null,
    })
    .onConflictDoNothing({ target: equipmentGrants.requestId })
    .returning({ id: equipmentGrants.id });
  if (!claimed) {
    const raced = await replayGrant(tx, requestId, input);
    if (raced) {
      return raced;
    }
    throw new AppError("GRANT_REQUEST_CONFLICT", undefined, { requestId });
  }

  const now = new Date();
  const created = await tx
    .insert(playerItems)
    .values(
      Array.from({ length: input.count }, () => ({
        playerId: input.playerId,
        itemSlug: item.slug,
        isStack: false,
        quantity: 1,
        source: input.source,
        acquiredAt: now,
      })),
    )
    .returning();
  await tx.update(equipmentGrants).set({ instanceIds: created.map((row) => row.id) }).where(eq(equipmentGrants.id, claimed.id));
  return created;
}

/** 同一个 requestId 已经发过：核对是同一笔，返回当时生成、现在还在的实例（可能已被分解 / 删除）；没发过返回 null。 */
async function replayGrant(tx: Tx, requestId: string, input: GrantEquipmentInput): Promise<GrantedEquipment[] | null> {
  const [existing] = await tx.select().from(equipmentGrants).where(eq(equipmentGrants.requestId, requestId));
  if (!existing) {
    return null;
  }
  if (existing.playerId !== input.playerId || existing.itemSlug !== input.itemId || existing.count !== input.count || existing.source !== input.source) {
    throw new AppError("GRANT_REQUEST_CONFLICT", undefined, { requestId });
  }
  if (existing.instanceIds.length === 0) {
    return [];
  }
  const rows = await tx
    .select()
    .from(playerItems)
    .where(and(eq(playerItems.playerId, existing.playerId), inArray(playerItems.id, existing.instanceIds)));
  const order = new Map(existing.instanceIds.map((id, index) => [id, index]));
  return rows.sort((left, right) => (order.get(left.id) ?? 0) - (order.get(right.id) ?? 0));
}
