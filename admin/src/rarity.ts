// 装备稀有度：按品质名映射到 1..6，对应 tokens.css 里的 --xx-rarity-1..6。
// 现有后台品质为 白/绿/蓝/紫/橙 五档，设计计划书规划的第六档为 红（仙品）。
const order = ["白", "绿", "蓝", "紫", "橙", "红"];

export function rarityOf(qualityName: string): number {
  const index = order.indexOf(qualityName);
  return index < 0 ? 1 : index + 1;
}
