/**
 * 洞府 v1 · 关卡种子掉落（开发二号）。
 * - 全局默认：content_globals.tuning.seedDrops（配置概览「种子掉落」）
 * - 单关覆盖：content_stages.seed_drops；null/缺省 = 用全局；[] = 本关不掉；非空 = 用这份
 * - 每只普通怪击杀独立掷一次（与指定掉落同频）；可堆叠材料走 grantItem / addStack
 * - 字段统一用 itemSlug（= content_items.slug）；后台表单里的 itemId 也是 slug
 */
import { AppError } from "../../shared/errors.js";

export type SeedDropEntry = {
  /** content_items.slug，例如 seed_lingcao */
  itemSlug: string;
  /** 万分比 0..10000 */
  chanceBp: number;
  minCount: number;
  maxCount: number;
};

/** 后台表单行（概率用百分比，itemId = slug）。 */
export type SeedDropInputRow = {
  itemId?: string;
  itemSlug?: string;
  chancePercent?: number;
  chanceBp?: number;
  minCount?: number;
  maxCount?: number;
};

export const SEED_DROP_MAX = 20;
export const SEED_DROP_COUNT_MAX = 99;

/** 出厂全局默认：灵草 / 清心 两种种子。概率可在配置概览改。 */
export const DEFAULT_SEED_DROPS: SeedDropEntry[] = [
  { itemSlug: "seed_lingcao", chanceBp: 800, minCount: 1, maxCount: 1 },
  { itemSlug: "seed_qingxin", chanceBp: 400, minCount: 1, maxCount: 1 },
];

/** 洞府约定的种子 / 草药 / 丹药编号（迁移 0047 写入；已有不覆盖）。 */
export const DONGFU_ITEM_STUBS = [
  { slug: "seed_lingcao", displayName: "灵草种子", description: "药园种植，成熟后收获灵草。", kind: "material", quality: "green", iconKey: "seed_lingcao" },
  { slug: "seed_qingxin", displayName: "清心草种子", description: "药园种植，成熟后收获清心草。", kind: "material", quality: "blue", iconKey: "seed_qingxin" },
  { slug: "herb_lingcao", displayName: "灵草", description: "药园产出，炼丹材料。", kind: "material", quality: "green", iconKey: "herb_lingcao" },
  { slug: "herb_qingxin", displayName: "清心草", description: "药园产出，炼丹材料。", kind: "material", quality: "blue", iconKey: "herb_qingxin" },
  { slug: "pill_cultivate", displayName: "修为丹", description: "使用后增加修为或短时加快修炼（洞府炼丹）。", kind: "pill", quality: "green", iconKey: "pill_cultivate" },
  { slug: "pill_atk_temp", displayName: "攻击临时丹", description: "战斗中临时提升攻击（洞府炼丹）。", kind: "pill", quality: "blue", iconKey: "pill_atk_temp" },
  { slug: "pill_def_temp", displayName: "防御临时丹", description: "战斗中临时提升防御（洞府炼丹）。", kind: "pill", quality: "blue", iconKey: "pill_def_temp" },
] as const;

