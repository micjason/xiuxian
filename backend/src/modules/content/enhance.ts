import { eq } from "drizzle-orm";
import { contentGlobals, contentItems } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import type { ContentSnapshot } from "./validate.js";
import { QUALITY_TABLE, type QualityKey } from "./catalog.js";

/**
 * 装备强化规则（强化经验 = 分解装备得到，用来给其他装备升强化等级）。
 * 规则存在 content_globals.enhance，后台可改；代码里读不到就报错，不会偷偷用默认值。
 * STARTING_ENHANCE_RULES 只在这几处出现：迁移 0016/0017 的初始数据（同一份数字）、后台的“填入建议起始值”按钮、数值方案和旧数据导入脚本。
 * 规则里的一切（等级上限、每级属性加成、经验曲线、突破节点和材料）都来自这份配置；强化经验池没有上限。
 * 所有数字都是起始值，等和客户确认后再调整，见 docs/design/enhance_rules_proposal.md。
 */
/** 强化规则按品质配置；品质来自统一品质表（catalog.ts，白→橙 5 档，红已去掉）。 */
export const ENHANCE_QUALITIES = QUALITY_TABLE.map((row) => ({ key: row.key, name: row.short }));

export type EnhanceQualityKey = QualityKey;

/** 校验用的合理范围，只防止填错（例如多写几个零把后台算崩），不是玩法数值；玩法数值全在规则里。 */
export const ENHANCE_LIMITS = { maxCap: 200, maxBreakCount: 9999 } as const;

export type BreakMaterial = { itemSlug: string; count: number };
/** 突破节点：装备强化到 level 级后，必须交齐 materials 才能继续升到 level+1 级。 */
export type BreakNode = { level: number; materials: BreakMaterial[] };

export type EnhanceQualityRule = {
  /** 强化等级上限 */
  cap: number;
  /** 这个品质每一级所需经验再乘以它 */
  costMult: number;
  /** 分解这个品质的装备（未强化）得到的基础经验 */
  decomposeExp: number;
  /** 可选：这个品质自己的经验增长倍数；不填则用通用的 expGrowth */
  expGrowth?: number;
  /** 可选：这个品质自己的每级属性加成（万分比）；不填则用通用的 statGrowthBp */
  statGrowthBp?: number;
  /** 突破节点（按等级从小到大）；没有就是空数组 */
  breakthroughs: BreakNode[];
};

export type EnhanceRules = {
  /** 强化 0→1 级所需经验（经验倍数为 1 时） */
  expBase: number;
  /** 每升一级，所需经验乘以这个倍数（品质可单独覆盖） */
  expGrowth: number;
  /** 每级强化给装备基础属性增加的万分比（品质可单独覆盖） */
  statGrowthBp: number;
  /** 分解已强化装备时，返还已投入经验的万分比 */
  refundBp: number;
  /** 强化经验池没有上限，所以这里也没有对应字段。 */
  qualities: Partial<Record<EnhanceQualityKey, EnhanceQualityRule>>;
  /**
   * 第五批（SPEC_Q §17.2 / 17.3）：分解得「炼器精粹」、强化消耗精粹。老快照没有这一项（迁移 0050 会补上）；
   * 缺了的话分解 / 强化报错「请先在后台填写炼器精粹」，其他照常。上面的 expBase / expGrowth / decomposeExp / refundBp
   * 是旧的「强化经验」规则，只留着给一次性迁移（强化经验 → 精粹）算比例，游戏不再用它们结算。
   */
  essence?: EssenceRules;
};

/** 装备部位（和 tuning.ts 的 TUNING_SLOTS 相同；这里单独写一份，免得 enhance.ts 依赖 tuning.ts）。 */
export const ESSENCE_SLOTS = ["weapon", "clothes", "helmet", "gloves", "shoes", "accessory"] as const;
export type EssenceSlot = (typeof ESSENCE_SLOTS)[number];

/** 大境界倍率键，与固定境界表 majorKey 一致（炼气 → 大乘）。 */
export const REALM_YIELD_MAJORS = ["qi", "foundation", "core", "nascent", "spirit", "void", "unity", "mahayana"] as const;
export type RealmYieldMajor = (typeof REALM_YIELD_MAJORS)[number];

