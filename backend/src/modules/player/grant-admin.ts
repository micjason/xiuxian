/**
 * 后台「装备补发」（ADMIN_SPEC §14，设计稿 equip_grant.png）。
 * 选玩家 → 选装备 → 件数 → 原因（必填）→ grantEquipment(source = admin_grant)。
 * - 幂等：后台每次打开确认框生成一个 requestId，重复点击 / 网络重试不会多发。
 * - 背包满了照样发（超出容量，玩家整理后再处理），返回里会提示。
 * - 流水在 equipment_grants，后台「操作日志 → 装备发放」按来源筛。
 */
import { and, count, desc, eq, gte, ilike, inArray, isNull, lte, sql, type SQL } from "drizzle-orm";
import { contentItems, equipmentGrants, playerItems, players, playerStates } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { readGameRules } from "../content/rules.js";
import { GRANT_SOURCES, grantEquipment, type GrantSource } from "./grant.js";

export const ADMIN_GRANT_MAX = 20;
export const GRANT_REASONS = ["补偿 · 奖励未到账", "补偿 · 服务器故障", "活动奖励", "测试", "其他"] as const;
export const GRANT_BATCH_LIMITS = { players: 100, items: 10 } as const;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type AdminGrantInput = { playerId?: unknown; itemId?: unknown; count?: unknown; reason?: unknown; note?: unknown; requestId?: unknown };

/** 选玩家：按账号模糊找（最多 20 个），带境界、背包占用。 */
export async function searchGrantPlayers(db: Db, query: string) {
  const text = query.trim();
  const filter = text ? (UUID.test(text) ? eq(players.id, text) : ilike(players.username, `%${text.replace(/[%_\\]/g, (char) => `\\${char}`)}%`)) : undefined;
  const rows = await db
    .select({ id: players.id, username: players.username, realmSlug: playerStates.realmSlug, bagBonus: playerStates.bagBonus, lastSettledAt: playerStates.lastSettledAt })
    .from(players)
    .innerJoin(playerStates, eq(playerStates.playerId, players.id))
    .where(filter)
    .orderBy(desc(playerStates.lastSettledAt))
    .limit(20);
  if (rows.length === 0) {
    return [];
  }
  const world = await loadCurrentWorld(db);
  const capacity = world ? readGameRules(world).bagCapacity : 0;
  const used = await db
    .select({ playerId: playerItems.playerId, n: count() })
    .from(playerItems)
    .where(and(inArray(playerItems.playerId, rows.map((row) => row.id)), isNull(playerItems.equippedSlot)))
    .groupBy(playerItems.playerId);
  return rows.map((row) => ({
    id: row.id,
    username: row.username,
    realmName: world?.realms.find((realm) => realm.slug === row.realmSlug)?.displayName ?? row.realmSlug,
    bagUsed: Number(used.find((entry) => entry.playerId === row.id)?.n ?? 0),
    bagCapacity: capacity + (row.bagBonus ?? 0),
    lastSettledAt: row.lastSettledAt,
  }));
}

