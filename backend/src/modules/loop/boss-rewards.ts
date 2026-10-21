import { eq, sql } from "drizzle-orm";
import type { Tx } from "../../db/tx.js";
import { playerItems, playerStates } from "../../db/schema.js";
import { ensureSkillBook } from "../content/ops-content.js";
import { dropMultsOf, rollGearPiece } from "../content/monster-drops.js";
import type { BossRuleSet } from "../content/boss-rules.js";
import { rollDropTable } from "../content/roll-drops.js";
import type { GameRules } from "../content/rules.js";
import type { ContentSnapshot } from "../content/validate.js";
import { rewardDayKey } from "../progress/day.js";
import { AppError } from "../../shared/errors.js";
import { grantItem } from "./bag.js";
import { grantEquipment, type GrantSource } from "../player/grant.js";

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
  /** 重复挑战这次有没有奖励。 */
  rewarded: boolean;
  /** 这次消耗了 1 次每日首领挑战总次数。 */
  countedDaily: boolean;
  /** 每日首领挑战总次数：今天已用 / 总数（所有首领合计）。 */
  dailyRewardCount: number;
  dailyRewardLimit: number;
  bagFull: boolean;
};

/** 新奖励模型：boss 配了首通固定奖励或重复挑战奖励，就不再走旧的掉落表/方案奖励。 */
export function usesRewardModel(boss: Boss | undefined): boolean {
  return Boolean(boss && ((boss.firstClear?.length ?? 0) > 0 || boss.repeat));
}

/** 每日首领挑战总次数今天用了几次（第四批：全局一份，存在 player_states；换天按北京时间 dayStartHour 点，和原来的每日次数一样）。 */
export function bossDailyUsed(state: { bossDailyCount: number; bossDailyDay: string | null }, rules: Pick<GameRules, "dayStartHour">, now: Date): number {
  return state.bossDailyDay === rewardDayKey(now, rules.dayStartHour) ? state.bossDailyCount : 0;
}

/** 「发放指定装备」的来源（ADMIN_SPEC §14）；首领这边只用这两个。 */
export type BossGearSource = Extract<GrantSource, "boss_first" | "boss_repeat">;

/**
 * 一场首领胜利的「战斗报告 id」（可重放）：玩家 + 关卡 + 这条进度记录的解锁时间 + 第几次胜利。
 * 带上解锁时间是因为后台「清空玩家」会删掉进度记录、clear_count 从 0 重来，不带的话清空后的胜利会撞上清空前的发放单号。
 */
export function bossBattleId(playerId: string, stageSlug: string, progress: { unlockedAt: Date; clearCount: number }): string {
  return `boss:${playerId}:${stageSlug}:${progress.unlockedAt.getTime()}:${progress.clearCount + 1}`;
}

/**
 * 首领给装备都走这一个函数（抽中之后调用）→ 统一发放接口 grantEquipment（ADMIN_SPEC §14）。
 * requestId = 战斗报告 id + 序号，同一场胜利重放不会重复发；写 equipment_grants 流水。
 * 第四批：主程序的 grantEquipment 行囊满时对 stage_drop / boss_first / boss_repeat 不发装备、返回 skipped: "bag_full"（不报错）。
 * 这里对返回值宽松读取：老版本返回发放的装备数组；新版本可能是数组上带 skipped，或 { items | granted, skipped } 对象。
 */
export async function grantBossEquipment(
  tx: Tx,
  input: { playerId: string; itemSlug: string; count: number; source: BossGearSource; stageSlug: string; battleId: string; index: number },
): Promise<{ count: number; skipped: string | null }> {
  const result = (await grantEquipment(tx, {
    playerId: input.playerId,
    itemId: input.itemSlug,
    count: input.count,
    source: input.source,
    sourceRef: input.stageSlug,
    requestId: `${input.battleId}:${input.index}`,
  })) as unknown;
  return readGrantResult(result);
}

/** grantEquipment 返回值 → 发了几件、有没有因为行囊满跳过（见上）。 */
export function readGrantResult(result: unknown): { count: number; skipped: string | null } {
  const record = (result ?? {}) as { skipped?: unknown; items?: unknown; granted?: unknown };
  const list = Array.isArray(result) ? result : Array.isArray(record.items) ? record.items : Array.isArray(record.granted) ? record.granted : [];
  const skipped = typeof record.skipped === "string" && record.skipped ? record.skipped : null;
  return { count: list.length, skipped };
}