/**
 * 默认大境界倍率。一口价 yields 是金丹档（×1）；炼气 / 筑基打折。
 * 元婴及以后还没有单独的精粹曲线，出厂先与金丹同为 1，后台可改。缺键仍用这张表。
 */
export const DEFAULT_REALM_YIELD_MULT: Record<RealmYieldMajor, number> = {
  qi: 0.25,
  foundation: 0.45,
  core: 1.0,
  nascent: 1.0,
  spirit: 1.0,
  void: 1.0,
  unity: 1.0,
  mahayana: 1.0,
};

export type EssenceRules = {
  /** 精粹对应的物品编号（可堆叠材料），默认 refine_essence。 */
  itemSlug: string;
  /** 分解一件未强化装备得到的精粹（按品质）——金丹档基准；再乘大境界倍率。 */
  yields: Record<EnhanceQualityKey, number>;
  /** 部位倍数（万分比，不填 = 10000 = 1 倍）：产出 = round(品质产出 × 大境界倍率 × 倍数)。 */
  slotMultBp: Partial<Record<EssenceSlot, number>>;
  /** 单独指定「某品质某部位」的产出（填了就不再乘部位倍数；绝对值，不再乘境界倍率）。 */
  slotOverrides: Partial<Record<EnhanceQualityKey, Partial<Record<EssenceSlot, number>>>>;
  /** 强化返还基础：每 1 级再 × 大境界倍率后取整（SPEC：返还 = 等级 × round(refundPerLevel × 倍率)）。 */
  refundPerLevel: number;
  /** 大境界倍率（金丹=1 = 一口价）。缺键或旧存档缺整表时用 DEFAULT_REALM_YIELD_MULT。 */
  realmYieldMult: Record<RealmYieldMajor, number>;
  /** 强化 0→1 级消耗的精粹（品质倍数 costMult 为 1 时）。 */
  costBase: number;
  /** 每升一级，消耗乘以这个倍数。 */
  costGrowth: number;
  /** 单独指定的每级消耗（下标 = 当前等级，即 +L → +L+1）；没填的等级按公式算。 */
  costTable: Partial<Record<EnhanceQualityKey, number[]>>;
  /** 一次性迁移：玩家剩余强化经验 × 这个万分比（向上取整）= 得到的精粹。 */
  migrationRatioBp: number;
};

/**
 * 起始精粹规则（后台可改）。品质一口价 白20/绿60/蓝150/紫400/橙1000 是**金丹档**基准；
 * 再乘大境界倍率（炼气 0.25 / 筑基 0.45 / 金丹 1.0），返还每级 40 也按同一倍率缩放。
 * 消耗 = round(40 × 1.25^级 × 品质倍数)，不跟境界走。详见 balance_research/essence_realm_tiers.md。
 */
export const STARTING_ESSENCE_RULES: EssenceRules = {
  itemSlug: "refine_essence",
  yields: { white: 20, green: 60, blue: 150, purple: 400, orange: 1000 },
  slotMultBp: {},
  slotOverrides: {},
  refundPerLevel: 40,
  realmYieldMult: { ...DEFAULT_REALM_YIELD_MULT },
  costBase: 40,
  costGrowth: 1.25,
  costTable: {},
  migrationRatioBp: 7000,
};

/** 精粹物品（迁移 0050 / 后台「填入建议起始值」时没有就创建）。 */
export const STARTING_ESSENCE_ITEM = {
  slug: "refine_essence",
  displayName: "炼器精粹",
  description: "分解装备得到，用来强化装备。",
  quality: "orange",
  iconKey: "refine_essence",
} as const;

/** 起始突破材料：后台“填入建议起始值”时如果物品里还没有，会一并创建。数字和名称都只是起始值。 */
export const STARTING_BREAK_MATERIALS = [
  { slug: "enh_stone_low", displayName: "突破石·下品", description: "装备强化到突破节点时消耗的材料。", quality: "green" },
  { slug: "enh_stone_mid", displayName: "突破石·中品", description: "装备强化到较高突破节点时消耗的材料。", quality: "blue" },
  { slug: "enh_stone_high", displayName: "突破石·上品", description: "装备强化到高阶突破节点时消耗的材料。", quality: "purple" },
] as const;

