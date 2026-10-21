/**
 * 配置概览（后台「游戏配置 → 配置概览」）：一页看全所有默认数值。
 * - 战斗公式 / 挂机节奏 / 行囊离线：content_globals.combat 等（rules.ts）
 * - 默认掉率 / 品质权重 / 首领橙装概率、功法层数系数、自动分解、多余功法书折算：content_globals.tuning（tuning.ts）
 * - 强化与分解：content_globals.enhance（enhance.ts）
 * - 装备生成参数（预算比例、速度比例、品质系数、部位占比）只读摘要，在「装备配置」里改。
 */
import { eq } from "drizzle-orm";
import { contentGlobals, contentStages } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { enhanceRulesFromInput, readEnhanceView, saveEnhanceRules } from "./enhance.js";
import { gearQualityFactorsFromInput, gearSpeedFactorOf, readGearQualityFactors, syncGear } from "./gear.js";
import { readRules, rulesForSave, rulesFromInput, saveRules, type RulesInput } from "./rules.js";
import { compactDropOverride, customDropCount, resolveMonsterDrop } from "./stage-defaults.js";
import { DEFAULT_TUNING, tuningFromInput, tuningOf, type Tuning } from "./tuning.js";

async function globalsRow(db: Db) {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  return row ?? null;
}

export async function readTuning(db: Db): Promise<Tuning> {
  return tuningOf((await globalsRow(db))?.tuning);
}

/** 存 tuning（只合并传进来的项）。改了装备相关的项会重算 90 件装备。 */
export async function saveTuning(db: Db, input: Partial<Record<keyof Tuning, unknown>>, adminId: string | null): Promise<Tuning> {
  const row = await globalsRow(db);
  if (!row) {
    throw new AppError("INVALID_INPUT", "请先新建境界");
  }
  const before = tuningOf(row.tuning);
  const next = tuningFromInput({ ...before, ...stripUndefined(input) });
  await db.update(contentGlobals).set({ tuning: next, updatedAt: new Date(), updatedBy: adminId }).where(eq(contentGlobals.id, 1));
  if (next.gearBudgetRatio !== before.gearBudgetRatio || JSON.stringify(next.slotShares) !== JSON.stringify(before.slotShares)) {
    await syncGear(db, adminId);
  }
  return next;
}

function stripUndefined<T extends Record<string, unknown>>(input: T): Partial<T> {
  return Object.fromEntries(Object.entries(input ?? {}).filter(([, value]) => value !== undefined)) as Partial<T>;
}

/** 关卡继承情况：哪些关卡改过默认掉率 / 权重。 */
async function stageInheritance(db: Db, tuning: Tuning) {
  const stages = await db.select().from(contentStages);
  const rows = stages
    .sort((left, right) => left.requiredRealmOrder - right.requiredRealmOrder || left.displayName.localeCompare(right.displayName, "zh"))
    .map((stage) => ({
      id: stage.slug,
      displayName: stage.displayName,
      realmCode: stage.requiredRealmOrder,
      customCount: customDropCount(stage.monsterDrop),
      override: stage.monsterDrop ?? null,
      effective: resolveMonsterDrop(stage.monsterDrop, tuning),
    }));
  return { total: rows.length, customized: rows.filter((row) => row.customCount > 0) };
}

export async function readConfigOverview(db: Db) {
  const row = await globalsRow(db);
  const tuning = tuningOf(row?.tuning);
  return {
    rules: await readRules(db),
    tuning,
    tuningDefaults: DEFAULT_TUNING,
    enhance: await readEnhanceView(db),
    gear: {
      gearBudgetRatio: tuning.gearBudgetRatio,
      gearSpeedFactor: gearSpeedFactorOf(row?.combat?.gearSpeedFactor),
      slotShares: tuning.slotShares,
      qualityFactors: row ? await readGearQualityFactors(db) : null,
    },
    stages: await stageInheritance(db, tuning),
  };
}

/**
 * 配置概览一次保存：先全部校验，全部通过才写库（不会出现一半存上、一半报错）。
 * rules / tuning / enhance 都是可选的，只存传了的部分。
 */
export async function saveConfigOverview(
  db: Db,
  input: { rules?: RulesInput; tuning?: Partial<Record<keyof Tuning, unknown>>; enhance?: unknown },
  adminId: string | null,
) {
  const row = await globalsRow(db);
  if (!row) {
    throw new AppError("INVALID_INPUT", "请先新建境界");
  }
  if (input.rules) {
    rulesFromInput(rulesForSave(input.rules, row));
  }
  if (input.tuning) {
    tuningFromInput({ ...tuningOf(row.tuning), ...stripUndefined(input.tuning) });
  }
  if (input.enhance !== undefined) {
    enhanceRulesFromInput(input.enhance);
  }
  if (input.tuning) {
    await saveTuning(db, input.tuning, adminId);
  }
  if (input.enhance !== undefined) {
    await saveEnhanceRules(db, input.enhance, adminId);
  }
  if (input.rules) {
    await saveRules(db, input.rules, adminId);
  }
  return readConfigOverview(db);
}

/** 装备配置页「生成参数」一次保存：预算比例、速度比例、品质系数、部位占比，存完重算 90 件。 */
export async function saveGearParams(
  db: Db,
  input: { gearBudgetRatio?: unknown; gearSpeedFactor?: unknown; qualityFactors?: Record<string, unknown>; slotShares?: Record<string, unknown> },
  adminId: string | null,
) {
  const row = await globalsRow(db);
  if (!row) {
    throw new AppError("INVALID_INPUT", "请先新建境界");
  }
  const tuning = tuningFromInput({
    ...tuningOf(row.tuning),
    ...(input.gearBudgetRatio !== undefined ? { gearBudgetRatio: input.gearBudgetRatio } : {}),
    ...(input.slotShares !== undefined ? { slotShares: input.slotShares } : {}),
  });
  const speed = input.gearSpeedFactor === undefined ? gearSpeedFactorOf(row.combat?.gearSpeedFactor) : gearSpeedFactorOf(input.gearSpeedFactor);
  const factors = input.qualityFactors === undefined ? await readGearQualityFactors(db) : gearQualityFactorsFromInput(input.qualityFactors);
  await db
    .update(contentGlobals)
    .set({
      tuning,
      gearQualityFactors: factors,
      combat: { ...(row.combat ?? {}), gearSpeedFactor: speed },
      updatedAt: new Date(),
      updatedBy: adminId,
    })
    .where(eq(contentGlobals.id, 1));
  await syncGear(db, adminId);
  return { ok: true };
}

/** 把关卡掉落恢复成全部跟随默认。 */
export async function resetStageDrop(db: Db, id: string, adminId: string | null) {
  const [stage] = await db.select().from(contentStages).where(eq(contentStages.slug, id)).limit(1);
  if (!stage) {
    throw new AppError("NOT_FOUND", "没有这个关卡");
  }
  await db.update(contentStages).set({ monsterDrop: null, updatedAt: new Date(), updatedBy: adminId }).where(eq(contentStages.slug, id));
  return { id };
}

export { compactDropOverride };
