// 装备稀有度：按品质名映射到 1..6，对应 tokens.css 里的 --xx-rarity-1..6。
// 品质统一为 白/绿/蓝/紫/橙 五档（服务端品质表 catalog.ts；红已去掉）。
const order = ["白", "绿", "蓝", "紫", "橙"];

export function rarityOf(qualityName: string): number {
  const index = order.indexOf(qualityName);
  return index < 0 ? 1 : index + 1;
}
