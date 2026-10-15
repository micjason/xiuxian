import type { FieldDef, Schema } from "./types";

// ---------- 境界 ----------
export const realmSchema: Schema = {
  title: "境界",
  groups: [
    { key: "base", title: "基本信息", desc: "编号决定突破顺序，大境界决定装备分阶。" },
    { key: "cultivate", title: "修炼与突破", desc: "挂机修为的产出与突破门槛。" },
    { key: "stats", title: "到达该境界增加的属性", desc: "会和更低境界的加在一起。" },
    { key: "combat", title: "战斗", desc: "出手快慢的基础值。" },
  ],
  fields: [
    {
      key: "code", label: "编号", kind: "int", group: "base", required: true, min: 1, lockedAfterCreate: true,
      hint: "突破顺序，从小到大。不能重复。新建后不能改，要调整顺序请新建并删除。",
      affects: "突破顺序、关卡所需境界、装备可穿戴阶段", example: "1、2、3…", column: { width: 80 },
    },
    {
      key: "displayName", label: "名称", kind: "text", group: "base", required: true,
      hint: "玩家看到的境界名，例如「炼气初期」。", column: { minWidth: 140 }, example: "炼气初期",
    },
    {
      key: "majorName", label: "大境界", kind: "text", group: "base", required: true,
      hint: "同一个大境界的小境界填同一个名字，例如三个小境界都填「炼气」。保存后系统会生成这一阶的 25 件装备。",
      affects: "装备分阶与自动生成（6 部位 × 5 品质）", column: { width: 100 },
    },
    {
      key: "tickSeconds", label: "修炼间隔", kind: "number", group: "cultivate", min: 0, step: 1, unit: "秒", default: 0,
      hint: "每隔多少秒结算一次修为。0 表示还没设置，玩家得不到修为。", affects: "挂机修为速度（与「每次获得修为」一起算）",
      column: { width: 100 },
    },
    {
      key: "gainPerTick", label: "每次获得修为", kind: "number", group: "cultivate", min: 0, step: 1, unit: "点", default: 0,
      hint: "每个修炼间隔获得多少修为。0 表示还没设置。", affects: "挂机修为速度、功法分解折算", column: { width: 110 },
    },
    {
      key: "breakthroughCost", label: "突破消耗修为", kind: "number", group: "cultivate", min: 0, step: 1, unit: "点", default: 0,
      hint: "从本境界突破到下一境界要消耗的修为。最高境界不会用到。", affects: "突破节奏", column: { width: 110 },
    },
    {
      key: "attack", label: "攻击", kind: "number", group: "stats", min: 0, step: 1, default: 0,
      hint: "到达这个境界时增加的攻击。0 表示不增加。", affects: "面板攻击、战力", column: { width: 80 },
    },
    {
      key: "defense", label: "防御", kind: "number", group: "stats", min: 0, step: 1, default: 0,
      hint: "到达这个境界时增加的防御。", affects: "面板防御、受到的伤害、战力", column: { width: 80 },
    },
    {
      key: "hp", label: "气血", kind: "number", group: "stats", min: 0, step: 1, default: 0,
      hint: "到达这个境界时增加的气血。", affects: "面板气血、战力", column: { width: 80 },
    },
    {
      key: "speed", label: "速度", kind: "number", group: "stats", min: 0, step: 1, default: 0,
      hint: "到达这个境界时增加的速度。速度越高出手越快，但有最短出手间隔。", affects: "出手间隔、战力", column: { width: 80 },
    },
    {
      key: "interval", label: "基础出手间隔", kind: "number", group: "combat", min: 0.1, step: 0.1, precision: 2, unit: "秒",
      hint: "没有速度加成时多少秒出手一次。必须填，空着玩家无法战斗。第一版统一填 1.5。",
      affects: "出手间隔（与速度基数一起算）", example: "1.5", column: { width: 110 },
    },
  ],
};

