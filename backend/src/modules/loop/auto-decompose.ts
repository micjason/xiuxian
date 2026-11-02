/**
 * 挂机自动分解：玩家在设置里勾选要自动拆的品质（白/绿/蓝/紫/橙）。
 * 默认白绿蓝勾上、紫橙不勾；掉落时品质在列表里 → 直接变炼器精粹，不进包。
 */
import type { GrantSource } from "../player/grant.js";

export const AUTO_DECOMPOSE_QUALITY_KEYS = ["white", "green", "blue", "purple", "orange"] as const;
export type AutoDecomposeQuality = (typeof AUTO_DECOMPOSE_QUALITY_KEYS)[number];

/** 新号 / 空配置时的默认勾选：白绿蓝。 */
export const DEFAULT_AUTO_DECOMPOSE_QUALITIES: AutoDecomposeQuality[] = ["white", "green", "blue"];

/** 只有挂机 / 关卡 / 首领掉落会自动拆；后台补发、邮件、洞府锻造等照常进包。 */
export const AUTO_DECOMPOSE_GRANT_SOURCES: readonly GrantSource[] = ["stage_drop", "boss_first", "boss_repeat"];

export function isAutoDecomposeGrantSource(source: GrantSource): boolean {
  return (AUTO_DECOMPOSE_GRANT_SOURCES as readonly string[]).includes(source);
}

/** 清洗玩家勾选：只留合法品质、去重、按白→橙排序。非法输入整段丢弃后用默认。 */
export function normalizeAutoDecomposeQualities(input: unknown): AutoDecomposeQuality[] {
  if (!Array.isArray(input)) {
    return [...DEFAULT_AUTO_DECOMPOSE_QUALITIES];
  }
  const allowed = new Set<string>(AUTO_DECOMPOSE_QUALITY_KEYS);
  const seen = new Set<AutoDecomposeQuality>();
  for (const raw of input) {
    if (typeof raw !== "string") {
      continue;
    }
    const key = raw.trim().toLowerCase();
    if (!allowed.has(key)) {
      continue;
    }
    seen.add(key as AutoDecomposeQuality);
  }
  return AUTO_DECOMPOSE_QUALITY_KEYS.filter((key) => seen.has(key));
}

export function qualitiesInclude(qualities: readonly string[], quality: string | null | undefined): boolean {
  if (!quality) {
    return false;
  }
  return qualities.includes(quality);
}