function textOf(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function intOf(value: unknown, label: string, min: number, max: number): number {
  const n = Number(value);
  if (!Number.isInteger(n) || n < min || n > max) {
    throw new AppError("INVALID_INPUT", `${label}要在 ${min}–${max} 的整数`);
  }
  return n;
}

/** 严格校验一条列表（保存用）。items 里要有对应 slug；允许任意可堆叠材料/丹药，不限种子。 */
export function seedDropsFromInput(
  raw: unknown,
  options: { knownSlugs?: Set<string>; label?: string } = {},
): SeedDropEntry[] {
  const label = options.label ?? "种子掉落";
  if (raw === undefined || raw === null) {
    return [];
  }
  if (!Array.isArray(raw)) {
    throw new AppError("INVALID_INPUT", `${label}格式不正确`);
  }
  if (raw.length > SEED_DROP_MAX) {
    throw new AppError("INVALID_INPUT", `${label}最多 ${SEED_DROP_MAX} 条`);
  }
  const seen = new Set<string>();
  return raw.map((row, index) => {
    const rowLabel = `${label}第 ${index + 1} 行`;
    const input = (row ?? {}) as SeedDropInputRow;
    const itemSlug = textOf(input.itemSlug) || textOf(input.itemId);
    if (!itemSlug) {
      throw new AppError("INVALID_INPUT", `${rowLabel}：请选择物品`);
    }
    if (options.knownSlugs && !options.knownSlugs.has(itemSlug)) {
      throw new AppError("INVALID_INPUT", `${rowLabel}：物品「${itemSlug}」不存在`);
    }
    if (seen.has(itemSlug)) {
      throw new AppError("INVALID_INPUT", `${rowLabel}：「${itemSlug}」重复了`);
    }
    seen.add(itemSlug);
    let chanceBp: number;
    if (input.chanceBp !== undefined && input.chanceBp !== null && String(input.chanceBp) !== "") {
      chanceBp = intOf(input.chanceBp, `${rowLabel}：概率（万分比）`, 0, 10000);
    } else {
      const percent = Number(input.chancePercent);
      if (!Number.isFinite(percent)) {
        throw new AppError("INVALID_INPUT", `${rowLabel}：请填写概率`);
      }
      chanceBp = Math.round(percent * 100);
      if (chanceBp < 0 || chanceBp > 10000) {
        throw new AppError("INVALID_INPUT", `${rowLabel}：概率要在 0%–100% 之间`);
      }
    }
    const minCount = intOf(input.minCount ?? 1, `${rowLabel}：最少数量`, 1, SEED_DROP_COUNT_MAX);
    const maxCount = intOf(input.maxCount ?? minCount, `${rowLabel}：最多数量`, minCount, SEED_DROP_COUNT_MAX);
    return { itemSlug, chanceBp, minCount, maxCount };
  });
}

/** 宽松读取（运行时）：坏行丢弃，整表坏了回退默认。 */
export function seedDropsOf(raw: unknown, fallback: SeedDropEntry[] = DEFAULT_SEED_DROPS): SeedDropEntry[] {
  try {
    if (raw === undefined || raw === null) {
      return fallback.map((row) => ({ ...row }));
    }
    if (!Array.isArray(raw)) {
      return fallback.map((row) => ({ ...row }));
    }
    const out: SeedDropEntry[] = [];
    for (const row of raw) {
      try {
        const [one] = seedDropsFromInput([row]);
        if (one) out.push(one);
      } catch {
        /* skip bad row */
      }
    }
    return out;
  } catch {
    return fallback.map((row) => ({ ...row }));
  }
}

/**
 * 合并全局 + 单关覆盖。
 * - override == null / undefined → 用全局
 * - override == [] → 本关明确不掉
 * - override 非空 → 用覆盖表
 */
export function resolveSeedDrops(override: SeedDropEntry[] | null | undefined, globalDrops: SeedDropEntry[]): SeedDropEntry[] {
  if (override === null || override === undefined) {
    return globalDrops.map((row) => ({ ...row }));
  }
  return override.map((row) => ({ ...row }));
}

/** 后台：null = 跟随全局；传数组（可空）= 覆盖。undefined = 不改。 */
export function readSeedDropOverride(input: unknown): SeedDropEntry[] | null | undefined {
  if (input === undefined) {
    return undefined;
  }
  if (input === null) {
    return null;
  }
  return seedDropsFromInput(input, { label: "关卡种子掉落" });
}

export type RandomInt = (min: number, max: number) => number;

/** 一只怪的击杀：对生效表逐条独立掷骰，返回要发放的 {itemSlug, quantity}。 */
export function rollSeedDropsForKill(entries: SeedDropEntry[], randomInt: RandomInt): { itemSlug: string; quantity: number }[] {
  const grants: { itemSlug: string; quantity: number }[] = [];
  for (const entry of entries) {
    if (entry.chanceBp <= 0) continue;
    if (entry.chanceBp < 10000 && randomInt(0, 10000) >= entry.chanceBp) continue;
    const quantity =
      entry.minCount === entry.maxCount ? entry.minCount : randomInt(entry.minCount, entry.maxCount + 1);
    if (quantity > 0) grants.push({ itemSlug: entry.itemSlug, quantity });
  }
  return grants;
}
