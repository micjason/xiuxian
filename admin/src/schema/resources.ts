import type { FieldDef, Schema } from "./types";

// ---------- 境界 ----------
export const realmSchema: Schema = {
  title: "境界",
  groups: [
    { key: "base", title: "基本信息", desc: "编号决定突破顺序，大境界决定装备分阶。" },
    { key: "cultivate", title: "修炼与突破", desc: "挂机修为的产出与突破门槛。每秒修为 = 每次获得修为 ÷ 修炼间隔，是本境自己的数，不是前面境界加起来。" },
    { key: "stats", title: "到达该境界增加的属性", desc: "会和更低境界的加在一起。" },
    { key: "combat", title: "战斗", desc: "出手快慢的基础值。" },
    { key: "gate", title: "大境界突破门槛", desc: "跨大境界（例如炼气 → 筑基）要先通关一个首领关；小境界之间不用填。填在大境界的最后一层。" },
    { key: "ult", title: "手动大招", desc: "首领战里玩家可以点的大招。同一个大境界的几层填一样的。倍数填 0 表示没有大招。" },
  ],
  fields: [
    {
      key: "code", help: false, label: "编号", kind: "int", group: "base", required: true, min: 1, lockedAfterCreate: true,
      hint: "突破顺序，从小到大。不能重复。新建后不能改，要调整顺序请新建并删除。",
      affects: "突破顺序、关卡所需境界、装备可穿戴阶段", example: "1、2、3…", column: { width: 80 },
    },
    {
      key: "displayName", label: "名称", kind: "text", group: "base", required: true,
      hint: "玩家看到的境界名，例如「炼气初期」。", column: { minWidth: 140 }, example: "炼气初期",
    },
    {
      key: "majorName", label: "大境界", kind: "text", group: "base", required: true,
      hint: "同一个大境界的小境界填同一个名字，例如三个小境界都填「炼气」。保存后系统会生成这一阶的 30 件装备（6 部位 × 5 品质）。",
      affects: "装备分阶与自动生成（6 部位 × 5 品质）", column: { width: 100 },
    },
    {
      key: "tickSeconds", label: "修炼间隔", kind: "number", group: "cultivate", min: 0, step: 1, unit: "秒", default: 1,
      hint: "每隔多少秒结算一次修为。原型统一填 1。0 表示还没设置，玩家得不到修为。本境自己的间隔，不是累计前境。", affects: "挂机修为速度（与「每次获得修为」一起算）",
      column: { width: 100 },
    },
    {
      key: "gainPerTick", label: "每次获得修为", kind: "number", group: "cultivate", min: 0, step: 1, unit: "点", default: 0,
      hint: "每个修炼间隔获得多少修为。0 表示还没设置。本境自己的产出，不是前面境界加起来（和 settle.ts 一致）。", affects: "挂机修为速度、功法分解折算", column: { width: 110 },
    },
    {
      key: "breakthroughCost", label: "突破消耗修为", kind: "number", group: "cultivate", min: 0, step: 1, unit: "点", default: 0,
      hint: "从本境界突破到下一境界要消耗的修为。最高境界不会用到。", affects: "突破节奏", column: { width: 110 },
    },
    {
      key: "attack", help: false, label: "攻击", kind: "number", group: "stats", min: 0, step: 1, default: 0,
      hint: "到达这个境界时增加的攻击。0 表示不增加。", affects: "面板攻击、战力", column: { width: 80 },
    },
    {
      key: "defense", help: false, label: "防御", kind: "number", group: "stats", min: 0, step: 1, default: 0,
      hint: "到达这个境界时增加的防御。", affects: "面板防御、受到的伤害、战力", column: { width: 80 },
    },
    {
      key: "hp", help: false, label: "气血", kind: "number", group: "stats", min: 0, step: 1, default: 0,
      hint: "到达这个境界时增加的气血。", affects: "面板气血、战力", column: { width: 80 },
    },
    {
      key: "speed", help: false, label: "速度", kind: "number", group: "stats", min: 0, step: 1, default: 0,
      hint: "到达这个境界时增加的速度。速度越高出手越快，但有最短出手间隔。", affects: "出手间隔、战力", column: { width: 80 },
    },
    {
      key: "interval", label: "基础出手间隔", kind: "number", group: "combat", min: 0.1, step: 0.1, precision: 2, unit: "秒",
      hint: "没有速度加成时多少秒出手一次。必须填，空着玩家无法战斗。第一版统一填 1.5。",
      affects: "出手间隔（与速度基数一起算）", example: "1.5", column: { width: 110 },
    },
    {
      key: "requiredStageId", label: "突破前要先通关", kind: "select", group: "gate", options: [], default: "",
      hint: "从本境界突破到下一境界之前，玩家必须首通这个关卡的首领。留空 = 不需要。只能选有首领、且境界要求不高于本境界的关卡（选项来自「关卡」页）。",
      affects: "大境界突破（未通关时突破按钮提示去挑战首领）", example: "炼气三层选「黑风岭·三」",
    },
    {
      key: "ultName", label: "大招名称", kind: "text", group: "ult", default: "",
      hint: "按钮上显示的名字，例如「剑诀·破军」。", affects: "首领战大招按钮",
    },
    {
      key: "ultMultiplier", label: "大招伤害倍数", kind: "number", group: "ult", min: 0, max: 100, step: 0.5, precision: 2, unit: "倍", default: 0,
      hint: "大招伤害 = 一次普攻伤害 × 这个倍数（取整），是额外多打一下，不替代普攻。炼气 4、筑基 5、金丹 6。0 = 没有大招。",
      affects: "首领战胜负（服务端按点击时间重新模拟）", example: "4",
    },
    {
      key: "ultCooldownSeconds", label: "大招冷却", kind: "number", group: "ult", min: 0, max: 600, step: 1, precision: 1, unit: "秒", default: 0,
      hint: "释放之后多少秒再次冷却完成。炼气 20、筑基 18、金丹 16。有大招时必须至少 1 秒。", affects: "首领战大招次数",
    },
    {
      key: "ultFirstCooldownSeconds", label: "开战首次冷却", kind: "number", group: "ult", min: 0, max: 600, step: 1, precision: 1, unit: "秒", default: 8,
      hint: "进入首领战后第一次冷却完成的时间，原型统一 8 秒。", affects: "首领战大招次数",
    },
  ],
};