/** 后台补发：校验 → grantEquipment(admin_grant) → 返回发了哪些、背包是否超出。 */
export async function adminGrant(db: Db, input: AdminGrantInput, actor: { actorId: string; actorName: string }) {
  const playerId = String(input.playerId ?? "");
  const itemId = String(input.itemId ?? "");
  const requestId = String(input.requestId ?? "").trim();
  const reason = String(input.reason ?? "").trim();
  const note = String(input.note ?? "").trim();
  const total = Number(input.count);
  if (!UUID.test(playerId)) {
    throw new AppError("INVALID_INPUT", "请选择玩家");
  }
  if (!itemId) {
    throw new AppError("INVALID_INPUT", "请选择装备");
  }
  if (!Number.isInteger(total) || total < 1 || total > ADMIN_GRANT_MAX) {
    throw new AppError("INVALID_INPUT", `件数要在 1–${ADMIN_GRANT_MAX} 之间`);
  }
  if (!reason) {
    throw new AppError("INVALID_INPUT", "请填写补发原因");
  }
  if (reason.length > 60 || note.length > 200) {
    throw new AppError("INVALID_INPUT", "原因最多 60 个字，备注最多 200 个字");
  }
  if (!requestId || requestId.length > 128) {
    throw new AppError("INVALID_INPUT", "缺少发放单号，请刷新页面再试");
  }
  // 只能发游戏里现在有的装备（玩家按当前内容显示）
  const world = await loadCurrentWorld(db);
  const published = world?.items.find((item) => item.slug === itemId);
  if (!published || published.kind !== "equipment") {
    throw new AppError("INVALID_INPUT", "没有这件装备（或已经不是装备）");
  }
  const rows = await db.transaction((tx) =>
    grantEquipment(tx, {
      playerId,
      itemId,
      count: total,
      source: "admin_grant",
      requestId: `admin:${requestId}`,
      operator: actor.actorName,
      reason,
      note: note || null,
    }),
  );
  const [player] = await searchGrantPlayers(db, playerId);
  return {
    granted: rows.map((row) => ({ id: row.id, itemSlug: row.itemSlug })),
    player: player ?? null,
    overflow: player ? Math.max(0, player.bagUsed - player.bagCapacity) : 0,
  };
}

/** 发放流水：按来源 / 玩家 / 时间筛，新的在前，分页。 */
export async function listGrants(db: Db, query: { source?: string; player?: string; from?: string; to?: string; limit?: string | number; offset?: string | number }) {
  const filters: SQL[] = [];
  if (query.source) {
    if (!(GRANT_SOURCES as readonly string[]).includes(query.source)) {
      throw new AppError("INVALID_INPUT", "来源不正确");
    }
    filters.push(eq(equipmentGrants.source, query.source as GrantSource));
  }
  if (query.player) {
    const text = query.player.trim();
    filters.push(UUID.test(text) ? eq(equipmentGrants.playerId, text) : ilike(players.username, `%${text.replace(/[%_\\]/g, (char) => `\\${char}`)}%`));
  }
  if (query.from) {
    filters.push(gte(equipmentGrants.createdAt, new Date(query.from)));
  }
  if (query.to) {
    filters.push(lte(equipmentGrants.createdAt, new Date(query.to)));
  }
  const limit = Math.min(200, Math.max(1, Number(query.limit) || 50));
  const offset = Math.max(0, Number(query.offset) || 0);
  const where = filters.length > 0 ? and(...filters) : undefined;
  const rows = await db
    .select({
      id: equipmentGrants.id,
      createdAt: equipmentGrants.createdAt,
      source: equipmentGrants.source,
      sourceRef: equipmentGrants.sourceRef,
      playerId: equipmentGrants.playerId,
      username: players.username,
      itemSlug: equipmentGrants.itemSlug,
      itemName: contentItems.displayName,
      quality: contentItems.quality,
      count: equipmentGrants.count,
      operator: equipmentGrants.operator,
      reason: equipmentGrants.reason,
      note: equipmentGrants.note,
      requestId: equipmentGrants.requestId,
    })
    .from(equipmentGrants)
    .innerJoin(players, eq(players.id, equipmentGrants.playerId))
    .leftJoin(contentItems, eq(contentItems.slug, equipmentGrants.itemSlug))
    .where(where)
    .orderBy(desc(equipmentGrants.createdAt))
    .limit(limit)
    .offset(offset);
  const [total] = await db
    .select({ n: sql<number>`count(*)::int` })
    .from(equipmentGrants)
    .innerJoin(players, eq(players.id, equipmentGrants.playerId))
    .where(where);
  return { rows, total: total?.n ?? 0, sources: GRANT_SOURCES };
}


export type AdminGrantBatchInput = { playerIds?: unknown; items?: unknown; reason?: unknown; note?: unknown; batchId?: unknown };

