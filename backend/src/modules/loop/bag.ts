import { and, eq, sql } from "drizzle-orm";
import type { Tx } from "../../db/tx.js";
import { playerItems, playerStates } from "../../db/schema.js";
import { decomposeEnhanceExp, readEnhanceRules } from "../content/enhance.js";
import type { ContentSnapshot } from "../content/validate.js";

type World = ContentSnapshot & { version: number };

/** 自动分解只动这两种品质（蓝、紫、橙永远不自动分解）。 */
export const AUTO_DECOMPOSE_QUALITIES = new Set(["white", "green"]);

export async function addEnhanceExp(tx: Tx, playerId: string, amount: number) {
  await tx
    .update(playerStates)
    .set({ enhanceExp: sql`${playerStates.enhanceExp} + ${amount}` })
    .where(eq(playerStates.playerId, playerId));
}

export type GrantOptions = {
  /** 玩家的“满包自动分解”开关。 */
  autoDecompose: boolean;
  /** 行囊容量（已含 bagBonus）。 */
  capacity: number;
  /** 首领首通奖励：允许暂时超出容量。 */
  overflow?: boolean;
};

export type GrantResult = {
  added: number;
  /** 新掉落的白/绿装备直接分解成了强化经验的件数。 */
  decomposed: number;
  /** 没放进行囊、也没有分解（背包满）的件数。 */
  dropped: number;
  /** 本次因分解得到的强化经验（新掉落直接分解 + 腾格分解）。 */
  enhanceExp: number;
  /** 为了放下蓝/紫等新掉落，被分解腾格的包内装备。 */
  freed: { itemSlug: string; enhanceExp: number }[];
  reason?: "BAG_FULL";
};

export async function bagUsedSlots(tx: Tx, playerId: string): Promise<number> {
  const rows = await tx.select({ id: playerItems.id, equippedSlot: playerItems.equippedSlot }).from(playerItems).where(eq(playerItems.playerId, playerId));
  return rows.filter((row) => !row.equippedSlot).length;
}

/**
 * 在行囊里找一件可以自动分解的装备：没穿、没强化（+0）、白或绿；先白后绿，同品质先拿到的先分解。
 * 蓝、紫、橙，以及已强化的，永远不会被选中。
 */
export async function pickAutoDecomposeCandidate(tx: Tx, world: World, playerId: string) {
  const rows = await tx.select().from(playerItems).where(eq(playerItems.playerId, playerId));
  const candidates = rows
    .filter((row) => !row.equippedSlot && row.enhanceLevel === 0)
    .map((row) => ({ row, def: world.items.find((item) => item.slug === row.itemSlug) }))
    .filter((entry) => entry.def?.kind === "equipment" && entry.def.slot && AUTO_DECOMPOSE_QUALITIES.has(entry.def.quality ?? "white"));
  candidates.sort((left, right) => {
    const quality = (left.def?.quality === "white" ? 0 : 1) - (right.def?.quality === "white" ? 0 : 1);
    return quality !== 0 ? quality : left.row.acquiredAt.getTime() - right.row.acquiredAt.getTime();
  });
  return candidates[0] ?? null;
}

/** 分解一件包内装备（行删掉，强化经验入账），返回得到的经验。 */
export async function decomposeRow(tx: Tx, world: World, playerId: string, row: { id: string; itemSlug: string; quantity: number; enhanceLevel: number }) {
  const def = world.items.find((item) => item.slug === row.itemSlug);
  const gained = decomposeEnhanceExp(readEnhanceRules(world), def?.quality, row.enhanceLevel) * row.quantity;
  await tx.delete(playerItems).where(eq(playerItems.id, row.id));
  await addEnhanceExp(tx, playerId, gained);
  return gained;
}

/**
 * 挑战前腾格：行囊满且开关开着时，分解一件白/绿腾出一格。返回腾格结果；没有可分解的就返回 null。
 */