// ---------- 物品 ----------
export const itemSchema: Schema = {
  title: "物品",
  fields: [
    { key: "displayName", label: "名称", kind: "text", required: true, hint: "玩家在行囊里看到的名字。", column: { minWidth: 160 } },
    { key: "description", label: "描述", kind: "textarea", hint: "物品详情里的说明文字。", column: { minWidth: 260 } },
  ],
};

// ---------- 装备（单件，只能改名称/描述/图标，属性由预算公式算出） ----------
export const gearPieceSchema: Schema = {
  title: "装备",
  fields: [
    { key: "displayName", label: "名称", kind: "text", required: true, hint: "装备名称。属性由「装备预算 × 部位占比 × 品质系数」算出，不能手填。" },
    { key: "description", label: "描述", kind: "textarea", hint: "装备详情里的说明文字。" },
    { key: "iconKey", label: "图标标识", kind: "text", hint: "客户端图标资源的 key。现在客户端还没有真实美术，可以先空着。", example: "gear_weapon_01" },
  ],
};

export const qualityFactorSchema: Schema = {
  title: "品质系数",
  fields: [
    { key: "white", label: "白（凡品）系数", kind: "number", required: true, min: 0.01, step: 0.05, default: 1, hint: "白品质装备的属性倍数，是其他品质的基准，建议保持 1。", affects: "全部白色装备属性" },
    { key: "green", label: "绿（良品）系数", kind: "number", required: true, min: 0.01, step: 0.05, default: 1.15, hint: "绿品质装备的属性倍数。", affects: "全部绿色装备属性" },
    { key: "blue", label: "蓝（精品）系数", kind: "number", required: true, min: 0.01, step: 0.05, default: 1.3, hint: "蓝品质装备的属性倍数。", affects: "全部蓝色装备属性" },
    { key: "purple", label: "紫（珍品）系数", kind: "number", required: true, min: 0.01, step: 0.05, default: 1.5, hint: "紫品质装备的属性倍数。", affects: "全部紫色装备属性" },
    { key: "orange", label: "橙（绝品）系数", kind: "number", required: true, min: 0.01, step: 0.05, default: 1.8, hint: "橙品质装备的属性倍数。", affects: "全部橙色装备属性", warning: "保存后每件装备的攻击、防御、气血、速度都会按新系数重算。" },
  ],
};

// ---------- 技能 ----------
export const skillSchema: Schema = {
  title: "技能",
  groups: [
    { key: "base", title: "基本信息" },
    { key: "bonus", title: "属性加成（按层数系数放大）", desc: "三项百分比彼此相加，只乘境界基础值，不乘装备。" },
  ],
  fields: [
    { key: "displayName", label: "名称", kind: "text", group: "base", required: true, hint: "功法名称。", column: { minWidth: 140 } },
    { key: "categoryId", label: "分类", kind: "select", group: "base", required: true, hint: "技能所属分类，先在「分类」页建好。", options: [], column: { width: 120 } },
    { key: "description", label: "描述", kind: "textarea", group: "base", hint: "功法说明。", column: { minWidth: 220 } },
    { key: "attack", label: "攻击加成", kind: "number", group: "bonus", min: 0, max: 100, step: 0.01, unit: "%", default: 0, hint: "运转时给境界基础攻击增加的百分比。实际值 = 基础百分比 × 层数系数。", affects: "面板攻击、战力", column: { width: 90 } },
    { key: "defense", label: "防御加成", kind: "number", group: "bonus", min: 0, max: 100, step: 0.01, unit: "%", default: 0, hint: "给境界基础防御增加的百分比。", affects: "面板防御、战力", column: { width: 90 } },
    { key: "hp", label: "气血加成", kind: "number", group: "bonus", min: 0, max: 100, step: 0.01, unit: "%", default: 0, hint: "给境界基础气血增加的百分比。", affects: "面板气血、战力", column: { width: 90 } },
    { key: "cultivateBonus", label: "修炼加成", kind: "number", group: "bonus", min: 0, step: 1, unit: "万分比", default: 0, hint: "挂机修为的额外加成，10000 万分比 = 100%。", example: "500 即修为 +5%", affects: "挂机修为速度", column: { width: 90 } },
  ],
};

