import { and, eq, sql } from "drizzle-orm";
import type { Tx } from "../../db/tx.js";
import { playerItems, playerStageProgress, playerStates } from "../../db/schema.js";
import { ensureSkillBook } from "../content/ops-content.js";
import { dropMultsOf, rollGearPiece } from "../content/monster-drops.js";
import type { BossRuleSet } from "../content/boss-rules.js";
import { rollDropTable } from "../content/roll-drops.js";
import type { GameRules } from "../content/rules.js";
import type { ContentSnapshot } from "../content/validate.js";
import { rewardDayKey } from "../progress/day.js";
import { AppError } from "../../shared/errors.js";
import { grantItem } from "./bag.js";

type World = ContentSnapshot & { version: number };
type Stage = ContentSnapshot["stages"][number];
type Boss = NonNullable<Stage["bosses"]>[number];
type RandomInt = (min: number, max: number) => number;

export type BossDrop = { itemSlug: string; quantity: number; designated?: boolean; decomposed?: boolean; enhanceExp?: number; dropped?: boolean; freed?: { itemSlug: string; enhanceExp: number }[] };

export type BossRewardOutcome = {
  drops: BossDrop[];
  /** 首通固定奖励里的修为（已入账）。 */
  cultivation: number;
  /** 首通固定奖励里的灵石（已入账）。 */
  spiritStones: number;
  firstClear: boolean;
  /** 重复挑战这次有没有奖励（今天前 N 次胜利才有）。 */
  rewarded: boolean;
  dailyRewardCount: number;
  dailyRewardLimit: number;
  bagFull: boolean;
};

/** 新奖励模型：boss 配了首通固定奖励或重复挑战奖励，就不再走旧的掉落表/方案奖励。 */
export function usesRewardModel(boss: Boss | undefined): boolean {
  return Boolean(boss && ((boss.firstClear?.length ?? 0) > 0 || boss.repeat));
}

export function dailyUsed(progress: { dailyRewardCount: number; dailyRewardDay: string | null }, rules: Pick<GameRules, "dayStartHour">, now: Date): number {
  return progress.dailyRewardDay === rewardDayKey(now, rules.dayStartHour) ? progress.dailyRewardCount : 0;
}

/** 「发放指定装备」的来源（ADMIN_SPEC §14）；首领这边只用这两个。 */
export type BossGearSource = "boss_first" | "boss_repeat";

/**
 * 首领给装备都走这一个函数（抽中之后调用）。
 * TODO(第二批统一发放接口)：独立开发超级大师的 backend/src/modules/player/grant.ts 合入后，换成
 *   grantEquipment(tx, { playerId, itemId: itemSlug, count, source, sourceRef: stageSlug, requestId })
 * （source = boss_first | boss_repeat，requestId 用下面算好的可重放值），这里先用 grantItem 顶着，行为和以前一样。
 */
export async function grantBossEquipment(
  tx: Tx,
  world: World,
  input: {
    playerId: string;
    itemSlug: string;
    count: number;
    source: BossGearSource;
    /** 关卡编号 */
    sourceRef: string;
    /** 幂等键：`${playerId}:${stageSlug}:${source}:${第几次胜利}:${第几件}`，同一次胜利重放不会重复发。 */
    requestId: string;
    now: Date;
    autoDecompose: boolean;
    capacity: number;
    overflow: boolean;
  },
) {
  return grantItem(tx, world, input.playerId, input.itemSlug, input.count, `drop:${input.sourceRef}`, input.now, {
    autoDecompose: input.autoDecompose,
    capacity: input.capacity,
    overflow: input.overflow,
  });
}

/**
 * 首领胜利后的奖励（第三批，规则见 content/boss-rules.ts，按首领档次 + 单关覆盖生效）：
 * - 首通：首领的 firstClear 固定奖励（物品 / 功法书 / 修为 / 灵石 / 按「装备品质掉率」抽装备），允许暂时超出行囊容量；不占每日次数。
 * - 重打：规则「重打给奖励」开着、每日次数 > 0 且今天没用完时，给 repeat 奖励（装备按「装备品质掉率」抽 + 额外物品各自掷），
 *   走行囊规则（满包自动分解 / 腾格 / 不掉）。用完了（或不给重打奖励）仍可打，但没有奖励。
 * 日期按北京时间、每天 dayStartHour 点换天。
 */