export async function freeOneSlot(tx: Tx, world: World, playerId: string): Promise<{ itemSlug: string; enhanceExp: number } | null> {
  const candidate = await pickAutoDecomposeCandidate(tx, world, playerId);
  if (!candidate) {
    return null;
  }
  const enhanceExp = await decomposeRow(tx, world, playerId, candidate.row);
  return { itemSlug: candidate.row.itemSlug, enhanceExp };
}

async function insertRow(tx: Tx, playerId: string, itemSlug: string, isStack: boolean, quantity: number, source: string, now: Date) {
  await tx.insert(playerItems).values({ playerId, itemSlug, isStack, quantity, source, acquiredAt: now });
}

/**
 * 发放一件物品，处理行囊容量（设计表 2.6 / 3.7）。负责人确认的规则：突破石、功法书这类非装备物品每个堆叠仍占一格
 * （bagUsedSlots 数的是所有没穿戴的行），但从不因为满包被拒绝——满包时照常入包，可以超出容量；只有装备的新掉落受容量限制：
 * - 有空格：直接入包（可叠加物品并入已有一堆，不占新格）。
 * - 没有空格（只针对装备掉落）：
 *   · 新掉落是白/绿装备、开关开：直接分解成强化经验；
 *   · 新掉落是蓝/紫装备、开关开：分解包内一件没强化的白/绿腾出一格再入包；找不到可分解的就不掉；
 *   · 开关关：不掉，reason = BAG_FULL。
 * - options.overflow（首领首通奖励）：不管容量，直接入包。
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
  const result: GrantResult = { added: 0, decomposed: 0, dropped: 0, enhanceExp: 0, freed: [] };
  const definition = world.items.find((row) => row.slug === itemSlug);
  if (!definition || quantity <= 0) {
    return result;
  }
  const isGear = definition.kind === "equipment" && Boolean(definition.slot);
  const unit = isGear ? 1 : quantity;
  const repeat = isGear ? quantity : 1;
  for (let index = 0; index < repeat; index += 1) {
    let stackRow: { id: string; quantity: number } | undefined;
    if (!isGear) {
      [stackRow] = await tx
        .select({ id: playerItems.id, quantity: playerItems.quantity })
        .from(playerItems)
        .where(and(eq(playerItems.playerId, playerId), eq(playerItems.itemSlug, itemSlug), eq(playerItems.isStack, true)))
        .limit(1);
    }
    const needsSlot = !stackRow;
    // 满包只拦装备掉落：突破石、功法书每个堆叠仍占一格（计入 bagUsedSlots），但满包时不检查容量，直接入包（可超出容量），不会因为背包满而丢。
    if (needsSlot && !options.overflow && isGear) {
      const used = await bagUsedSlots(tx, playerId);
      if (used >= options.capacity) {
        const newIsAutoQuality = isGear && AUTO_DECOMPOSE_QUALITIES.has(definition.quality ?? "white");
        if (!options.autoDecompose) {
          result.dropped += 1;
          result.reason = "BAG_FULL";
          continue;
        }
        if (newIsAutoQuality) {
          const gained = decomposeEnhanceExp(readEnhanceRules(world), definition.quality, 0);
          await addEnhanceExp(tx, playerId, gained);
          result.decomposed += 1;
          result.enhanceExp += gained;
          continue;
        }
        const freed = await freeOneSlot(tx, world, playerId);
        if (!freed) {
          result.dropped += 1;
          result.reason = "BAG_FULL";
          continue;
        }
        result.freed.push(freed);
        result.enhanceExp += freed.enhanceExp;
      }
    }
    if (stackRow) {
      await tx.update(playerItems).set({ quantity: stackRow.quantity + unit }).where(eq(playerItems.id, stackRow.id));
    } else {
      await insertRow(tx, playerId, itemSlug, !isGear, unit, source, now);
    }
    result.added += 1;
  }
  return result;
}