export const skillCategorySchema: Schema = {
  title: "技能分类",
  fields: [{ key: "displayName", label: "名称", kind: "text", required: true, hint: "分类名称，例如「心法」「功法」。", column: { minWidth: 200 } }],
};

// ---------- 关卡 / Boss ----------
export const stageSchema: Schema = {
  title: "关卡",
  fields: [
    { key: "displayName", label: "关卡名称", kind: "text", required: true, hint: "关卡名，玩家在历练页看到。", column: { minWidth: 160 } },
    { key: "realmCode", label: "所需境界", kind: "select", required: true, hint: "到达这个境界才能挑战。选项来自「境界」页。", options: [], affects: "关卡解锁" },
  ],
};

export const bossSchema: Schema = {
  title: "首领",
  fields: [
    { key: "name", label: "名称", kind: "text", required: true, hint: "首领名称。" },
    { key: "attack", label: "攻击", kind: "number", min: 0, step: 1, default: 0, required: true, hint: "首领攻击。" },
    { key: "defense", label: "防御", kind: "number", min: 0, step: 1, default: 0, required: true, hint: "首领防御。" },
    { key: "hp", label: "气血", kind: "number", min: 0, step: 1, default: 0, required: true, hint: "首领气血，必须大于 0。" },
    { key: "interval", label: "出手间隔", kind: "number", min: 0, step: 0.1, precision: 2, unit: "秒", default: 1.5, required: true, hint: "首领多少秒出手一次，必须大于 0。" },
  ],
};

// ---------- 战斗公式与参数（/admin/draft/rules 的 12 个字段，旧页面只露出 7 个） ----------
export const rulesSchema: Schema = {
  title: "战斗公式与参数",
  groups: [
    { key: "damage", title: "伤害", desc: "每下伤害 = 攻击 × 攻击 ÷（攻击 + k × 对方防御）" },
    { key: "speed", title: "出手", desc: "出手间隔 = 基础出手间隔 × 速度基数 ÷（速度基数 + 速度），不短于最短出手间隔" },
    { key: "power", title: "战力权重", desc: "战力 = 各项属性 × 对应权重，再四舍五入。权重只影响战力数字，不影响实际伤害。" },
    { key: "battle", title: "挑战与推荐战力" },
    { key: "world", title: "行囊与离线" },
  ],
  fields: [
    { key: "defenseConstant", label: "防御常数 k", kind: "number", group: "damage", required: true, min: 0.01, step: 0.1, default: 1, hint: "k 越大，同样的防御挡掉越多，战斗越久。", affects: "所有战斗的伤害；改动后装备战力会整体偏移，需要重新反推战力权重", warning: "改 k 后原来的四个战力权重不再代表真实实力。" },
    { key: "speedBase", label: "速度基数", kind: "number", group: "speed", required: true, min: 0.01, step: 10, default: 100, hint: "基数越大，速度越不容易缩短出手间隔。", affects: "出手间隔" },
    { key: "minInterval", label: "最短出手间隔", kind: "number", group: "speed", required: true, min: 0.01, step: 0.1, precision: 2, unit: "秒", default: 0.5, hint: "速度再高，出手间隔也不会短于这个值。", affects: "出手间隔下限" },
    { key: "attackWeight", label: "攻击权重", kind: "number", group: "power", required: true, min: 0, step: 0.1, default: 4.7, hint: "战力里攻击的占比权重。", affects: "战力、推荐战力、装备战力" },
    { key: "defenseWeight", label: "防御权重", kind: "number", group: "power", required: true, min: 0, step: 0.1, default: 1.6, hint: "战力里防御的占比权重。", affects: "战力、推荐战力、装备战力" },
    { key: "hpWeight", label: "气血权重", kind: "number", group: "power", required: true, min: 0, step: 0.01, default: 0.95, hint: "战力里气血的占比权重。气血数值通常比其他属性大几倍，权重相应较小。", affects: "战力、推荐战力、装备战力" },
    { key: "speedWeight", label: "速度权重", kind: "number", group: "power", required: true, min: 0, step: 0.1, default: 2.6, hint: "战力里速度的占比权重。", affects: "战力、推荐战力、装备战力" },
    { key: "challengeCooldownSeconds", label: "挑战冷却", kind: "number", group: "battle", required: true, min: 0, step: 1, unit: "秒", default: 0, hint: "两次挑战首领之间要间隔的秒数，0 表示没有冷却。", affects: "玩家挑战频率" },
    { key: "timeLimitSeconds", label: "单场时限", kind: "number", group: "battle", required: true, min: 1, step: 5, unit: "秒", default: 45, hint: "首领战超过这个时间没分出胜负，算玩家输。原型默认 45 秒；全局一个值，所有首领共用。", affects: "战斗胜负、试打结果" },
    { key: "recommendedPowerMargin", label: "推荐战力倍数", kind: "number", group: "battle", required: true, min: 0.1, step: 0.05, default: 1.05, hint: "关卡推荐战力 = 打赢首领所需战力 × 这个倍数。大于 1 更保守。", affects: "关卡推荐战力" },
    { key: "bagCapacity", label: "行囊容量", kind: "int", group: "world", required: true, min: 1, step: 10, unit: "格", default: 100, hint: "玩家行囊最多放多少件（已穿戴的不占格）。满了无法挑战拿掉落。", affects: "行囊、掉落", warning: "调小不会清掉玩家已有物品，但已超出的玩家会无法挑战。" },
    { key: "offlineCapSeconds", label: "离线收益上限", kind: "int", group: "world", required: true, min: 1, step: 3600, unit: "秒", default: 28800, hint: "离线最多按多少秒结算修为，28800 = 8 小时。", affects: "离线收益" },
  ],
};

