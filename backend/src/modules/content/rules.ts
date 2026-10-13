import { eq } from "drizzle-orm";
import { contentGlobals, contentRealms } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import type { ContentSnapshot } from "./validate.js";

export type GameRules = {
  offlineCapSeconds: number;
  bagCapacity: number;
  powerWeights: { attack: number; defense: number; hp: number; speed: number };
  minInterval: number;
  challengeCooldownSeconds: number;
  timeLimitSeconds: number;
  defenseConstant: number;
  speedBase: number;
  recommendedPowerMargin: number;
};

export type RulesInput = {
  offlineCapSeconds?: number;
  bagCapacity?: number;
  attackWeight?: number;
  defenseWeight?: number;
  hpWeight?: number;
  speedWeight?: number;
  minInterval?: number;
  challengeCooldownSeconds?: number;
  timeLimitSeconds?: number;
  defenseConstant?: number;
  speedBase?: number;
  recommendedPowerMargin?: number;
};

const fields = [
  ["offlineCapSeconds", "离线上限", false],
  ["bagCapacity", "行囊容量", false],
  ["attackWeight", "攻击权重", true],
  ["defenseWeight", "防御权重", true],
  ["hpWeight", "气血权重", true],
  ["speedWeight", "速度权重", true],
  ["minInterval", "最短出手间隔", false],
  ["challengeCooldownSeconds", "挑战冷却", true],
  ["timeLimitSeconds", "单场时限", false],
  ["defenseConstant", "防御常数 k", false],
  ["speedBase", "速度基数", false],
  ["recommendedPowerMargin", "推荐战力倍数", false],
] as const;

function numberOf(value: unknown, label: string, allowZero: boolean): number {
  if (value === undefined || value === null || value === "") {
    throw new AppError("INVALID_INPUT", `请填写${label}`);
  }
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || (!allowZero && number === 0)) {
    throw new AppError("INVALID_INPUT", allowZero ? `${label}不能小于 0` : `${label}必须大于 0`);
  }
  return number;
}

export function rulesForSave(
  input: RulesInput,
  stored: {
    offlineCapSeconds: number | null;
    bagCapacity: number | null;
    combat: { challengeCooldownSeconds?: number; timeLimitSeconds?: number; recommendedPowerMargin?: number } | null;
  } | null,
): RulesInput {
  return {
    ...input,
    offlineCapSeconds: input.offlineCapSeconds ?? stored?.offlineCapSeconds ?? undefined,
    bagCapacity: input.bagCapacity ?? stored?.bagCapacity ?? undefined,
    challengeCooldownSeconds: input.challengeCooldownSeconds ?? stored?.combat?.challengeCooldownSeconds,
    timeLimitSeconds: input.timeLimitSeconds ?? stored?.combat?.timeLimitSeconds,
    recommendedPowerMargin: input.recommendedPowerMargin ?? stored?.combat?.recommendedPowerMargin,
  };
}

export function rulesFromInput(input: RulesInput): GameRules {
  const values = Object.fromEntries(fields.map(([key, label, allowZero]) => [key, numberOf(input[key], label, allowZero)])) as Record<
    (typeof fields)[number][0],
    number
  >;
  if (!Number.isInteger(values.bagCapacity)) {
    throw new AppError("INVALID_INPUT", "行囊容量要填整数");
  }
  if (!Number.isInteger(values.offlineCapSeconds)) {
    throw new AppError("INVALID_INPUT", "离线上限要填整数");
  }
  return {
    offlineCapSeconds: values.offlineCapSeconds,
    bagCapacity: values.bagCapacity,
    powerWeights: {
      attack: values.attackWeight,
      defense: values.defenseWeight,
      hp: values.hpWeight,
      speed: values.speedWeight,
    },
    minInterval: values.minInterval,
    challengeCooldownSeconds: values.challengeCooldownSeconds,
    timeLimitSeconds: values.timeLimitSeconds,
    defenseConstant: values.defenseConstant,
    speedBase: values.speedBase,
    recommendedPowerMargin: values.recommendedPowerMargin,
  };
}

function rulesInputOf(world: ContentSnapshot): RulesInput {
  const combat = world.globals.combat;
  const weights = world.globals.powerWeights;
  return {
    offlineCapSeconds: world.globals.offlineCapSeconds,
    bagCapacity: world.globals.bagCapacity,
    attackWeight: weights?.attack,
    defenseWeight: weights?.defense,
    hpWeight: weights?.hp,
    speedWeight: weights?.speed,
    minInterval: combat?.minInterval,
    challengeCooldownSeconds: combat?.challengeCooldownSeconds,
    timeLimitSeconds: combat?.timeLimitSeconds,
    defenseConstant: combat?.defenseConstant,
    speedBase: combat?.speedBase,
    recommendedPowerMargin: combat?.recommendedPowerMargin,
  };
}

export function readGameRules(world: ContentSnapshot): GameRules {
  const input = rulesInputOf(world);
  const missing = fields
    .filter(([key, , allowZero]) => {
      const value = input[key];
      if (value === undefined || value === null || !Number.isFinite(Number(value))) {
        return true;
      }
      const number = Number(value);
      return number < 0 || (!allowZero && number === 0);
    })
    .map(([, label]) => label);
  if (missing.length > 0) {
    throw new AppError("INVALID_INPUT", `请先在后台填写：${missing.join("、")}`);
  }
  return rulesFromInput(input);
}

export function rulesView(row: typeof contentGlobals.$inferSelect | null) {
  const combat = row?.combat;
  const weights = row?.powerWeights;
  return {
    offlineCapSeconds: row?.offlineCapSeconds ?? null,
    bagCapacity: row?.bagCapacity ?? null,
    attackWeight: weights?.attack ?? null,
    defenseWeight: weights?.defense ?? null,
    hpWeight: weights?.hp ?? null,
    speedWeight: weights?.speed ?? null,
    minInterval: combat?.minInterval ?? null,
    challengeCooldownSeconds: combat?.challengeCooldownSeconds ?? null,
    timeLimitSeconds: combat?.timeLimitSeconds ?? null,
    defenseConstant: combat?.defenseConstant ?? null,
    speedBase: combat?.speedBase ?? null,
    recommendedPowerMargin: combat?.recommendedPowerMargin ?? null,
  };
}

export async function readRules(db: Db) {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  return rulesView(row ?? null);
}

export async function saveRules(db: Db, input: RulesInput, adminId: string | null) {
  const [current] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  const rules = rulesFromInput(rulesForSave(input, current ?? null));
  const values = {
    id: 1,
    offlineCapSeconds: rules.offlineCapSeconds,
    bagCapacity: rules.bagCapacity,
    powerWeights: rules.powerWeights,
    combat: {
      minInterval: rules.minInterval,
      challengeCooldownSeconds: rules.challengeCooldownSeconds,
      timeLimitSeconds: rules.timeLimitSeconds,
      defenseConstant: rules.defenseConstant,
      speedBase: rules.speedBase,
      recommendedPowerMargin: rules.recommendedPowerMargin,
    },
    updatedAt: new Date(),
    updatedBy: adminId,
  };
  if (current) {
    await db.update(contentGlobals).set(values).where(eq(contentGlobals.id, 1));
  } else {
    const realms = await db.select().from(contentRealms);
    if (realms.length === 0) {
      throw new AppError("INVALID_INPUT", "请先新建境界");
    }
    const start = realms.reduce((smallest, row) => (row.sortOrder < smallest.sortOrder ? row : smallest));
    await db.insert(contentGlobals).values({ ...values, startingRealmSlug: start.slug });
  }
  return readRules(db);
}