// ---------- 物品 ----------
export const itemSchema: Schema = {
  title: "物品",
  fields: [
    { key: "displayName", label: "名称", kind: "text", required: true, hint: "玩家在行囊里看到的名字。", column: { minWidth: 160 } },
    { key: "kind", label: "类型", kind: "select", required: true, default: "material", options: [{ label: "材料", value: "material" }, { label: "丹药", value: "pill" }], hint: "材料（例如突破石，强化突破要用）或丹药。保存时不会再清空原来的类型。", column: { width: 90 } },
    { key: "quality", label: "品质", kind: "select", required: true, default: "white", options: [{ label: "白", value: "white" }, { label: "绿", value: "green" }, { label: "蓝", value: "blue" }, { label: "紫", value: "purple" }, { label: "橙", value: "orange" }], hint: "行囊里显示的品质颜色。", column: { width: 80 } },
    { key: "stackable", label: "可叠加", kind: "bool", default: true, hint: "同种物品在行囊里叠成一格。", column: { width: 80 } },
    { key: "iconKey", label: "图标", kind: "select", options: [], hint: "游戏里显示的图标。不选 = 按编号自动选（例如突破石用石头图）。客户端 0.15.0 起生效。" },
    { key: "description", label: "描述", kind: "textarea", hint: "物品详情里的说明文字。", column: { minWidth: 260 } },
  ],
};