// 草稿快照 globals 里目前没有任何编辑接口的参数：只读展示，提醒后端补接口。
export const globalsReadonlyFields: FieldDef[] = [
  { key: "startingRealmSlug", label: "初始境界", kind: "text", readonly: true, hint: "新玩家的起始境界。目前只能改数据库或导入脚本。" },
  { key: "starterItems", label: "新手物品", kind: "text", readonly: true, hint: "新玩家注册时发放的物品清单。目前没有编辑接口。" },
  { key: "artSlotRules", label: "功法栏位规则", kind: "text", readonly: true, hint: "各境界开放几个功法栏位。目前没有编辑接口。" },
  { key: "idleKillCap", label: "挂机击杀上限", kind: "number", readonly: true, hint: "离线结算时最多算多少次击杀。目前没有编辑接口。" },
  { key: "minClientVersionCode", label: "最低客户端版本号", kind: "number", readonly: true, hint: "低于这个版本号的客户端被要求更新。目前没有编辑接口。" },
];

// ---------- 人偶（手填属性） ----------
export const puppetManualSchema: Schema = {
  title: "人偶",
  fields: [
    { key: "displayName", label: "名称", kind: "text", required: true, hint: "人偶只用于试打，不进游戏。" },
    { key: "attack", label: "攻击", kind: "number", min: 0, default: 0, hint: "手填的攻击。" },
    { key: "defense", label: "防御", kind: "number", min: 0, default: 0, hint: "手填的防御。" },
    { key: "hp", label: "气血", kind: "number", min: 0, default: 0, hint: "手填的气血。" },
    { key: "speed", label: "速度", kind: "number", min: 0, default: 0, hint: "手填的速度。" },
    { key: "interval", label: "出手间隔", kind: "number", min: 0, precision: 2, unit: "秒", default: 1.5, hint: "手填的出手间隔。" },
  ],
};

// ---------- 运营 ----------
export const announcementSchema: Schema = {
  title: "公告",
  fields: [
    { key: "title", label: "标题", kind: "text", required: true, hint: "玩家登录后弹出的公告标题。", column: { minWidth: 180 } },
    { key: "body", label: "正文", kind: "textarea", required: true, hint: "公告正文，支持换行。", column: { minWidth: 280 } },
    { key: "enabled", label: "启用", kind: "bool", default: true, hint: "启用后玩家登录时可见；关闭等于下线。公告接口暂不支持删除，请用「关闭」。", column: { width: 90 } },
  ],
};

