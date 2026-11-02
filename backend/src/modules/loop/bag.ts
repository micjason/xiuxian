import { and, eq, inArray } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import type { Tx } from "../../db/tx.js";
import { grantEquipment, type GrantSource } from "../player/grant.js";
import { playerItems, playerStates } from "../../db/schema.js";
import { essenceRules, essenceYield, readEnhanceRules, resolveRealmYieldMajor } from "../content/enhance.js";
import { tuningOf } from "../content/tuning.js";
import type { ContentSnapshot } from "../content/validate.js";
import { AppError } from "../../shared/errors.js";
import { isAutoDecomposeGrantSource, normalizeAutoDecomposeQualities, qualitiesInclude } from "./auto-decompose.js";

type World = ContentSnapshot & { version: number };

/**
 * 行囊（SPEC_Q §17.2 / 17.5 + 挂机自动分解）：
 * - 玩家设置里勾选的品质：挂机 / 关卡 / 首领掉落时立刻拆成炼器精粹，不进包（腾格子给紫橙等）。
 * - 未勾选的品质：行囊满时，配置概览「行囊满时不发装备的来源」里的装备直接不发（skipped: bag_full）。
 * - 手动分解仍走 decomposeItems（分解弹窗）。
 */

export type GrantOptions = {
  /** 行囊容量（已含 bagBonus）。 */
  capacity: number;
  /** 首领首通奖励：只决定装备记成 boss_first（不是 boss_repeat）；满包拦不拦看配置的来源列表。 */
  overflow?: boolean;
  /** 装备走统一发放接口时记的来源（不填按 source 字符串推：wave:关卡 → stage_drop，drop:关卡 → boss_first / boss_repeat，starter → event）。 */
  grant?: { source: GrantSource; sourceRef?: string | null };
};

/** 旧的 source 字符串 → 统一发放接口的来源。 */
export function grantSourceOf(source: string, overflow: boolean): { source: GrantSource; sourceRef: string | null } {
  const [kind, ref] = source.split(":", 2);
  if (kind === "wave") {
    return { source: "stage_drop", sourceRef: ref ?? null };
  }
  if (kind === "drop") {
    return { source: overflow ? "boss_first" : "boss_repeat", sourceRef: ref ?? null };
  }
  return { source: "event", sourceRef: source || null };
}

export type GrantResult = {
  added: number;
  /** 行囊满没发的件数。 */
  dropped: number;
  /** 按玩家勾选品质自动拆掉的件数（不进包）。 */
  decomposed: number;
  /** 自动拆到的炼器精粹总数（字段名沿用老客户端的 enhanceExp）。 */
  enhanceExp: number;
  /** 每件自动拆：itemSlug + 得到的精粹（写在 enhanceExp 里给老客户端读）。 */
  freed: { itemSlug: string; enhanceExp: number }[];
  reason?: "BAG_FULL";
};

export async function bagUsedSlots(tx: Tx, playerId: string): Promise<number> {
  const rows = await tx.select({ id: playerItems.id, equippedSlot: playerItems.equippedSlot }).from(playerItems).where(eq(playerItems.playerId, playerId));
  return rows.filter((row) => !row.equippedSlot).length;
}

/** 给玩家加一种可堆叠物品（并入已有一堆；没有就新建一堆）。 */
export async function addStack(tx: Tx, playerId: string, itemSlug: string, quantity: number, source: string, now: Date) {
  if (quantity <= 0) {
    return;
  }
  const [stackRow] = await tx
    .select({ id: playerItems.id, quantity: playerItems.quantity })
    .from(playerItems)
    .where(and(eq(playerItems.playerId, playerId), eq(playerItems.itemSlug, itemSlug), eq(playerItems.isStack, true)))
    .limit(1);
  if (stackRow) {
    await tx.update(playerItems).set({ quantity: stackRow.quantity + quantity }).where(eq(playerItems.id, stackRow.id));
  } else {
    await tx.insert(playerItems).values({ playerId, itemSlug, isStack: true, quantity, source, acquiredAt: now });
  }
}

/** 玩家现有的某种堆叠物品总数（可能分成几堆）。 */
export function stackCount(items: { itemSlug: string; isStack: boolean; quantity: number }[], itemSlug: string): number {
  return items.filter((row) => row.isStack && row.itemSlug === itemSlug).reduce((sum, row) => sum + row.quantity, 0);
}

/** 从行囊里扣掉 count 个堆叠物品（不够时调用方先检查）。 */
export async function takeStack(tx: Tx, items: { id: string; itemSlug: string; isStack: boolean; quantity: number }[], itemSlug: string, count: number) {
  let left = count;
  for (const row of items.filter((stack) => stack.isStack && stack.itemSlug === itemSlug)) {
    if (left <= 0) {
      break;
    }
    const take = Math.min(left, row.quantity);
    left -= take;
    if (row.quantity - take <= 0) {
      await tx.delete(playerItems).where(eq(playerItems.id, row.id));
    } else {
      await tx.update(playerItems).set({ quantity: row.quantity - take }).where(eq(playerItems.id, row.id));
    }
  }
}

/** 精粹物品编号（规则里配置）。 */
export function essenceItemSlug(world: World): string {
  return essenceRules(readEnhanceRules(world)).itemSlug;
}

/**
 * 分解玩家勾选的装备（SPEC_Q §17.2）：只能是自己的、没穿戴的装备；一次可以多件。
 * 得到的精粹 = Σ(品质 + 部位产出) + Σ(强化等级 × 每级返还)，和客户端预览用同一份规则。返回每件得了多少和总数。
 */