// ---------- 装备（单件：名称 / 描述 / 图标 / 掉率倍数；属性由预算公式算出） ----------
export const gearPieceSchema: Schema = {
  title: "装备",
  fields: [
    { key: "displayName", label: "名称", kind: "text", required: true, hint: "装备名称。属性由「装备预算 × 部位占比 × 品质系数」算出，不能手填。" },
    { key: "description", label: "描述", kind: "textarea", hint: "装备详情里的说明文字。" },
    { key: "iconKey", label: "图标", kind: "text", help: true, hint: "空 = 游戏按「大境界 + 部位」自动选图标；选了就用选的这张（客户端 0.15 起生效）。", example: "gear_qi_weapon" },
    { key: "dropMult", label: "掉率倍数", kind: "number", min: 0, max: 100, step: 0.1, precision: 2, unit: "倍", default: 1, hint: "同大境界、同品质 6 件按倍数分配被抽中的机会：本件占比 = 本件倍数 ÷ 6 件倍数之和。普通怪掉落和首领重复奖励都按这个规则。" },
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
    { key: "role", label: "功法类型", kind: "select", group: "base", options: [{ label: "心法", value: "heart" }, { label: "攻法", value: "attack" }, { label: "身法", value: "body" }, { label: "步法", value: "step" }], hint: "功法类型。保存时不会再清空。" },
    { key: "rank", label: "品阶", kind: "select", group: "base", required: true, default: "yellow", options: [{ label: "黄阶", value: "yellow" }, { label: "玄阶", value: "xuan" }, { label: "地阶", value: "earth" }, { label: "天阶", value: "heaven" }], hint: "功法品阶，影响多余功法书折算修为。", column: { width: 80 } },
    { key: "requiredRealmCode", label: "所需境界", kind: "select", group: "base", options: [], hint: "达到这个境界才能学。" },
    { key: "prerequisiteIds", label: "前置功法", kind: "multiselect", group: "base", options: [], hint: "要先学会的功法。不能选自己。" },
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
    { key: "recommendedPower", label: "推荐战力", kind: "int", min: 0, max: 10000000, unit: "战力", hint: "默认按公式自动算：首领战力 × 推荐战力倍数（没有首领时用普通怪）；点「手动覆盖」才能填，玩家在历练页看到这个值。", affects: "关卡页提示、战斗页提示" },
  ],
};

export const bossSchema: Schema = {
  title: "首领",
  fields: [
    { key: "name", label: "名称", kind: "text", required: true, hint: "首领名称。" },
    { key: "attack", label: "攻击", kind: "number", help: false, min: 0, step: 1, default: 0, required: true, hint: "首领攻击。" },
    { key: "defense", label: "防御", kind: "number", help: false, min: 0, step: 1, default: 0, required: true, hint: "首领防御。" },
    { key: "hp", label: "气血", kind: "number", help: false, min: 0, step: 1, default: 0, required: true, hint: "首领气血，必须大于 0。" },
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
    { key: "gearSpeedFactor", label: "装备速度比例", kind: "number", group: "speed", required: true, min: 0, max: 1, step: 0.05, precision: 2, default: 0.3, hint: "鞋子、饰品上的速度 = 按预算算出的值 × 这个比例；省下的战力补到同部位的气血/攻击上，单件装备战力不变。1 = 不压速度；越小，装备越难把出手间隔压向下限。保存后会重新生成全部装备数值。", affects: "装备速度、出手间隔、装备数值（保存后整体重算）", warning: "改动会重算所有已生成装备的属性。" },
    { key: "challengeCooldownSeconds", label: "挑战冷却", kind: "number", group: "battle", required: true, min: 0, step: 1, unit: "秒", default: 0, hint: "两次挑战首领之间要间隔的秒数，0 表示没有冷却。", affects: "玩家挑战频率" },
    { key: "timeLimitSeconds", label: "单场时限", kind: "number", group: "battle", required: true, min: 1, step: 5, unit: "秒", default: 45, hint: "首领战超过这个时间没分出胜负，算玩家输。原型默认 45 秒；全局一个值，所有首领共用。", affects: "战斗胜负、试打结果" },
    { key: "recommendedPowerMargin", label: "推荐战力倍数", kind: "number", group: "battle", required: true, min: 0.1, step: 0.05, default: 1.05, hint: "关卡推荐战力 = 打赢首领所需战力 × 这个倍数。大于 1 更保守。", affects: "关卡推荐战力" },
    { key: "onlineGapSeconds", label: "在线判定间隔", kind: "int", group: "world", min: 1, max: 600, step: 1, unit: "秒", default: 15, hint: "“在线”= 玩家前台打开游戏。两次请求间隔不超过这个秒数算在线（打普通怪、拿击杀修为和掉落）；超过就按离线段结算（只产修为）。客户端前台每 15 秒内至少请求一次。", affects: "普通怪波次、击杀修为、装备掉落、离线结算" },
    { key: "offlinePopupMinSeconds", label: "离线弹窗最短时长", kind: "int", group: "world", min: 0, max: 86400, step: 60, unit: "秒", default: 300, hint: "离线达到这个秒数才弹“闭关归来”窗；不足时修为照常入账，只是不弹窗。", affects: "离线弹窗" },
    { key: "dayStartHour", label: "每日重置整点", kind: "int", group: "world", min: 0, max: 23, step: 1, unit: "点", default: 5, hint: "北京时间的几点算新的一天（首领每日奖励次数按它重置）。", affects: "首领每日奖励次数" },
    { key: "ultAutoCastWindowSeconds", label: "大招自动释放等待", kind: "number", group: "battle", min: 0, max: 30, step: 0.5, precision: 1, unit: "秒", default: 0, hint: "大招蓄满后再等几秒自动释放（第四批起没有手动点击，0＝蓄满立刻放）。大招的名称、倍率、冷却在“境界”里按层填。", affects: "首领战大招" },
    { key: "waveSize", label: "每波怪物数", kind: "int", group: "battle", min: 1, max: 10, step: 1, unit: "只", default: 3, hint: "普通怪一波有几只，依次上前，一次只和一只交战，中间不回血。", affects: "普通怪击杀速度" },
    { key: "waveTransitionSeconds", label: "波次转场秒数", kind: "number", group: "battle", min: 0, max: 60, step: 0.5, precision: 1, unit: "秒", default: 2, hint: "一波打完到下一波之间的转场时间，转场时主角回满血。", affects: "普通怪击杀速度" },
    { key: "reviveSeconds", label: "阵亡复活秒数", kind: "number", group: "battle", min: 0, max: 60, step: 0.5, precision: 1, unit: "秒", default: 3, hint: "普通怪打输（阵亡）后原地复活、回满血所需的秒数，无其他惩罚。", affects: "普通怪击杀速度" },
    { key: "bagCapacity", label: "行囊容量", kind: "int", help: false, group: "world", required: true, min: 1, step: 10, unit: "格", default: 20, hint: "玩家行囊最多放多少件（已穿戴的不占格）。满了无法挑战拿掉落。", affects: "行囊、掉落", warning: "调小不会清掉玩家已有物品，但已超出的玩家会无法挑战。" },
    { key: "offlineCapSeconds", label: "离线收益上限", kind: "int", group: "world", required: true, min: 1, step: 3600, unit: "秒", default: 28800, hint: "离线最多按多少秒结算修为，28800 = 8 小时。", affects: "离线收益" },
  ],
};

