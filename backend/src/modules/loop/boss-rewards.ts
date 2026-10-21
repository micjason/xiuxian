import { and, eq, sql } from "drizzle-orm";
import type { Tx } from "../../db/tx.js";
import { playerItems, playerStageProgress, playerStates } from "../../db/schema.js";
import { ensureSkillBook } from "../content/ops-content.js";
import { dropMultsOf, rollBossRepeatGear } from "../content/monster-drops.js";
import { bossOrangeChanceBp } from "../content/stage-defaults.js";
import { tuningOf } from "../content/tuning.js";
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

export function dailyUsed(progress: { dailyRewardCount: number; dailyRewardDay: string | null }, rules: GameRules, now: Date): number {
  return progress.dailyRewardDay === rewardDayKey(now, rules.dayStartHour) ? progress.dailyRewardCount : 0;
}

/**
 * 首领胜利后的奖励（设计表 2.6）：
 * - 首通：固定奖励（物品、功法书、修为），允许暂时超出行囊容量；首通不占每日奖励次数。
 * - 之后每天前 bossDailyRewardCount 次胜利：本境界阶装备 1 件（品质权重同本区域，白色并入绿色）+ 额外物品按各自概率掷；
 *   这些走行囊规则（满包自动分解 / 腾格 / 不掉）。超过次数仍可打，但没有奖励。
 * 日期按北京时间、每天 dayStartHour 点换天。
 */
export async function grantBossRewards(
  tx: Tx,
  world: World,
  playerId: string,
  input: {
    stage: Stage;
    boss: Boss;
    progress: { firstClearedAt: Date | null; dailyRewardCount: number; dailyRewardDay: string | null };
    rules: GameRules;
    autoDecompose: boolean;
    capacity: number;
    now: Date;
    randomInt: RandomInt;
  },
): Promise<BossRewardOutcome> {
  const { stage, boss, progress, rules, now } = input;
  const outcome: BossRewardOutcome = { drops: [], cultivation: 0, firstClear: !progress.firstClearedAt, rewarded: false, dailyRewardCount: 0, dailyRewardLimit: rules.bossDailyRewardCount, bagFull: false };
  const source = `drop:${stage.slug}`;
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
    const drop: BossDrop = designated ? { itemSlug, quantity, designated: true } : { itemSlug, quantity };
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
    for (const entry of boss.firstClear ?? []) {
      if (entry.kind === "cultivation") {
        outcome.cultivation += entry.amount;
      } else {
        await put(entry.itemSlug, entry.quantity, true);
      }
    }
    await rollDesignated("boss_first", true);
    if (outcome.cultivation > 0) {
      await tx.update(playerStates).set({ cultivation: sqlAdd(outcome.cultivation) }).where(eq(playerStates.playerId, playerId));
    }
    return outcome;
  }

  const used = dailyUsed(progress, rules, now);
  outcome.dailyRewardCount = used;
  if (!boss.repeat || used >= rules.bossDailyRewardCount) {
    return outcome;
  }
  outcome.rewarded = true;
  outcome.dailyRewardCount = used + 1;
  await tx
    .update(playerStageProgress)
    .set({ dailyRewardCount: used + 1, dailyRewardDay: rewardDayKey(now, rules.dayStartHour) })
    .where(and(eq(playerStageProgress.playerId, playerId), eq(playerStageProgress.stageSlug, stage.slug)));
  const majorKey = world.realms.find((row) => row.sortOrder === stage.requiredRealmOrder)?.majorKey;
  if (boss.repeat.gear && majorKey && stage.monsterDrop) {
    const orangeBp = bossOrangeChanceBp(boss.repeat, world.globals.tuning ?? tuningOf(null));
    const piece = rollBossRepeatGear(majorKey, stage.monsterDrop.qualityWeights, orangeBp, input.randomInt, dropMultsOf(world.items, world.realms));
    if (piece && world.items.some((item) => item.slug === piece.slug)) {
      await put(piece.slug, 1, false);
    }
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

function sqlAdd(amount: number) {
  return sql`${playerStates.cultivation} + ${amount}`;
}
