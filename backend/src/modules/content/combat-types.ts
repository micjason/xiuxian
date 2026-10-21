/**
 * 战斗系统（普通怪波次、首领奖励、大招）的配置类型和默认值。
 * 只放类型和常量，不依赖别的模块，db/schema.ts 和 validate.ts 都可以引用。
 */

/** 后台“战斗公式与参数”里的可选数值参数：缺省时用 default，所以老内容不用重新填也能跑。 */
export const OPTIONAL_RULES = {
  onlineGapSeconds: { label: "在线判定间隔", default: 15, min: 1, max: 600, integer: true },
  offlinePopupMinSeconds: { label: "离线弹窗最短时长", default: 300, min: 0, max: 86400, integer: true },
  ultAutoCastWindowSeconds: { label: "大招自动释放等待", default: 2, min: 0, max: 30, integer: false },
  bossDailyRewardCount: { label: "首领每日奖励次数", default: 5, min: 0, max: 99, integer: true },
  dayStartHour: { label: "每日重置整点（北京时间）", default: 5, min: 0, max: 23, integer: true },
  waveSize: { label: "每波怪物数", default: 3, min: 1, max: 10, integer: true },
  waveTransitionSeconds: { label: "波次转场秒数", default: 2, min: 0, max: 60, integer: false },
  reviveSeconds: { label: "阵亡复活秒数", default: 3, min: 0, max: 60, integer: false },
} as const;

export type OptionalRuleKey = keyof typeof OPTIONAL_RULES;
export type OptionalRuleValues = { [K in OptionalRuleKey]?: number };

export type QualityWeights = { white?: number; green?: number; blue?: number; purple?: number; orange?: number };

/** 一只普通怪（每个关卡一种，每波按“每波怪物数”只上前）。 */
export type StageMonster = {
  name: string;
  attack: number;
  defense: number;
  hp: number;
  interval: number;
  /** 每击杀一只得到的修为（整数，不吃功法加成）。 */
  killCultivation: number;
};

/** 普通怪的装备掉落：每只击杀 chanceBp 万分比掉 1 件本境界阶装备，品质按权重，6 个部位等概率。 */
export type MonsterDropConfig = {
  chanceBp: number;
  qualityWeights: QualityWeights;
};

/** 首领奖励条目：物品（也可以填功法编号，会变成功法书）或修为。 */
/** 关卡里存的掉落覆盖：缺的或 null 的项跟随配置概览的默认值。 */
export type MonsterDropOverride = {
  chanceBp?: number | null;
  qualityWeights?: { [K in keyof QualityWeights]?: number | null };
};

export type BossRewardEntry = { kind: "item"; itemSlug: string; quantity: number } | { kind: "cultivation"; amount: number };

export type BossRepeatReward = {
  /** 每次有奖励的胜利给 1 件本境界阶装备，品质权重取关卡的普通怪掉落权重，白色改为绿色。 */
  gear: boolean;
  /** 额外物品，各自按万分比独立掷骰（例如突破石）。 */
  extras: { itemSlug: string; chanceBp: number; minQty: number; maxQty: number }[];
  /** 给的装备直接是橙色的概率（万分比）；不填 = 配置概览的「首领橙装概率」。 */
  orangeChanceBp?: number | null;
};

export const DEFAULT_OPTIONAL_RULES = Object.fromEntries(
  (Object.keys(OPTIONAL_RULES) as OptionalRuleKey[]).map((key) => [key, OPTIONAL_RULES[key].default]),
) as Required<OptionalRuleValues>;

/** 指定掉落的触发时机：普通怪每只 / 首领首通 / 首领有奖励的重打。 */
export const DESIGNATED_TRIGGERS = ["monster", "boss_first", "boss_repeat"] as const;
export type DesignatedTrigger = (typeof DESIGNATED_TRIGGERS)[number];

/** 每关指定掉落的一条：和随机掉落同时生效，每条单独按概率抽（不占随机掉落的概率）。 */
export type DesignatedDrop = {
  itemSlug: string;
  trigger: DesignatedTrigger;
  /** 万分比 1..10000 */
  chanceBp: number;
  /** 件数 1..10 */
  count: number;
};

export const SET_STATS = ["attack", "defense", "hp", "speed"] as const;
export type SetStat = (typeof SET_STATS)[number];

/** 套装加成的一档：穿满 pieces 件时生效（各档叠加）。pct = 按角色总属性的百分比；flat = 直接加点数。 */
export type SetTier = {
  pieces: number;
  stats: { stat: SetStat; mode: "pct" | "flat"; value: number }[];
};

/** 功法栏位规则：境界排序号 ≥ minRealmOrder 时开放 slots 个通用栏位（取满足条件里最大的那条）。 */
export type SkillSlotRule = { minRealmOrder: number; slots: number };
