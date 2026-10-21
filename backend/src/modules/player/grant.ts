import { and, eq, inArray } from "drizzle-orm";
import type { Tx } from "../../db/tx.js";
import { contentItems, equipmentGrants, playerItems, playerStates, players } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { readGameRules } from "../content/rules.js";
import { tuningOf } from "../content/tuning.js";

/**
 * 「发放指定装备」统一接口（ADMIN_SPEC §14）。关卡掉落、首领奖励、后台补发（以后活动、邮件）都走这里。
 * - 装备不堆叠：count 件 = count 个 player_items 实例（is_stack = false，source = 本次 source）。
 * - 幂等：requestId 全局唯一；同一个 requestId 再调用不再发，返回第一次生成、现在还在的实例。
 *   同一个 requestId 但玩家 / 装备 / 件数 / source 不一样 → GRANT_REQUEST_CONFLICT（409）。
 * - 行囊满（第五批）：来源在配置概览「行囊满时不发装备的来源」里（默认 stage_drop / boss_first / boss_repeat）时，
 *   放不下就整笔不发、不写流水、不占 requestId，返回空数组并带 skipped: "bag_full"、bagFull: true（不报错，离线 / 挂机同样）。
 *   其他来源（admin_grant / mail / event）照发，可以超出容量。不再自动分解（分解由玩家自己选）。
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
  /**
   * 行囊规则（容量已含 bagBonus；skipSources = 满包不发的来源）。游戏循环里调用时传进来，省得每件都重新读一次配置；
   * 不传就按当前内容 + 玩家状态现算。
   */
  bag?: { capacity: number; skipSources: readonly string[] };
};

/** 生成的装备实例（player_items 行）。 */
export type GrantedEquipment = typeof playerItems.$inferSelect;

/** 返回值：发出的实例数组；行囊满被跳过时是空数组，并带 skipped / bagFull（boss-rewards.ts 的 readGrantResult 读这两个）。 */
export type GrantEquipmentResult = GrantedEquipment[] & { skipped?: "bag_full"; bagFull?: boolean };

/** 行囊里占格的行数（没穿戴的所有行：装备、每个堆叠各占一格；和 loop/bag.ts 的 bagUsedSlots 相同）。 */
async function usedSlots(tx: Tx, playerId: string): Promise<number> {
  const rows = await tx.select({ equippedSlot: playerItems.equippedSlot }).from(playerItems).where(eq(playerItems.playerId, playerId));
  return rows.filter((row) => !row.equippedSlot).length;
}

/** 没传 bag 时现算：容量 = 规则 bagCapacity + 玩家 bagBonus，来源列表读配置概览。读不到内容就不拦（照发）。 */
async function bagPolicy(tx: Tx, playerId: string): Promise<{ capacity: number; skipSources: readonly string[] } | null> {
  const world = await loadCurrentWorld(tx);
  if (!world) {
    return null;
  }
  const [state] = await tx.select({ bagBonus: playerStates.bagBonus }).from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
  return { capacity: readGameRules(world).bagCapacity + (state?.bagBonus ?? 0), skipSources: tuningOf(world.globals.tuning).bagFullSkipSources };
}

function skippedBagFull(): GrantEquipmentResult {
  return Object.assign([] as GrantedEquipment[], { skipped: "bag_full" as const, bagFull: true });
}

export async function grantEquipment(tx: Tx, input: GrantEquipmentInput): Promise<GrantEquipmentResult> {
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

  // 行囊满：配置里的来源（默认关卡掉落 / 首领）放不下就不发。
  const bag = input.bag ?? (await bagPolicy(tx, input.playerId));
  if (bag && bag.skipSources.includes(input.source)) {
    if ((await usedSlots(tx, input.playerId)) + input.count > bag.capacity) {
      return skippedBagFull();
    }
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