/** 起始值，全部可在后台改。 */
export const STARTING_ENHANCE_RULES: EnhanceRules = {
  expBase: 60,
  expGrowth: 1.25,
  statGrowthBp: 600,
  refundBp: 8000,
  qualities: {
    white: { cap: 5, costMult: 1, decomposeExp: 30, breakthroughs: [] },
    green: { cap: 8, costMult: 1.1, decomposeExp: 60, breakthroughs: [{ level: 5, materials: [{ itemSlug: "enh_stone_low", count: 3 }] }] },
    blue: { cap: 10, costMult: 1.25, decomposeExp: 120, breakthroughs: [{ level: 5, materials: [{ itemSlug: "enh_stone_low", count: 5 }] }] },
    purple: {
      cap: 12,
      costMult: 1.4,
      decomposeExp: 240,
      breakthroughs: [
        { level: 5, materials: [{ itemSlug: "enh_stone_low", count: 8 }] },
        { level: 10, materials: [{ itemSlug: "enh_stone_mid", count: 3 }] },
      ],
    },
    orange: {
      cap: 15,
      costMult: 1.6,
      decomposeExp: 480,
      breakthroughs: [
        { level: 5, materials: [{ itemSlug: "enh_stone_low", count: 10 }] },
        { level: 10, materials: [{ itemSlug: "enh_stone_mid", count: 6 }] },
      ],
    },
  },
  essence: STARTING_ESSENCE_RULES,
};

function positive(value: unknown, label: string, integer = false): number {
  if (value === undefined || value === null || value === "") {
    throw new AppError("INVALID_INPUT", `请填写${label}`);
  }
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) {
    throw new AppError("INVALID_INPUT", `${label}必须大于 0`);
  }
  if (integer && !Number.isInteger(number)) {
    throw new AppError("INVALID_INPUT", `${label}要填整数`);
  }
  return number;
}

function optionalPositive(value: unknown, label: string, integer = false): number | undefined {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }
  return positive(value, label, integer);
}

function breakNodesFromInput(input: unknown, label: string, cap: number): BreakNode[] {
  if (input === undefined || input === null) {
    return [];
  }
  if (!Array.isArray(input)) {
    throw new AppError("INVALID_INPUT", `${label}突破节点格式不正确`);
  }
  const nodes: BreakNode[] = [];
  for (const raw of input as Record<string, unknown>[]) {
    const level = positive(raw?.level, `${label}突破节点等级`, true);
    if (level >= cap) {
      throw new AppError("INVALID_INPUT", `${label}突破节点 +${level} 必须小于等级上限 +${cap}（到上限就不用再突破了）`);
    }
    if (nodes.some((node) => node.level === level)) {
      throw new AppError("INVALID_INPUT", `${label}突破节点 +${level} 重复了`);
    }
    const materialsRaw = Array.isArray(raw.materials) ? (raw.materials as Record<string, unknown>[]) : [];
    if (materialsRaw.length === 0) {
      throw new AppError("INVALID_INPUT", `${label}突破节点 +${level} 至少要有一种材料`);
    }
    const materials: BreakMaterial[] = [];
    for (const material of materialsRaw) {
      const itemSlug = typeof material?.itemSlug === "string" ? material.itemSlug.trim() : "";
      if (!itemSlug) {
        throw new AppError("INVALID_INPUT", `${label}突破节点 +${level} 有一行没选材料`);
      }
      if (materials.some((row) => row.itemSlug === itemSlug)) {
        throw new AppError("INVALID_INPUT", `${label}突破节点 +${level} 的材料 ${itemSlug} 重复了`);
      }
      const count = positive(material.count, `${label}突破节点 +${level} 的材料数量`, true);
      if (count > ENHANCE_LIMITS.maxBreakCount) {
        throw new AppError("INVALID_INPUT", `${label}突破节点 +${level} 的材料数量不能超过 ${ENHANCE_LIMITS.maxBreakCount}`);
      }
      materials.push({ itemSlug, count });
    }
    nodes.push({ level, materials });
  }
  return nodes.sort((left, right) => left.level - right.level);
}

/**
 * 解析强化规则。requireAll 为真（后台保存、发布校验）时 6 个品质都必须填；
 * 为假（运行时读已发布快照）时允许缺品质——老快照没有红色规则，只是红色装备不能强化，其他照常。
 */
