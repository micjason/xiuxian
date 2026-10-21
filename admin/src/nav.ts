// 后台信息架构：菜单树是唯一来源，路由、面包屑、全局搜索都从这里生成。
export type NavItem = {
  path: string;
  label: string;
  /** 全局搜索额外关键词 */
  keywords?: string;
  desc: string;
  /** 菜单项后的「新」小标签（上线两周后去掉） */
  isNew?: boolean;
};
export type NavGroup = {
  key: string;
  title: string;
  icon: string;
  items: NavItem[];
  /** 面包屑点一级菜单时跳到哪（不填 = 组里第一项） */
  home?: string;
};

export const navTree: NavGroup[] = [
  {
    key: "overview",
    title: "概览",
    icon: "Odometer",
    items: [{ path: "/dashboard", label: "运营概览", desc: "内容版本、待办、玩家分布和最近操作", keywords: "首页 仪表盘 待办" }],
  },
  {
    key: "players",
    title: "玩家运营",
    icon: "User",
    items: [{ path: "/players", label: "玩家管理", desc: "查询玩家、查看战力来源、清空进度", keywords: "用户 账号 战力 清空 重置" }],
  },
  {
    key: "config",
    title: "游戏配置",
    icon: "SetUp",
    home: "/config/overview",
    items: [
      {
        path: "/config/overview",
        label: "配置概览",
        desc: "所有默认数值：战力公式、默认掉率与品质权重、强化与分解、功法层数、挂机节奏",
        keywords: "默认 默认值 数值 掉率 掉落 权重 品质 橙装 战力公式 分解 强化 功法 层数 行囊 离线 参数",
        isNew: true,
      },
      { path: "/config/realms", label: "境界", desc: "突破顺序、修炼速度、境界属性", keywords: "修为 突破 大境界" },
      { path: "/config/items", label: "物品", desc: "突破石等材料、物品说明", keywords: "物品 材料 突破石 背包 行囊" },
      {
        path: "/config/gear",
        label: "装备配置",
        desc: "装备生成参数、各大境界预算、90 件装备的名称与掉率倍数",
        keywords: "武器 装备 品质 品质系数 预算 部位 占比 掉率 倍数 图标",
        isNew: true,
      },
      { path: "/config/skills", label: "技能", desc: "功法与分类", keywords: "功法 心法 技能分类" },
      { path: "/config/stages", label: "关卡与Boss", desc: "关卡、首领属性与掉落、试打", keywords: "首领 掉落 掉率 试打 历练" },
      { path: "/config/enhance", label: "装备强化", desc: "强化经验、等级上限、属性加成、突破节点、分解返还", keywords: "强化 经验 分解 上限 品质 成长 突破 材料 仙品 红" },
      { path: "/config/combat", label: "战斗公式与参数", desc: "伤害、出手、战力权重、行囊与离线参数、试炼模拟", keywords: "规则 公式 k 权重 人偶 战力 模拟 冷却" },
      { path: "/config/buildings", label: "洞府建筑", desc: "旧版洞府玩法配置（dev 客户端未接入）", keywords: "洞府" },
    ],
  },
  {
    key: "publish",
    title: "发布中心",
    icon: "Promotion",
    items: [
      { path: "/publish", label: "草稿与发布", desc: "校验、变更清单、发布", keywords: "发布 草稿 变更 校验" },
      { path: "/publish/versions", label: "版本历史", desc: "每次发布的快照、任意两个版本（或草稿）的差别", keywords: "快照 对比 历史 版本" },
      { path: "/publish/client", label: "客户端安装包", desc: "上传安装包、设为当前版本、强制更新", keywords: "apk 更新 版本 安装包" },
    ],
  },
  {
    key: "ops",
    title: "公告弹窗",
    icon: "Present",
    items: [
      { path: "/ops/announcements", label: "公告", desc: "登录公告", keywords: "通知" },
      { path: "/ops/popups", label: "弹窗", desc: "弹窗类型的优先级与开关" },
    ],
  },
  {
    key: "system",
    title: "系统",
    icon: "Setting",
    items: [
      { path: "/system/admins", label: "管理员", desc: "当前为单管理员模式", keywords: "账号 权限" },
      { path: "/system/audit", label: "操作日志", desc: "谁在什么时候做了什么", keywords: "审计 记录 操作记录 日志" },
      { path: "/system/settings", label: "设置", desc: "外观与会话", keywords: "主题 深色 退出" },
    ],
  },
];

/**
 * 后续阶段才做的功能。只在侧栏底部以灰色文字提示，不可点击、没有路由、没有假数据。
 * 阶段划分见 docs/roadmap/phases.md：A 阶段只做单人可玩的完整玩法和后台；B 阶段才做安全与运营。
 */
export const plannedFeatures: { label: string; phase: string }[] = [
  { label: "邮件与补偿", phase: "B" },
  { label: "礼包与兑换码", phase: "B" },
  { label: "商品与订单", phase: "B" },
  { label: "封禁与回滚", phase: "B" },
];

export const flatNav: (NavItem & { group: string })[] = navTree.flatMap((group) => group.items.map((item) => ({ ...item, group: group.title })));

/** 一级菜单组的「首页」：面包屑点一级时跳这里。 */
export function groupHome(groupTitle: string): string | undefined {
  const group = navTree.find((item) => item.title === groupTitle);
  return group ? (group.home ?? group.items[0]?.path) : undefined;
}

export function navOf(path: string): (NavItem & { group: string }) | undefined {
  const exact = flatNav.find((item) => item.path === path);
  if (exact) {
    return exact;
  }
  // 子路径：取最长前缀
  return [...flatNav].sort((left, right) => right.path.length - left.path.length).find((item) => path.startsWith(`${item.path}/`));
}

/** 旧路由 → 新路由，保证旧书签不失效。 */
export const legacyRedirects: Record<string, string> = {
  "/realms": "/config/realms",
  "/stages": "/config/stages",
  "/weapons": "/config/gear",
  "/items": "/config/items",
  "/skills": "/config/skills",
  "/buildings": "/config/buildings",
  "/releases": "/publish/client",
  "/rules": "/config/combat",
  "/puppets": "/config/combat?tab=sim",
  "/announcements": "/ops/announcements",
  "/popups": "/ops/popups",
  "/operations": "/system/audit",
  "/ops/mail": "/ops/announcements",
  "/ops/gifts": "/ops/announcements",
  "/ops/codes": "/ops/announcements",
  "/ops/shop": "/ops/announcements",
};
