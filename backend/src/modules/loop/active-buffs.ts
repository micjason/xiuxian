/**
 * 临时属性丹 buff（洞府 v1 · 开发二号）。
 * 表 player_active_buffs 与洞府经营开发 0060 一致；本模块负责：
 * - applyActiveBuff：落库（供 useItem / 洞府 applyPillUse 调用）
 * - 读取未过期行，同 buffStat 的 buffBp **相加**，乘算到战斗攻防
 */
import { and, eq, gt } from "drizzle-orm";
import type { Tx } from "../../db/tx.js";
import { playerActiveBuffs } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import { computePower } from "../combat/stats.js";
import { readGameRules } from "../content/rules.js";
import type { ContentSnapshot } from "../content/validate.js";

export const BUFF_STATS = ["attack", "defense"] as const;
export type BuffStat = (typeof BUFF_STATS)[number];

export type ActiveBuffRow = {
  id: string;
  buffStat: string;
  buffBp: number;
  startedAt: Date;
  expiresAt: Date;
  sourceItemSlug: string;
};

export type BuffTotals = { attackBp: number; defenseBp: number };

export type PillEffect = {
  cultivationGain?: number;
  buffStat?: string;
  buffBp?: number;
  durationSeconds?: number;
};

export function isBuffStat(value: unknown): value is BuffStat {
  return value === "attack" || value === "defense";
}

/** 洞府 / useItem 写入一条生效 buff。同属性多条并存，结算时相加（不替换）。 */
export async function applyActiveBuff(
  tx: Tx,
  input: {
    playerId: string;
    buffStat: string;
    buffBp: number;
    durationSeconds: number;
    sourceItemSlug: string;
    now: Date;
  },
): Promise<ActiveBuffRow> {
  if (!isBuffStat(input.buffStat)) {
    throw new AppError("INVALID_INPUT", "临时属性只能是 attack 或 defense");
  }
  if (!Number.isInteger(input.buffBp) || input.buffBp <= 0 || input.buffBp > 100_000) {
    throw new AppError("INVALID_INPUT", "buffBp 要在 1–100000（万分比）");
  }
  if (!Number.isFinite(input.durationSeconds) || input.durationSeconds <= 0 || input.durationSeconds > 86400 * 30) {
    throw new AppError("INVALID_INPUT", "durationSeconds 不合法");
  }
  const sourceItemSlug = String(input.sourceItemSlug ?? "").trim();
  if (!sourceItemSlug) {
    throw new AppError("INVALID_INPUT", "缺少 sourceItemSlug");
  }
  const [row] = await tx
    .insert(playerActiveBuffs)
    .values({
      playerId: input.playerId,
      buffStat: input.buffStat,
      buffBp: input.buffBp,
      startedAt: input.now,
      expiresAt: new Date(input.now.getTime() + input.durationSeconds * 1000),
      sourceItemSlug,
    })
    .returning();
  return row!;
}

/** 未过期的 buff 行（expires_at > now）。 */
export async function listActiveBuffs(tx: Tx, playerId: string, now: Date): Promise<ActiveBuffRow[]> {
  return tx
    .select()
    .from(playerActiveBuffs)
    .where(and(eq(playerActiveBuffs.playerId, playerId), gt(playerActiveBuffs.expiresAt, now)));
}

/** 同属性 buffBp 相加。 */
export function sumActiveBuffs(rows: ActiveBuffRow[]): BuffTotals {
  let attackBp = 0;
  let defenseBp = 0;
  for (const row of rows) {
    if (row.buffStat === "attack") attackBp += row.buffBp;
    else if (row.buffStat === "defense") defenseBp += row.buffBp;
  }
  return { attackBp, defenseBp };
}

export async function loadBuffTotals(tx: Tx, playerId: string, now: Date): Promise<BuffTotals> {
  return sumActiveBuffs(await listActiveBuffs(tx, playerId, now));
}

type CombatStats = {
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  interval: number;
  power: number;
  bonusBp: number;
  sets?: unknown;
};

/** 把万分比加成乘到攻防，并按当前规则重算战力 / 出手间隔。 */
export function applyBuffsToStats(stats: CombatStats, totals: BuffTotals, world: ContentSnapshot): CombatStats {
  if (totals.attackBp === 0 && totals.defenseBp === 0) {
    return stats;
  }
  const attack = stats.attack * (1 + totals.attackBp / 10000);
  const defense = stats.defense * (1 + totals.defenseBp / 10000);
  const rules = readGameRules(world);
  const combat = computePower({
    attack,
    defense,
    hp: stats.hp,
    speed: stats.speed,
    baseInterval: rules.baseInterval,
    minInterval: rules.minInterval,
    speedBase: rules.speedBase,
    weights: rules.powerWeights,
  });
  return { ...stats, attack, defense, interval: combat.interval, power: combat.power };
}

/** 客户端展示用：剩余秒数（向下取整，至少 0）。 */
export function activeBuffsDto(rows: ActiveBuffRow[], now: Date) {
  return rows.map((row) => ({
    id: row.id,
    buffStat: row.buffStat,
    buffBp: row.buffBp,
    sourceItemSlug: row.sourceItemSlug,
    startedAt: row.startedAt,
    expiresAt: row.expiresAt,
    remainingSeconds: Math.max(0, Math.floor((row.expiresAt.getTime() - now.getTime()) / 1000)),
  }));
}

/** 校验后台 / 物品 effect 字段。undefined = 不改；null = 清空。 */
export function pillEffectFromInput(raw: unknown): PillEffect | null | undefined {
  if (raw === undefined) return undefined;
  if (raw === null || raw === "") return null;
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw new AppError("INVALID_INPUT", "丹药效果格式不正确");
  }
  const obj = raw as Record<string, unknown>;
  const out: PillEffect = {};
  if (obj.cultivationGain !== undefined && obj.cultivationGain !== null && obj.cultivationGain !== "") {
    const n = Number(obj.cultivationGain);
    if (!Number.isInteger(n) || n < 1 || n > 1_000_000_000) {
      throw new AppError("INVALID_INPUT", "修为增益要在 1–1000000000");
    }
    out.cultivationGain = n;
  }
  if (obj.buffStat !== undefined && obj.buffStat !== null && obj.buffStat !== "") {
    if (!isBuffStat(obj.buffStat)) {
      throw new AppError("INVALID_INPUT", "临时属性只能是 attack 或 defense");
    }
    out.buffStat = obj.buffStat;
  }
  if (obj.buffBp !== undefined && obj.buffBp !== null && obj.buffBp !== "") {
    const n = Number(obj.buffBp);
    if (!Number.isInteger(n) || n < 1 || n > 100_000) {
      throw new AppError("INVALID_INPUT", "buffBp 要在 1–100000");
    }
    out.buffBp = n;
  }
  if (obj.durationSeconds !== undefined && obj.durationSeconds !== null && obj.durationSeconds !== "") {
    const n = Number(obj.durationSeconds);
    if (!Number.isInteger(n) || n < 1 || n > 86400 * 30) {
      throw new AppError("INVALID_INPUT", "持续秒数不合法");
    }
    out.durationSeconds = n;
  }
  const hasCult = out.cultivationGain != null;
  const hasBuff = out.buffStat != null || out.buffBp != null || out.durationSeconds != null;
  if (hasBuff) {
    if (!out.buffStat || out.buffBp == null || out.durationSeconds == null) {
      throw new AppError("INVALID_INPUT", "临时属性丹要同时填 buffStat、buffBp、durationSeconds");
    }
  }
  if (!hasCult && !hasBuff) {
    return null;
  }
  return out;
}