export function enhanceRulesFromInput(input: unknown, options: { requireAll?: boolean } = {}): EnhanceRules {
  const requireAll = options.requireAll ?? true;
  if (typeof input !== "object" || input === null) {
    throw new AppError("INVALID_INPUT", "请先在后台填写强化规则");
  }
  const raw = input as Record<string, unknown>;
  const qualitiesRaw = (raw.qualities ?? {}) as Record<string, Record<string, unknown> | undefined>;
  const qualities: EnhanceRules["qualities"] = {};
  for (const quality of ENHANCE_QUALITIES) {
    const row = qualitiesRaw[quality.key];
    if (row === undefined && !requireAll) {
      continue;
    }
    const label = `${quality.name}品质`;
    const cap = positive(row?.cap, `${label}强化上限`, true);
    if (cap > ENHANCE_LIMITS.maxCap) {
      throw new AppError("INVALID_INPUT", `${label}强化上限不能超过 ${ENHANCE_LIMITS.maxCap}`);
    }
    const expGrowth = optionalPositive(row?.expGrowth, `${label}经验增长倍数`);
    if (expGrowth !== undefined && expGrowth < 1) {
      throw new AppError("INVALID_INPUT", `${label}经验增长倍数不能小于 1`);
    }
    const rule: EnhanceQualityRule = {
      cap,
      costMult: positive(row?.costMult, `${label}经验倍数`),
      decomposeExp: positive(row?.decomposeExp, `${label}分解经验`, true),
      breakthroughs: breakNodesFromInput(row?.breakthroughs, label, cap),
    };
    if (expGrowth !== undefined) {
      rule.expGrowth = expGrowth;
    }
    const statGrowthBp = optionalPositive(row?.statGrowthBp, `${label}每级属性加成`, true);
    if (statGrowthBp !== undefined) {
      rule.statGrowthBp = statGrowthBp;
    }
    qualities[quality.key] = rule;
  }
  const refundBp = Number(raw.refundBp);
  if (!Number.isFinite(refundBp) || refundBp < 0 || refundBp > 10000) {
    throw new AppError("INVALID_INPUT", "分解返还比例要在 0 到 10000 之间");
  }
  const expGrowth = positive(raw.expGrowth, "经验增长倍数");
  if (expGrowth < 1) {
    throw new AppError("INVALID_INPUT", "经验增长倍数不能小于 1");
  }
  const rules: EnhanceRules = {
    expBase: positive(raw.expBase, "基础经验", true),
    expGrowth,
    statGrowthBp: positive(raw.statGrowthBp, "每级属性加成", true),
    refundBp,
    qualities,
  };
  if (raw.essence !== undefined && raw.essence !== null) {
    rules.essence = essenceRulesFromInput(raw.essence);
  }
  return rules;
}

function nonNegativeInt(value: unknown, label: string, max = 100_000_000): number {
  const number = Number(value);
  if (value === undefined || value === null || value === "" || !Number.isInteger(number) || number < 0 || number > max) {
    throw new AppError("INVALID_INPUT", `${label}要填 0 到 ${max} 的整数`);
  }
  return number;
}

