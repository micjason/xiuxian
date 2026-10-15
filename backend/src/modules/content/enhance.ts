import { eq } from "drizzle-orm";
import { contentGlobals, contentItems } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import type { ContentSnapshot } from "./validate.js";

/**
 * 装备强化规则（强化经验 = 分解装备得到，用来给其他装备升强化等级）。
 * 规则存在 content_globals.enhance，后台可改；代码里读不到就报错，不会偷偷用默认值。
 * STARTING_ENHANCE_RULES 只在这几处出现：迁移 0016/0017 的初始数据（同一份数字）、后台的“填入建议起始值”按钮、数值方案和旧数据导入脚本。
 * 规则里的一切（等级上限、每级属性加成、经验曲线、突破节点和材料）都来自这份配置；强化经验池没有上限。
 * 所有数字都是起始值，等和客户确认后再调整，见 docs/design/enhance_rules_proposal.md。
 */
export const ENHANCE_QUALITIES = [
  { key: "white", name: "白" },
  { key: "green", name: "绿" },
  { key: "blue", name: "蓝" },
  { key: "purple", name: "紫" },
  { key: "orange", name: "橙" },
  { key: "red", name: "红" },
] as const;

export type EnhanceQualityKey = (typeof ENHANCE_QUALITIES)[number]["key"];

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
};

/** 起始突破材料：后台“填入建议起始值”时如果物品里还没有，会一并创建。数字和名称都只是起始值。 */
export const STARTING_BREAK_MATERIALS = [
  { slug: "enh_stone_low", displayName: "突破石·下品", description: "装备强化到突破节点时消耗的材料。（起始值，可在后台修改）", quality: "green" },
  { slug: "enh_stone_mid", displayName: "突破石·中品", description: "装备强化到较高突破节点时消耗的材料。（起始值，可在后台修改）", quality: "blue" },
  { slug: "enh_stone_high", displayName: "突破石·上品", description: "装备强化到高阶突破节点时消耗的材料。（起始值，可在后台修改）", quality: "purple" },
] as const;

/** 起始值，全部可在后台改。红（仙品）的数字是新增的起始值，没有平衡过。 */
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
    red: {
      cap: 18,
      costMult: 2,
      decomposeExp: 960,
      breakthroughs: [
        { level: 5, materials: [{ itemSlug: "enh_stone_low", count: 15 }] },
        { level: 10, materials: [{ itemSlug: "enh_stone_mid", count: 10 }] },
        { level: 15, materials: [{ itemSlug: "enh_stone_high", count: 5 }] },
      ],
    },
  },
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
  return {
    expBase: positive(raw.expBase, "基础经验", true),
    expGrowth,
    statGrowthBp: positive(raw.statGrowthBp, "每级属性加成", true),
    refundBp,
    qualities,
  };
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
          problems.push(`${quality.name}品质 +${node.level} 突破：材料 ${material.itemSlug} 不能是装备或功法书`);
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

export async function readEnhanceView(db: Db) {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  return { rules: row?.enhance ?? null, starting: STARTING_ENHANCE_RULES, startingMaterials: STARTING_BREAK_MATERIALS };
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
  if (created.length > 0) {
    items = await db.select({ slug: contentItems.slug, kind: contentItems.kind, enabled: contentItems.enabled }).from(contentItems);
  }
  const problems = breakMaterialProblems(rules, items);
  if (problems.length > 0) {
    throw new AppError("INVALID_INPUT", problems[0] ?? "突破材料不正确", { problems });
  }
  await db.update(contentGlobals).set({ enhance: rules, updatedAt: new Date(), updatedBy: adminId }).where(eq(contentGlobals.id, 1));
  return { ...(await readEnhanceView(db)), createdMaterials: created };
}