export async function decomposeRows(tx: Tx, world: World, playerId: string, itemIds: string[], now: Date) {
  const ids = [...new Set(itemIds.filter((id) => typeof id === "string" && id))];
  if (ids.length === 0) {
    throw new AppError("INVALID_INPUT", "请先选择装备");
  }
  if (ids.some((id) => !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))) {
    throw new AppError("NOT_FOUND");
  }
  const rows = await tx.select().from(playerItems).where(and(eq(playerItems.playerId, playerId), inArray(playerItems.id, ids)));
  if (rows.length !== ids.length) {
    throw new AppError("NOT_FOUND", "有装备已经不在行囊里了，请刷新");
  }
  for (const row of rows) {
    const def = world.items.find((item) => item.slug === row.itemSlug);
    if (row.equippedSlot) {
      throw new AppError("EQUIPPED_CANNOT_DECOMPOSE", `已穿戴的装备不能分解，请先脱下「${def?.displayName ?? "这件装备"}」`);
    }
    if (!def || def.kind !== "equipment" || !def.slot) {
      throw new AppError("NOT_EQUIPMENT", "这不是装备，不能分解");
    }
  }
  const rules = readEnhanceRules(world);
  const slug = essenceRules(rules).itemSlug;
  if (!world.items.some((item) => item.slug === slug)) {
    throw new AppError("INVALID_INPUT", `炼器精粹物品 ${slug} 不在后台`);
  }
  const pieces: { itemId: string; itemSlug: string; quality: string | null; enhanceLevel: number; essence: number }[] = [];
  for (const row of rows) {
    const def = world.items.find((item) => item.slug === row.itemSlug)!;
    const realm = world.realms.find((row) => row.sortOrder === def.requiredRealmOrder);
    const major = resolveRealmYieldMajor(realm);
    pieces.push({
      itemId: row.id,
      itemSlug: row.itemSlug,
      quality: def.quality ?? null,
      enhanceLevel: row.enhanceLevel,
      essence: essenceYield(rules, def.quality, def.slot, row.enhanceLevel, major) * row.quantity,
    });
  }
  await tx.delete(playerItems).where(and(eq(playerItems.playerId, playerId), inArray(playerItems.id, ids)));
  const total = pieces.reduce((sum, row) => sum + row.essence, 0);
  await addStack(tx, playerId, slug, total, "decompose", now);
  return { pieces, essence: total, itemSlug: slug };
}

/**
 * 发放一件物品，处理行囊容量（设计表 2.6 / 3.7、SPEC_Q §17.5）：
 * - 非装备（突破石、功法书、精粹……）每个堆叠占一格，但从不因为满包被拒绝（可以超出容量）；可叠加的并入已有一堆。
 * - 装备走统一发放接口 grantEquipment：来源在「行囊满时不发装备的来源」里且放不下 → 不发（dropped，reason = BAG_FULL）。
 */
export async function grantItem(
  tx: Tx,
  world: World,
  playerId: string,
  itemSlug: string,
  quantity: number,
  source: string,
  now: Date,
  options: GrantOptions,
): Promise<GrantResult> {
  const result: GrantResult = { added: 0, dropped: 0, decomposed: 0, enhanceExp: 0, freed: [] };
  const definition = world.items.find((row) => row.slug === itemSlug);
  if (!definition || quantity <= 0) {
    return result;
  }
  const isGear = definition.kind === "equipment" && Boolean(definition.slot);
  if (!isGear) {
    await addStack(tx, playerId, itemSlug, quantity, source, now);
    result.added += 1;
    return result;
  }
  const grant = options.grant ?? grantSourceOf(source, Boolean(options.overflow));
  const skipSources = tuningOf(world.globals.tuning).bagFullSkipSources;
  const autoQualities = isAutoDecomposeGrantSource(grant.source) ? await loadAutoDecomposeQualities(tx, playerId) : [];
  const shouldAuto = isAutoDecomposeGrantSource(grant.source) && qualitiesInclude(autoQualities, definition.quality);
  if (shouldAuto) {
    let essencePer = 0;
    try {
      const rules = readEnhanceRules(world);
      const slug = essenceRules(rules).itemSlug;
      if (!world.items.some((item) => item.slug === slug)) {
        throw new Error("missing essence item");
      }
      const realm = world.realms.find((row) => row.sortOrder === definition.requiredRealmOrder);
      const major = resolveRealmYieldMajor(realm);
      essencePer = essenceYield(rules, definition.quality, definition.slot, 0, major);
      for (let index = 0; index < quantity; index += 1) {
        await addStack(tx, playerId, slug, essencePer, "auto_decompose", now);
        result.decomposed += 1;
        result.enhanceExp += essencePer;
        result.freed.push({ itemSlug, enhanceExp: essencePer });
      }
      return result;
    } catch {
      // 精粹规则没配好：退回正常进包，别把掉落吞了。
    }
  }
  for (let index = 0; index < quantity; index += 1) {
    const created = await grantEquipment(tx, {
      playerId,
      itemId: itemSlug,
      count: 1,
      source: grant.source,
      sourceRef: grant.sourceRef ?? null,
      requestId: randomUUID(),
      bag: { capacity: options.capacity, skipSources },
    });
    if (created.skipped) {
      result.dropped += 1;
      result.reason = "BAG_FULL";
      continue;
    }
    result.added += 1;
  }
  return result;
}

async function loadAutoDecomposeQualities(tx: Tx, playerId: string): Promise<string[]> {
  const [row] = await tx
    .select({ autoDecomposeQualities: playerStates.autoDecomposeQualities })
    .from(playerStates)
    .where(eq(playerStates.playerId, playerId))
    .limit(1);
  return normalizeAutoDecomposeQualities(row?.autoDecomposeQualities);
}