/** 炼器精粹规则校验（后台保存 / 运行时读快照都用这一个）。 */
export function essenceRulesFromInput(input: unknown): EssenceRules {
  if (typeof input !== "object" || input === null) {
    throw new AppError("INVALID_INPUT", "炼器精粹规则格式不正确");
  }
  const raw = input as Record<string, unknown>;
  const itemSlug = typeof raw.itemSlug === "string" ? raw.itemSlug.trim() : "";
  if (!itemSlug) {
    throw new AppError("INVALID_INPUT", "请选择炼器精粹对应的物品");
  }
  const yieldsRaw = (raw.yields ?? {}) as Record<string, unknown>;
  const yields = Object.fromEntries(ENHANCE_QUALITIES.map((q) => [q.key, nonNegativeInt(yieldsRaw[q.key], `${q.name}品质分解产出`)])) as EssenceRules["yields"];
  const slotMultBp: EssenceRules["slotMultBp"] = {};
  const multRaw = (raw.slotMultBp ?? {}) as Record<string, unknown>;
  for (const slot of ESSENCE_SLOTS) {
    const value = multRaw[slot];
    if (value !== undefined && value !== null && value !== "") {
      slotMultBp[slot] = nonNegativeInt(value, "部位产出倍数", 1_000_000);
    }
  }
  const slotOverrides: EssenceRules["slotOverrides"] = {};
  const overRaw = (raw.slotOverrides ?? {}) as Record<string, Record<string, unknown> | undefined>;
  for (const q of ENHANCE_QUALITIES) {
    for (const slot of ESSENCE_SLOTS) {
      const value = overRaw[q.key]?.[slot];
      if (value !== undefined && value !== null && value !== "") {
        (slotOverrides[q.key] ??= {})[slot] = nonNegativeInt(value, `${q.name}品质单独指定的部位产出`);
      }
    }
  }
  const costTable: EssenceRules["costTable"] = {};
  const tableRaw = (raw.costTable ?? {}) as Record<string, unknown>;
  for (const q of ENHANCE_QUALITIES) {
    const list = tableRaw[q.key];
    if (list === undefined || list === null) {
      continue;
    }
    if (!Array.isArray(list)) {
      throw new AppError("INVALID_INPUT", `${q.name}品质的每级消耗表格式不正确`);
    }
    // 空格子（null / ""）= 这一级按公式；填了就必须 ≥ 1。
    const levels = list.map((value) => (value === null || value === "" || value === undefined ? null : positive(value, `${q.name}品质每级精粹消耗`, true)));
    while (levels.length > 0 && levels[levels.length - 1] === null) {
      levels.pop();
    }
    if (levels.length > 0) {
      costTable[q.key] = levels as number[];
    }
  }
  const costGrowth = positive(raw.costGrowth, "精粹消耗增长倍数");
  if (costGrowth < 1) {
    throw new AppError("INVALID_INPUT", "精粹消耗增长倍数不能小于 1");
  }
  const realmYieldMult = realmYieldMultFromInput(raw.realmYieldMult);
  return {
    itemSlug,
    yields,
    slotMultBp,
    slotOverrides,
    refundPerLevel: nonNegativeInt(raw.refundPerLevel, "每级强化返还"),
    realmYieldMult,
    costBase: positive(raw.costBase, "强化基础精粹消耗", true),
    costGrowth,
    costTable,
    migrationRatioBp: nonNegativeInt(raw.migrationRatioBp, "强化经验转精粹比例", 10_000_000),
  };
}

/** 读大境界倍率；缺整表或缺键时用默认（旧存档兼容）。倍率必须 > 0。 */
export function realmYieldMultFromInput(input: unknown): Record<RealmYieldMajor, number> {
  const out: Record<RealmYieldMajor, number> = { ...DEFAULT_REALM_YIELD_MULT };
  if (typeof input !== "object" || input === null) {
    return out;
  }
  const raw = input as Record<string, unknown>;
  for (const key of REALM_YIELD_MAJORS) {
    const value = raw[key];
    if (value === undefined || value === null || value === "") {
      continue;
    }
    const number = Number(value);
    if (!Number.isFinite(number) || number <= 0) {
      throw new AppError("INVALID_INPUT", `大境界「${key}」精粹倍率必须大于 0`);
    }
    out[key] = number;
  }
  return out;
}

/** 大境界中文名 → 倍率键。固定表用语义键（qi / nascent / …），旧数据也可能是 major1。 */
export const MAJOR_NAME_TO_YIELD_KEY: Record<string, RealmYieldMajor> = {
  炼气: "qi",
  筑基: "foundation",
  金丹: "core",
  元婴: "nascent",
  化神: "spirit",
  炼虚: "void",
  合体: "unity",
  大乘: "mahayana",
};

/**
 * 把装备所在境界解析成倍率键。
 * 优先 majorName；其次 majorKey 已是语义键；否则 null（调用方按炼气兜底）。
 */
export function resolveRealmYieldMajor(
  realm: { majorKey?: string | null; majorName?: string | null } | null | undefined,
): RealmYieldMajor | null {
  if (!realm) return null;
  const byName = realm.majorName ? MAJOR_NAME_TO_YIELD_KEY[realm.majorName] : undefined;
  if (byName) return byName;
  if (realm.majorKey && (REALM_YIELD_MAJORS as readonly string[]).includes(realm.majorKey)) {
    return realm.majorKey as RealmYieldMajor;
  }
  return null;
}

/**
 * 取装备大境界对应的精粹倍率。
 * major 可以是语义键（qi … mahayana），或直接把 resolveRealmYieldMajor 的结果传进来。
 * 缺 / 未知 → 按炼气并打日志（决策稿 §5）。
 */