/**
 * 补发抽屉一次发放：多个玩家 × 多件装备，同一个事务（全部成功或全部不发）。
 * 每个（玩家, 装备）一条 equipment_grants，requestId = admin:{补发单号}:{玩家}:{装备}，sourceRef = 补发单号；
 * 同一个补发单号重复提交（双击、网络重试）不会多发。
 */
export async function adminGrantBatch(db: Db, input: AdminGrantBatchInput, actor: { actorId: string; actorName: string }) {
  const playerIds = Array.isArray(input.playerIds) ? [...new Set(input.playerIds.map((value) => String(value)))] : [];
  if (playerIds.length === 0) {
    throw new AppError("INVALID_INPUT", "请选择玩家");
  }
  if (playerIds.length > GRANT_BATCH_LIMITS.players) {
    throw new AppError("INVALID_INPUT", `一次最多发给 ${GRANT_BATCH_LIMITS.players} 名玩家`);
  }
  if (playerIds.some((id) => !UUID.test(id))) {
    throw new AppError("INVALID_INPUT", "玩家编号不正确");
  }
  const rawItems = Array.isArray(input.items) ? input.items : [];
  if (rawItems.length === 0) {
    throw new AppError("INVALID_INPUT", "请选择要发的装备");
  }
  if (rawItems.length > GRANT_BATCH_LIMITS.items) {
    throw new AppError("INVALID_INPUT", `一次最多 ${GRANT_BATCH_LIMITS.items} 种装备`);
  }
  const world = await loadCurrentWorld(db);
  const seen = new Set<string>();
  const items = rawItems.map((raw, index) => {
    const itemId = String((raw as { itemId?: unknown })?.itemId ?? "");
    const total = Number((raw as { count?: unknown })?.count);
    const item = world?.items.find((row) => row.slug === itemId);
    if (!item || item.kind !== "equipment") {
      throw new AppError("INVALID_INPUT", `第 ${index + 1} 行：请选择装备`);
    }
    if (seen.has(itemId)) {
      throw new AppError("INVALID_INPUT", `第 ${index + 1} 行：「${item.displayName}」重复了`);
    }
    seen.add(itemId);
    if (!Number.isInteger(total) || total < 1 || total > ADMIN_GRANT_MAX) {
      throw new AppError("INVALID_INPUT", `第 ${index + 1} 行：每人数量要在 1–${ADMIN_GRANT_MAX} 之间`);
    }
    return { itemId, count: total, displayName: item.displayName };
  });
  const reason = String(input.reason ?? "").trim();
  const note = String(input.note ?? "").trim();
  const batchId = String(input.batchId ?? "").trim();
  if (!reason) {
    throw new AppError("INVALID_INPUT", "请选择补发原因");
  }
  if (!note) {
    throw new AppError("INVALID_INPUT", "请填写备注（写进操作日志，玩家看不到）");
  }
  if (reason.length > 60 || note.length > 200) {
    throw new AppError("INVALID_INPUT", "原因最多 60 个字，备注最多 200 个字");
  }
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(batchId)) {
    throw new AppError("INVALID_INPUT", "缺少补发单号，请重新打开补发抽屉");
  }
  const known = await db.select({ id: players.id }).from(players).where(inArray(players.id, playerIds));
  const missing = playerIds.filter((id) => !known.some((row) => row.id === id));
  if (missing.length > 0) {
    throw new AppError("INVALID_INPUT", `有 ${missing.length} 名玩家不存在`);
  }
  const granted = await db.transaction(async (tx) => {
    let total = 0;
    for (const playerId of playerIds) {
      for (const item of items) {
        const rows = await grantEquipment(tx, {
          playerId,
          itemId: item.itemId,
          count: item.count,
          source: "admin_grant",
          sourceRef: batchId,
          requestId: `admin:${batchId}:${playerId}:${item.itemId}`,
          operator: actor.actorName,
          reason,
          note,
        });
        total += rows.length;
      }
    }
    return total;
  });
  return { batchId, players: playerIds.length, items: items.map(({ itemId, count: each }) => ({ itemId, count: each })), granted };
}