/**
 * 首领胜利后的奖励（第四批：一套规则，见 content/boss-rules.ts，全局默认 + 单关覆盖）：
 * - 首通（还没击败过）：首领的 firstClear 固定奖励（物品 / 功法书 / 修为 / 灵石 / 按「首通装备品质」抽装备），允许暂时超出行囊容量；不算每日次数。
 * - 重复（已击败过：手动重打 mode = manual，挂机刷出来的 mode = idle）：规则「重复奖励」开着才有 repeat 奖励
 *   （装备按「重复奖励装备品质」抽 + 额外物品各自掷；额外物品走行囊规则；装备走统一发放接口，行囊满照发、来源 boss_repeat）。
 *   手动重打一定算「每日首领挑战总次数」；挂机首领看「挂机首领算每日次数」开关（默认不算 = 不消耗、次数用完照样有奖励）。
 *   要算次数的：今天没用完就消耗 1 次给奖励；用完了照样能打，但没有奖励。
 * 日期按北京时间、每天 dayStartHour 点换天。
 */
export async function grantBossRewards(
  tx: Tx,
  world: World,
  playerId: string,
  input: {
    stage: Stage;
    boss: Boss;
    progress: { unlockedAt: Date; firstClearedAt: Date | null; clearCount: number; dailyRewardCount: number; dailyRewardDay: string | null };
    rules: GameRules;
    bossRules: BossRuleSet;
    /** 每日首领挑战总次数（全局）。 */
    dailyTotal: number;
    /** manual = 手动挑战 / 自动挑战（没击败过的）；idle = 挂机刷出来的首领。 */
    mode: "manual" | "idle";
    /** 挂机首领的战斗编号（同一次结算里第几只），requestId 用；手动的不传。 */
    battleId?: string;
    autoDecompose: boolean;
    capacity: number;
    now: Date;
    randomInt: RandomInt;
  },
): Promise<BossRewardOutcome> {
  const { stage, boss, progress, rules, bossRules, now } = input;
  const outcome: BossRewardOutcome = { drops: [], cultivation: 0, spiritStones: 0, firstClear: !progress.firstClearedAt, rewarded: false, countedDaily: false, dailyRewardCount: 0, dailyRewardLimit: input.dailyTotal, bagFull: false };
  const source = `drop:${stage.slug}`;
  const battleId = input.battleId ?? bossBattleId(playerId, stage.slug, progress);
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
  /** 按首领规则的装备品质掉率（首通 / 重复各一组）抽一件本境界阶装备并发放。 */
  const rollAndGrant = async (kind: BossGearSource, index: number) => {
    const pct = kind === "boss_first" ? bossRules.gearQualityPct : bossRules.repeatGearQualityPct;
    if (!majorKey) {
      throw new AppError("INVALID_INPUT", `关卡「${stage.displayName ?? stage.slug}」的境界没有大境界编号，发不了装备`);
    }
    const piece = rollGearPiece(majorKey, pct, input.randomInt, multOf);
    if (!piece) {
      return;
    }
    if (!world.items.some((item) => item.slug === piece.slug)) {
      throw new AppError("INVALID_INPUT", `装备 ${piece.slug} 不在后台，发不了`);
    }
    const granted = await grantBossEquipment(tx, { playerId, itemSlug: piece.slug, count: 1, source: kind, stageSlug: stage.slug, battleId, index });
    if (granted.skipped) {
      // 行囊满（主程序 grantEquipment 跳过）：这件没发，客户端显示「行囊已满」
      outcome.drops.push({ itemSlug: piece.slug, quantity: 0, dropped: true });
      outcome.bagFull = true;
      return;
    }
    outcome.drops.push({ itemSlug: piece.slug, quantity: granted.count });
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
          await rollAndGrant("boss_first", gearIndex);
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

  const [daily] = await tx.select({ bossDailyCount: playerStates.bossDailyCount, bossDailyDay: playerStates.bossDailyDay }).from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
  const used = daily ? bossDailyUsed(daily, rules, now) : 0;
  outcome.dailyRewardCount = used;
  if (!boss.repeat || !bossRules.repeatRewards) {
    return outcome;
  }
  const countsDaily = input.mode === "manual" || bossRules.idleSpawnCountsDaily;
  if (countsDaily) {
    if (used >= input.dailyTotal) {
      return outcome;
    }
    outcome.countedDaily = true;
    outcome.dailyRewardCount = used + 1;
    await tx
      .update(playerStates)
      .set({ bossDailyCount: used + 1, bossDailyDay: rewardDayKey(now, rules.dayStartHour) })
      .where(eq(playerStates.playerId, playerId));
  }
  outcome.rewarded = true;
  if (boss.repeat.gear && majorKey) {
    await rollAndGrant("boss_repeat", 0);
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