export function realmYieldMultOf(essence: EssenceRules, major: string | null | undefined): number {
  if (major && (REALM_YIELD_MAJORS as readonly string[]).includes(major)) {
    return essence.realmYieldMult[major as RealmYieldMajor] ?? DEFAULT_REALM_YIELD_MULT[major as RealmYieldMajor];
  }
  if (major) {
    console.warn(`[essence] unknown major=${major}, fallback qi`);
  } else {
    console.warn("[essence] missing major, fallback qi");
  }
  return essence.realmYieldMult.qi ?? DEFAULT_REALM_YIELD_MULT.qi;
}

/** 突破材料必须是后台里存在的、可堆叠的非装备物品。返回问题列表（空表示没问题）。 */
export function breakMaterialProblems(rules: EnhanceRules, items: { slug: string; kind: string | null; enabled?: boolean }[]): string[] {
  const problems: string[] = [];
  for (const quality of ENHANCE_QUALITIES) {
    for (const node of rules.qualities[quality.key]?.breakthroughs ?? []) {
      for (const material of node.materials) {
        const item = items.find((row) => row.slug === material.itemSlug);
        if (!item) {
          problems.push(`${quality.name}品质 +${node.level} 突破：材料 ${material.itemSlug} 在物品里不存在`);
        } else if (item.kind === "equipment" || item.kind === "skill_book") {
          problems.push(`${quality.name}品质 +${node.level} 突破：材料 ${material.itemSlug} 不能是装备或技能书`);
        } else if (item.enabled === false) {
          problems.push(`${quality.name}品质 +${node.level} 突破：材料 ${material.itemSlug} 已停用`);
        }
      }
    }
  }
  return problems;
}

/** 发布快照里的强化规则；缺了就报错。运行时读取允许缺品质（见 enhanceRulesFromInput）。 */
export function readEnhanceRules(world: ContentSnapshot): EnhanceRules {
  const stored = world.globals.enhance;
  if (!stored) {
    throw new AppError("INVALID_INPUT", "请先在后台填写：强化规则");
  }
  return enhanceRulesFromInput(stored, { requireAll: false });
}

export function qualityKeyOf(quality: string | null | undefined): EnhanceQualityKey {
  const found = ENHANCE_QUALITIES.find((row) => row.key === quality);
  if (!found) {
    throw new AppError("INVALID_INPUT", "这件装备的品质不能强化");
  }
  return found.key;
}

export function qualityRule(rules: EnhanceRules, quality: string | null | undefined): EnhanceQualityRule {
  const key = qualityKeyOf(quality);
  const row = rules.qualities[key];
  if (!row) {
    const name = ENHANCE_QUALITIES.find((item) => item.key === key)?.name ?? key;
    throw new AppError("INVALID_INPUT", `还没有${name}品质的强化规则，请在后台「装备强化」填写并重新发布`);
  }
  return row;
}

export function enhanceCap(rules: EnhanceRules, quality: string | null | undefined): number {
  return qualityRule(rules, quality).cap;
}

/** 这个品质实际使用的每级经验增长倍数。 */
export function expGrowthOf(rules: EnhanceRules, quality: string | null | undefined): number {
  return qualityRule(rules, quality).expGrowth ?? rules.expGrowth;
}

/** 这个品质实际使用的每级属性加成（万分比）。quality 为空时用通用值。 */
export function statGrowthOf(rules: EnhanceRules, quality?: string | null): number {
  if (quality === undefined || quality === null) {
    return rules.statGrowthBp;
  }
  return qualityRule(rules, quality).statGrowthBp ?? rules.statGrowthBp;
}

/** 从 level 级升到 level+1 级要多少强化经验。 */
export function enhanceCost(rules: EnhanceRules, quality: string | null | undefined, level: number): number {
  const row = qualityRule(rules, quality);
  return Math.max(1, Math.round(rules.expBase * (row.expGrowth ?? rules.expGrowth) ** level * row.costMult));
}

/** 从 0 级升到 level 级一共投入了多少经验。 */
export function enhanceInvested(rules: EnhanceRules, quality: string | null | undefined, level: number): number {
  let total = 0;
  for (let step = 0; step < level; step += 1) {
    total += enhanceCost(rules, quality, step);
  }
  return total;
}