export async function grantBossRewards(
  tx: Tx,
  world: World,
  playerId: string,
  input: {
    stage: Stage;
    boss: Boss;
    progress: { firstClearedAt: Date | null; clearCount: number; dailyRewardCount: number; dailyRewardDay: string | null };
    rules: GameRules;
    bossRules: BossRuleSet;
    autoDecompose: boolean;
    capacity: number;
    now: Date;
    randomInt: RandomInt;
  },
): Promise<BossRewardOutcome> {
  const { stage, boss, progress, rules, bossRules, now } = input;
  const limit = bossRules.repeatRewards ? bossRules.dailyRewardLimit : 0;
  const outcome: BossRewardOutcome = { drops: [], cultivation: 0, spiritStones: 0, firstClear: !progress.firstClearedAt, rewarded: false, dailyRewardCount: 0, dailyRewardLimit: limit, bagFull: false };
  const source = `drop:${stage.slug}`;
  const win = progress.clearCount + 1;
  const record = (drop: BossDrop, granted: Awaited<ReturnType<typeof grantItem>>) => {
    if (granted.decomposed > 0) {
      drop.decomposed = true;
      drop.enhanceExp = granted.enhanceExp;
    }
    if (granted.freed.length > 0) {
      drop.freed = granted.freed;
      drop.enhanceExp = (drop.enhanceExp ?? 0) + granted.freed.reduce((sum, row) => sum + row.enhanceExp, 0);
    }
    if (granted.dropped > 0) {
      drop.dropped = true;
      outcome.bagFull = true;
    }
    outcome.drops.push(drop);
  };
  const put = async (itemSlug: string, quantity: number, overflow: boolean, designated = false) => {
    const skill = world.skills.find((row) => row.slug === itemSlug);
    if (skill) {
      const bookSlug = await ensureSkillBook(tx, { slug: skill.slug, displayName: skill.displayName ?? "名称缺失" }, null);
      await tx.insert(playerItems).values({ playerId, itemSlug: bookSlug, isStack: false, quantity: 1, source, acquiredAt: now });
      outcome.drops.push({ itemSlug: bookSlug, quantity: 1 });
      return;
    }
    if (!world.items.some((item) => item.slug === itemSlug)) {
      throw new AppError("INVALID_INPUT", "有一件奖励已经不在后台");
    }
    const granted = await grantItem(tx, world, playerId, itemSlug, quantity, source, now, { autoDecompose: input.autoDecompose, capacity: input.capacity, overflow });
    record(designated ? { itemSlug, quantity, designated: true } : { itemSlug, quantity }, granted);
  };
  const majorKey = world.realms.find((row) => row.sortOrder === stage.requiredRealmOrder)?.majorKey;
  const multOf = dropMultsOf(world.items, world.realms);
  /** 按首领规则的装备品质掉率抽一件本境界阶装备并发放。 */
  const rollAndGrant = async (kind: BossGearSource, index: number, overflow: boolean) => {
    if (!majorKey) {
      throw new AppError("INVALID_INPUT", `关卡「${stage.displayName ?? stage.slug}」的境界没有大境界编号，发不了装备`);
    }
    const piece = rollGearPiece(majorKey, bossRules.gearQualityPct, input.randomInt, multOf);
    if (!piece) {
      return;
    }
    if (!world.items.some((item) => item.slug === piece.slug)) {
      throw new AppError("INVALID_INPUT", `装备 ${piece.slug} 不在后台，发不了`);
    }
    const granted = await grantBossEquipment(tx, world, {
      playerId,
      itemSlug: piece.slug,
      count: 1,
      source: kind,
      sourceRef: stage.slug,
      requestId: `${playerId}:${stage.slug}:${kind}:${win}:${index}`,
      now,
      autoDecompose: input.autoDecompose,
      capacity: input.capacity,
      overflow,
    });
    record({ itemSlug: piece.slug, quantity: 1 }, granted);
  };

  /** 指定掉落（首领首通 / 首领有奖励的重打）：每条单独按概率抽。 */
  const rollDesignated = async (trigger: "boss_first" | "boss_repeat", overflow: boolean) => {
    for (const row of stage.designatedDrops ?? []) {
      if (row.trigger !== trigger || row.chanceBp <= 0 || !world.items.some((item) => item.slug === row.itemSlug)) {
        continue;
      }
      if (row.chanceBp < 10000 && input.randomInt(0, 10000) >= row.chanceBp) {
        continue;
      }
      await put(row.itemSlug, row.count, overflow, true);
    }
  };

  if (!progress.firstClearedAt) {
    let gearIndex = 0;
    for (const entry of boss.firstClear ?? []) {
      if (entry.kind === "cultivation") {
        outcome.cultivation += entry.amount;
      } else if (entry.kind === "spiritStones") {
        outcome.spiritStones += entry.amount;
      } else if (entry.kind === "gear") {
        for (let n = 0; n < entry.count; n += 1) {
          await rollAndGrant("boss_first", gearIndex, true);
          gearIndex += 1;
        }
      } else {
        await put(entry.itemSlug, entry.quantity, true);
      }
    }
    await rollDesignated("boss_first", true);
    if (outcome.cultivation > 0 || outcome.spiritStones > 0) {
      await tx
        .update(playerStates)
        .set({ cultivation: sql`${playerStates.cultivation} + ${outcome.cultivation}`, spiritStones: sql`${playerStates.spiritStones} + ${outcome.spiritStones}` })
        .where(eq(playerStates.playerId, playerId));
    }
    return outcome;
  }

  const used = dailyUsed(progress, rules, now);
  outcome.dailyRewardCount = used;
  if (!boss.repeat || limit <= 0 || used >= limit) {
    return outcome;
  }
  outcome.rewarded = true;
  outcome.dailyRewardCount = used + 1;
  await tx
    .update(playerStageProgress)
    .set({ dailyRewardCount: used + 1, dailyRewardDay: rewardDayKey(now, rules.dayStartHour) })
    .where(and(eq(playerStageProgress.playerId, playerId), eq(playerStageProgress.stageSlug, stage.slug)));
  if (boss.repeat.gear && majorKey) {
    await rollAndGrant("boss_repeat", 0, false);
  }
  const extras = rollDropTable(
    boss.repeat.extras.map((extra) => ({ itemSlug: extra.itemSlug, chanceBp: extra.chanceBp, minQty: extra.minQty, maxQty: extra.maxQty })),
    input.randomInt,
  );
  for (const extra of extras) {
    await put(extra.itemSlug, extra.quantity, false);
  }
  await rollDesignated("boss_repeat", false);
  return outcome;
}