// 以前只读展示的 globals 参数：初始境界、新手物品、功法栏位已在「配置概览」可编辑（批次②）；
// 挂机击杀上限、最低客户端版本号已删除（离线不打怪；强制更新统一走「客户端安装包」）。
export const globalsReadonlyFields: FieldDef[] = [];

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
  role: "功法类型", cultivateBonusBp: "修炼加成（万分比）", prerequisiteSkillSlugs: "前置功法",
  requiredStageSlug: "所需通关关卡", requiredStageId: "突破前要先通关", ultName: "大招名称", ultMultiplier: "大招伤害倍数", ultCooldownSeconds: "大招冷却", ultFirstCooldownSeconds: "开战首次冷却",
  skillSlug: "对应功法", bossName: "首领名称", bossAttack: "首领攻击", bossDefense: "首领防御", bossHp: "首领气血", bossInterval: "首领出手间隔",
  tickSeconds: "修炼间隔", gainPerTick: "每次获得修为", breakthroughCost: "突破消耗修为", starterItems: "新手物品", startingRealmSlug: "初始境界",
  artSlotRules: "功法栏位规则", bagCapacity: "行囊容量",
  offlineCapSeconds: "离线收益上限", onlineGapSeconds: "在线判定间隔", offlinePopupMinSeconds: "离线弹窗最短时长", dayStartHour: "每日重置整点", bossDailyRewardCount: "首领每日奖励次数", ultAutoCastWindowSeconds: "大招自动释放等待", waveSize: "每波怪物数", waveTransitionSeconds: "波次转场秒数", reviveSeconds: "阵亡复活秒数", attack: "攻击", defense: "防御", hp: "气血", speed: "速度", displayName: "名称",
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