/** 强化后的单项属性：基础值 × (1 + 等级 × 每级加成)。传 quality 时使用这个品质自己的每级加成。 */
export function enhancedStat(base: number, level: number, rules: EnhanceRules, quality?: string | null): number {
  return Math.round(base * (1 + (level * statGrowthOf(rules, quality)) / 10000) * 100) / 100;
}

/** 分解一件装备得到的强化经验：品质基础值 + 已投入经验的返还。已穿戴的装备不能分解（由调用方保证）。 */
export function decomposeEnhanceExp(rules: EnhanceRules, quality: string | null | undefined, level: number): number {
  const base = qualityRule(rules, quality).decomposeExp;
  return base + Math.floor((enhanceInvested(rules, quality, level) * rules.refundBp) / 10000);
}

/**
 * 装备现在卡在哪个突破节点：强化等级正好等于节点等级、而且这个节点还没突破过（brokenLevel 小于它）。
 * 没卡住返回 null。等级已经超过节点的老装备不受影响（节点是后加的话，不会倒逼玩家补突破）。
 */
export function pendingBreakNode(rules: EnhanceRules, quality: string | null | undefined, level: number, brokenLevel: number): BreakNode | null {
  const row = qualityRule(rules, quality);
  return row.breakthroughs.find((node) => node.level === level && node.level > brokenLevel && node.level < row.cap) ?? null;
}

/** 从当前等级往上看，下一个还没突破的节点（含正卡着的），用于界面提示“下一个突破节点”。 */
export function nextBreakNode(rules: EnhanceRules, quality: string | null | undefined, level: number, brokenLevel: number): BreakNode | null {
  const row = qualityRule(rules, quality);
  return row.breakthroughs.find((node) => node.level >= level && node.level > brokenLevel && node.level < row.cap) ?? null;
}

/** 炼器精粹规则；快照里没有就报错（迁移 0050 会补上，后台「装备强化」也能填）。 */
export function essenceRules(rules: EnhanceRules): EssenceRules {
  if (!rules.essence) {
    throw new AppError("INVALID_INPUT", "请先在后台「装备强化」填写炼器精粹规则并重新发布");
  }
  return rules.essence;
}

/**
 * 分解一件装备得到的精粹（决策稿 essence_realm_tiers）：
 *   round(品质基础 × 大境界倍率 × 部位倍数) + 强化等级 × round(refundPerLevel × 同倍率)
 * 单独指定的部位产出（override）是绝对值，不再乘境界倍率。缺 majorKey → 炼气并打日志。
 * 已穿戴的不能分解（调用方保证）。
 */
export function essenceYield(
  rules: EnhanceRules,
  quality: string | null | undefined,
  slot: string | null | undefined,
  level: number,
  majorKey?: string | null,
): number {
  const essence = essenceRules(rules);
  const key = qualityKeyOf(quality);
  const slotKey = slot as EssenceSlot;
  const realmMult = realmYieldMultOf(essence, majorKey);
  const override = essence.slotOverrides[key]?.[slotKey];
  const base =
    override ?? Math.round((essence.yields[key] * realmMult * (essence.slotMultBp[slotKey] ?? 10000)) / 10000);
  const refund = Math.round(essence.refundPerLevel * realmMult);
  return base + Math.max(0, level) * refund;
}

/** 从 level 级升到 level+1 级要多少精粹：先看单独指定的表，没有就按公式 round(基础 × 增长^级 × 品质倍数)。 */
export function essenceCost(rules: EnhanceRules, quality: string | null | undefined, level: number): number {
  const essence = essenceRules(rules);
  const row = qualityRule(rules, quality);
  const fixed = essence.costTable[qualityKeyOf(quality)]?.[level];
  if (typeof fixed === "number" && fixed > 0) {
    return fixed;
  }
  return Math.max(1, Math.round(essence.costBase * essence.costGrowth ** level * row.costMult));
}

/** 一次性迁移：剩余强化经验 → 精粹（向上取整）。 */
export function migratedEssence(rules: EnhanceRules, enhanceExp: number): number {
  if (enhanceExp <= 0) {
    return 0;
  }
  return Math.ceil((enhanceExp * essenceRules(rules).migrationRatioBp) / 10000);
}

