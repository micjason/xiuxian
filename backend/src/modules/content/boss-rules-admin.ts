/**
 * 首领规则的后台读写（第四批：一套规则）：配置概览「首领规则」（tuning.bossRules）和单关「恢复默认」。
 * 配置概览页的这一块是子组件 BossRulesSection.vue。
 */
import { eq } from "drizzle-orm";
import { contentGlobals, contentStages } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { BOSS_GLOBAL_KEYS, BOSS_GROUP_KEYS, BOSS_RULE_KEYS, DEFAULT_BOSS_RULES, bossRulesFromInput, customRuleCount, type BossRuleOverride, type BossRules } from "./boss-rules.js";
import { saveTuning } from "./config-overview.js";
import { loadDraftSnapshot } from "./snapshot.js";
import { tuningOf } from "./tuning.js";

/** 默认值 + 被几关使用、几关改过。 */
export async function readBossRules(db: Db) {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  const rules = tuningOf(row?.tuning).bossRules;
  const world = await loadDraftSnapshot(db);
  const stages = world.stages.filter((stage) => stage.bosses?.[0]);
  const customized = stages.filter((stage) => customRuleCount(stage.bosses?.[0]?.ruleOverride ?? null) > 0);
  const usage = {
    stages: stages.length,
    customized: customized.length,
    customizedStages: customized.map((stage) => ({ id: stage.slug, displayName: stage.displayName ?? stage.slug, customCount: customRuleCount(stage.bosses?.[0]?.ruleOverride ?? null) })),
  };
  return { rules, defaults: DEFAULT_BOSS_RULES, usage };
}

/** 保存首领规则：只合并传了的项（分组的按小项）；全部校验通过才写。 */
export async function saveBossRules(db: Db, input: Partial<Record<keyof BossRules, unknown>>, adminId: string | null) {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  if (!row) {
    throw new AppError("INVALID_INPUT", "请先新建境界");
  }
  const before = tuningOf(row.tuning).bossRules;
  const raw = (input ?? {}) as Record<string, unknown>;
  const known = [...BOSS_RULE_KEYS, ...BOSS_GLOBAL_KEYS] as string[];
  const merged: Record<string, unknown> = { ...before };
  for (const [key, value] of Object.entries(raw)) {
    if (!known.includes(key) || value === undefined || value === null) continue;
    merged[key] = (BOSS_GROUP_KEYS as readonly string[]).includes(key) ? { ...(before[key as keyof BossRules] as object), ...(value as object) } : value;
  }
  const rules = bossRulesFromInput(merged, before);
  await saveTuning(db, { bossRules: rules }, adminId);
  return readBossRules(db);
}

/** 单关首领规则恢复默认：keys 不传 = 全部；传了只恢复这几项（statMul / gearQualityPct 整组）。 */
export async function resetStageBossRule(db: Db, id: string, keys: unknown, adminId: string | null) {
  const [stage] = await db.select().from(contentStages).where(eq(contentStages.slug, id)).limit(1);
  if (!stage) {
    throw new AppError("NOT_FOUND", "没有这个关卡");
  }
  const bosses = stage.bosses ?? [];
  const first = bosses[0];
  if (!first) {
    throw new AppError("INVALID_INPUT", "这个关卡还没有首领");
  }
  let rules: BossRuleOverride | undefined;
  if (keys === undefined || keys === null) {
    rules = undefined;
  } else {
    if (!Array.isArray(keys) || keys.some((key) => !BOSS_RULE_KEYS.includes(key as never))) {
      throw new AppError("INVALID_INPUT", "要恢复的规则项不正确");
    }
    const kept = Object.fromEntries(Object.entries(first.rules ?? {}).filter(([key]) => !(keys as string[]).includes(key)));
    rules = Object.keys(kept).length > 0 ? (kept as BossRuleOverride) : undefined;
  }
  const next = { ...first };
  if (rules) {
    next.rules = rules;
  } else {
    delete next.rules;
  }
  await db.update(contentStages).set({ bosses: [next, ...bosses.slice(1)], updatedAt: new Date(), updatedBy: adminId }).where(eq(contentStages.slug, id));
  return { id, ruleOverride: next.rules ?? null };
}
