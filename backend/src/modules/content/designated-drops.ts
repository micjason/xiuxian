import { contentItems } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { DESIGNATED_TRIGGERS, type DesignatedDrop, type DesignatedTrigger } from "./combat-types.js";

function textOf(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/** 指定掉落：装备 + 触发 + 概率（%）+ 件数。不传 = 保持原样；传空数组 = 清空。 */
export type DesignatedInput = { itemId?: string; trigger?: string; chancePercent?: number; count?: number }[] | null;

export const DESIGNATED_MAX = 20;

export function readDesignated(input: DesignatedInput | undefined, gear: Map<string, { kind: string | null; slot: string | null }>): DesignatedDrop[] | undefined {
  if (input === undefined) {
    return undefined;
  }
  if (input === null) {
    return [];
  }
  if (!Array.isArray(input) || input.length > DESIGNATED_MAX) {
    throw new AppError("INVALID_INPUT", `指定掉落最多 ${DESIGNATED_MAX} 条`);
  }
  const seen = new Set<string>();
  return input.map((row, index) => {
    const label = `指定掉落第 ${index + 1} 行`;
    const itemSlug = textOf(row?.itemId);
    const item = gear.get(itemSlug);
    if (!itemSlug || !item) {
      throw new AppError("INVALID_INPUT", `${label}：请选择装备`);
    }
    if (item.kind !== "equipment" || !item.slot) {
      throw new AppError("INVALID_INPUT", `${label}：只能选装备`);
    }
    const trigger = String(row?.trigger ?? "") as DesignatedTrigger;
    if (!(DESIGNATED_TRIGGERS as readonly string[]).includes(trigger)) {
      throw new AppError("INVALID_INPUT", `${label}：请选择触发时机`);
    }
    const key = `${itemSlug}:${trigger}`;
    if (seen.has(key)) {
      throw new AppError("INVALID_INPUT", `${label}：同一件装备、同一个触发时机只能有一条`);
    }
    seen.add(key);
    const percent = Number(row?.chancePercent);
    const chanceBp = Math.round(percent * 100);
    if (!Number.isFinite(percent) || chanceBp < 1 || chanceBp > 10000) {
      throw new AppError("INVALID_INPUT", `${label}：概率要在 0.01% 到 100% 之间`);
    }
    const count = Number(row?.count ?? 1);
    if (!Number.isInteger(count) || count < 1 || count > 10) {
      throw new AppError("INVALID_INPUT", `${label}：数量要在 1–10 件之间`);
    }
    return { itemSlug, trigger, chanceBp, count };
  });
}

export async function gearMap(db: Db) {
  const rows = await db.select({ slug: contentItems.slug, kind: contentItems.kind, slot: contentItems.slot }).from(contentItems);
  return new Map(rows.map((row) => [row.slug, row]));
}