export const popupSchema: Schema = {
  title: "弹窗",
  fields: [
    { key: "priority", label: "优先级", kind: "int", min: 1, default: 1, hint: "同时有多个弹窗时，数字小的先弹出。", unit: "" },
    { key: "enabled", label: "启用", kind: "bool", default: true, hint: "关闭后这类弹窗不再弹出。" },
  ],
};

export const buildingSchema: Schema = {
  title: "洞府建筑",
  fields: [
    { key: "slug", label: "编号", kind: "text", required: true, lockedAfterCreate: true, hint: "建筑的唯一标识，英文小写加下划线，创建后不能改。", example: "spirit_field", column: { width: 150 } },
    { key: "displayName", label: "名称", kind: "text", required: true, hint: "建筑名称。洞府玩法在旧版 main 分支，dev 分支客户端暂未接入。", column: { minWidth: 140 } },
    { key: "maxLevel", label: "等级上限", kind: "int", min: 1, default: 1, hint: "建筑最高几级。", column: { width: 100 } },
    { key: "laborBonus", label: "劳作加成", kind: "number", min: 0, default: 0, hint: "劳作产出加成。", column: { width: 100 } },
    { key: "cultivateBonusPerLevel", label: "每级修炼加成", kind: "number", min: 0, default: 0, hint: "每升一级增加的修炼加成。", column: { width: 120 } },
  ],
};

/** 在字段说明里按 key 查中文名，发布变更清单用它把英文字段名翻成中文。 */
export const allSchemas: Schema[] = [
  realmSchema, itemSchema, gearPieceSchema, qualityFactorSchema, skillSchema, skillCategorySchema, stageSchema, bossSchema,
  rulesSchema, puppetManualSchema, announcementSchema, popupSchema, buildingSchema,
];

const extraLabels: Record<string, string> = {
  sortOrder: "排序", nextRealmSlug: "下一境界", baseAttack: "基础攻击", baseDefense: "基础防御", baseHp: "基础气血", baseSpeed: "基础速度",
  baseInterval: "基础出手间隔", powerWeights: "战力权重", combat: "战斗参数", requiredRealmOrder: "所需境界编号", quality: "品质", slot: "部位",
  kind: "类型", stackable: "可叠加", enabled: "启用", bosses: "首领与掉落", entries: "掉落条目", recommendedPower: "推荐战力", rank: "品阶",
  role: "功法类型", cultivateBonusBp: "修炼加成（万分比）", prerequisiteSkillSlugs: "前置功法", minRateBp: "最低成功率", baseRateBp: "基础成功率",
  maxRateBp: "最高成功率", failLossBp: "失败损失", pityStepBp: "保底步长", powerFactorBp: "战力系数", requiredStageSlug: "所需通关关卡",
  skillSlug: "对应功法", bossName: "首领名称", bossAttack: "首领攻击", bossDefense: "首领防御", bossHp: "首领气血", bossInterval: "首领出手间隔",
  tickSeconds: "修炼间隔", gainPerTick: "每次获得修为", breakthroughCost: "突破消耗修为", starterItems: "新手物品", startingRealmSlug: "初始境界",
  artSlotRules: "功法栏位规则", idleKillCap: "挂机击杀上限", minClientVersionCode: "最低客户端版本号", bagCapacity: "行囊容量",
  offlineCapSeconds: "离线收益上限", attack: "攻击", defense: "防御", hp: "气血", speed: "速度", displayName: "名称",
};

const labelIndex = new Map<string, string>();
for (const schema of allSchemas) {
  for (const field of schema.fields) {
    if (!labelIndex.has(field.key)) {
      labelIndex.set(field.key, field.label);
    }
  }
}

export function fieldLabel(key: string): string {
  return extraLabels[key] ?? labelIndex.get(key) ?? key;
}