/**
 * 「没人变弱」的最低迁移比例（万分比，向上取整）：所有品质、所有等级里「精粹消耗 / 旧经验消耗」的最大值。
 * 迁移比例 ≥ 它时，旧经验能买的任何一串升级，换成精粹后也一定买得起（每一级都不更贵，加起来也不更贵）。后台用它提示。
 */
export function minSafeMigrationRatioBp(rules: EnhanceRules): number {
  let worst = 0;
  for (const quality of ENHANCE_QUALITIES) {
    const row = rules.qualities[quality.key];
    if (!row) {
      continue;
    }
    for (let level = 0; level < row.cap; level += 1) {
      worst = Math.max(worst, essenceCost(rules, quality.key, level) / enhanceCost(rules, quality.key, level));
    }
  }
  return Math.ceil(worst * 10000);
}

export async function readEnhanceView(db: Db) {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  const rules = row?.enhance ?? null;
  let minSafeRatioBp: number | null;
  try {
    minSafeRatioBp = rules?.essence ? minSafeMigrationRatioBp(enhanceRulesFromInput(rules, { requireAll: false })) : null;
  } catch {
    minSafeRatioBp = null;
  }
  return { rules, starting: STARTING_ENHANCE_RULES, startingMaterials: STARTING_BREAK_MATERIALS, essenceItem: STARTING_ESSENCE_ITEM, minSafeRatioBp };
}

export async function saveEnhanceRules(db: Db, input: unknown, adminId: string | null) {
  const rules = enhanceRulesFromInput(input);
  const [current] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  if (!current) {
    throw new AppError("INVALID_INPUT", "请先新建境界");
  }
  let items = await db.select({ slug: contentItems.slug, kind: contentItems.kind, enabled: contentItems.enabled }).from(contentItems);
  // 用到“起始突破材料”但物品里还没有时，一并创建（只创建这三个约定好的编号，其他材料必须自己先建好）。
  const used = new Set(ENHANCE_QUALITIES.flatMap((quality) => (rules.qualities[quality.key]?.breakthroughs ?? []).flatMap((node) => node.materials.map((row) => row.itemSlug))));
  const created: string[] = [];
  for (const starter of STARTING_BREAK_MATERIALS) {
    if (used.has(starter.slug) && !items.some((item) => item.slug === starter.slug)) {
      await db.insert(contentItems).values({
        slug: starter.slug,
        displayName: starter.displayName,
        description: starter.description,
        kind: "material",
        quality: starter.quality,
        stackable: true,
        updatedBy: adminId,
      });
      created.push(starter.slug);
    }
  }
  if (rules.essence?.itemSlug === STARTING_ESSENCE_ITEM.slug && !items.some((item) => item.slug === STARTING_ESSENCE_ITEM.slug)) {
    await db.insert(contentItems).values({
      slug: STARTING_ESSENCE_ITEM.slug,
      displayName: STARTING_ESSENCE_ITEM.displayName,
      description: STARTING_ESSENCE_ITEM.description,
      kind: "material",
      quality: STARTING_ESSENCE_ITEM.quality,
      iconKey: STARTING_ESSENCE_ITEM.iconKey,
      stackable: true,
      updatedBy: adminId,
    });
    created.push(STARTING_ESSENCE_ITEM.slug);
  }
  if (created.length > 0) {
    items = await db.select({ slug: contentItems.slug, kind: contentItems.kind, enabled: contentItems.enabled }).from(contentItems);
  }
  const problems = breakMaterialProblems(rules, items);
  if (rules.essence) {
    const item = items.find((row) => row.slug === rules.essence?.itemSlug);
    if (!item) {
      problems.push(`炼器精粹物品 ${rules.essence.itemSlug} 在物品里不存在`);
    } else if (item.kind === "equipment" || item.kind === "skill_book") {
      problems.push(`炼器精粹物品 ${rules.essence.itemSlug} 不能是装备或技能书`);
    }
  }
  if (problems.length > 0) {
    throw new AppError("INVALID_INPUT", problems[0] ?? "突破材料不正确", { problems });
  }
  await db.update(contentGlobals).set({ enhance: rules, updatedAt: new Date(), updatedBy: adminId }).where(eq(contentGlobals.id, 1));
  return { ...(await readEnhanceView(db)), createdMaterials: created };
}
