import { AppError } from "../../shared/errors.js";
import type { SkillSlotRule } from "./combat-types.js";

/** 一个玩家最多能开的技能栏位（防止误填）。 */
export const SKILL_SLOT_MAX = 6;

/** 没配置时：和以前一样，一开始就 3 个栏位。 */
export const DEFAULT_SKILL_SLOT_RULES: SkillSlotRule[] = [{ minRealmOrder: 0, slots: 3 }];

/** 库里存的规则 → 干净的规则（按境界排序；坏数据丢掉）；空 = 默认。 */
export function skillSlotRulesOf(raw: unknown): SkillSlotRule[] {
  const rows = Array.isArray(raw) ? raw : [];
  const clean = rows
    .map((row) => ({ minRealmOrder: Number((row as SkillSlotRule)?.minRealmOrder), slots: Number((row as SkillSlotRule)?.slots) }))
    .filter((row) => Number.isInteger(row.minRealmOrder) && row.minRealmOrder >= 0 && Number.isInteger(row.slots) && row.slots >= 1 && row.slots <= SKILL_SLOT_MAX)
    .sort((left, right) => left.minRealmOrder - right.minRealmOrder);
  return clean.length > 0 ? clean : DEFAULT_SKILL_SLOT_RULES;
}

/** 这个境界（排序号）开放几个技能栏位：取 minRealmOrder ≤ 境界的规则里栏位最多的；一条都不满足 = 0。 */
export function openSkillSlots(rules: SkillSlotRule[] | undefined, realmOrder: number): number {
  let open = 0;
  for (const rule of skillSlotRulesOf(rules)) {
    if (realmOrder >= rule.minRealmOrder) {
      open = Math.max(open, rule.slots);
    }
  }
  return open;
}

/** 栏位上限（所有规则里最大的栏位数）。 */
export function maxSkillSlots(rules: SkillSlotRule[] | undefined): number {
  return Math.max(0, ...skillSlotRulesOf(rules).map((rule) => rule.slots));
}

/** 下一次开放：第一个栏位数比现在多的规则（没有 = null）。 */
export function nextSkillSlotRule(rules: SkillSlotRule[] | undefined, realmOrder: number): SkillSlotRule | null {
  const open = openSkillSlots(rules, realmOrder);
  return skillSlotRulesOf(rules).find((rule) => rule.minRealmOrder > realmOrder && rule.slots > open) ?? null;
}

/** 后台保存：校验后返回（境界排序号要存在；栏位数随境界不能变少；同一境界只能一条）。 */
export function skillSlotRulesFromInput(raw: unknown, realmOrders: number[]): SkillSlotRule[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new AppError("INVALID_INPUT", "技能栏位规则至少要有一条");
  }
  const known = new Set(realmOrders);
  const rows = raw.map((row, index) => {
    const minRealmOrder = Number((row as SkillSlotRule)?.minRealmOrder);
    const slots = Number((row as SkillSlotRule)?.slots);
    if (!Number.isInteger(minRealmOrder) || !known.has(minRealmOrder)) {
      throw new AppError("INVALID_INPUT", `技能栏位第 ${index + 1} 行：请选择开放境界`);
    }
    if (!Number.isInteger(slots) || slots < 1 || slots > SKILL_SLOT_MAX) {
      throw new AppError("INVALID_INPUT", `技能栏位第 ${index + 1} 行：栏位数要在 1–${SKILL_SLOT_MAX} 之间`);
    }
    return { minRealmOrder, slots };
  });
  rows.sort((left, right) => left.minRealmOrder - right.minRealmOrder);
  for (let index = 1; index < rows.length; index += 1) {
    if (rows[index]!.minRealmOrder === rows[index - 1]!.minRealmOrder) {
      throw new AppError("INVALID_INPUT", "技能栏位：同一个境界只能有一条规则");
    }
    if (rows[index]!.slots <= rows[index - 1]!.slots) {
      throw new AppError("INVALID_INPUT", "技能栏位：境界越高栏位数要越多");
    }
  }
  return rows;
}
