import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import type { CombatSkill } from "./battle.js";
const bp = z.number().int().min(0).max(10000);
const effect = z.object({ kind: z.enum(["attack_up", "defense_down", "heal", "shield"]), valueBp: z.number().int().min(0).max(100000), durationSeconds: z.number().min(0.1).max(120).optional() });
const schema = z.object({
  skipAfterWin: z.boolean().default(true),
  speeds: z.array(z.union([z.literal(1), z.literal(2), z.literal(3)])).min(1).max(3).default([1,2,3]),
  statusDurationSeconds: z.number().min(0.1).max(120).default(3),
  fogTimeLimitSeconds: z.number().min(1).max(600).default(45),
  critChanceBp: bp.default(0), dodgeChanceBp: bp.default(0), critMultBp: z.number().int().min(10000).max(100000).default(15000),
  rage: z.object({ max: z.number().min(1).max(10000).default(100), onAttack: z.number().min(0).max(10000).default(20), onHit: z.number().min(0).max(10000).default(10), damageMultBp: z.number().int().min(0).max(100000).default(30000) }).prefault({}),
  skills: z.record(z.string(), z.object({ critChanceBp: bp.default(0), dodgeChanceBp: bp.default(0), effects: z.array(effect).max(4).default([]) })).default({}),
});
export type RuntimeCombatConfig = z.infer<typeof schema>;
export function runtimeConfigFromInput(raw: unknown): RuntimeCombatConfig {
  const result = schema.safeParse(raw ?? {});
  if (!result.success) throw new AppError("INVALID_INPUT", `战斗参数不合法：${result.error.issues.map(issue => issue.path.join(".") + " " + issue.message).join("；")}`);
  return result.data;
}
export function runtimeConfigOf(raw: unknown): RuntimeCombatConfig {
  const result = schema.safeParse(raw ?? {});
  return result.success ? result.data : schema.parse({});
}
export function configuredSkills(skills: CombatSkill[], config: RuntimeCombatConfig): CombatSkill[] {
  return skills.map(s => ({ ...s, effects: (config.skills[s.slug]?.effects ?? s.effects ?? []).map(e => ({ ...e, durationSeconds: e.durationSeconds ?? config.statusDurationSeconds })) }));
}
/** Current live stat model has attack/defense/hp/speed only. Optional existing side traits are preserved by callers; running-skill traits are additive. No hidden free crit/dodge is invented. */
export function combatTraits(skills: CombatSkill[], config: RuntimeCombatConfig) {
  return { critChanceBp: Math.min(10000, config.critChanceBp + skills.reduce((n,s) => n + (config.skills[s.slug]?.critChanceBp ?? 0), 0)), dodgeChanceBp: Math.min(10000, config.dodgeChanceBp + skills.reduce((n,s) => n + (config.skills[s.slug]?.dodgeChanceBp ?? 0), 0)), critMultBp: config.critMultBp };
}
