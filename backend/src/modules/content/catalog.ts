/**
 * 部位表、品质表：服务端唯一的一份（批次②统一）。/content/current 的 globals.slots / globals.qualities 下发给游戏和后台，
 * 两边都按这里的名字显示，不再各写一套。加一个品质 / 部位 = 在这里加一行（装备生成系数、强化规则、掉落权重会按 key 读）。
 * 红（仙品）已经去掉（迁移 0028 把旧数据并到橙）。
 */
export type SlotKey = "weapon" | "clothes" | "helmet" | "gloves" | "shoes" | "accessory";
export type QualityKey = "white" | "green" | "blue" | "purple" | "orange";

export type SlotRow = { key: SlotKey; name: string; glyph: string; sortOrder: number };
export type QualityRow = { key: QualityKey; name: string; short: string; color: string; sortOrder: number };

export const SLOT_TABLE: readonly SlotRow[] = [
  { key: "weapon", name: "武器", glyph: "剑", sortOrder: 1 },
  { key: "clothes", name: "衣服", glyph: "袍", sortOrder: 2 },
  { key: "helmet", name: "头冠", glyph: "冠", sortOrder: 3 },
  { key: "gloves", name: "护手", glyph: "护", sortOrder: 4 },
  { key: "shoes", name: "鞋子", glyph: "靴", sortOrder: 5 },
  { key: "accessory", name: "饰品", glyph: "佩", sortOrder: 6 },
];

export const QUALITY_TABLE: readonly QualityRow[] = [
  { key: "white", name: "凡品", short: "白", color: "#9aa3a0", sortOrder: 1 },
  { key: "green", name: "良品", short: "绿", color: "#3c9a4e", sortOrder: 2 },
  { key: "blue", name: "精品", short: "蓝", color: "#2e7fc4", sortOrder: 3 },
  { key: "purple", name: "珍品", short: "紫", color: "#8a4fc0", sortOrder: 4 },
  { key: "orange", name: "绝品", short: "橙", color: "#e07b1f", sortOrder: 5 },
];

export const SLOT_KEYS = SLOT_TABLE.map((row) => row.key);
export const QUALITY_KEYS = QUALITY_TABLE.map((row) => row.key);

export function isSlotKey(value: unknown): value is SlotKey {
  return typeof value === "string" && (SLOT_KEYS as string[]).includes(value);
}

export function isQualityKey(value: unknown): value is QualityKey {
  return typeof value === "string" && (QUALITY_KEYS as string[]).includes(value);
}

export function slotName(key: string | null | undefined): string {
  return SLOT_TABLE.find((row) => row.key === key)?.name ?? "";
}

export function qualityRow(key: string | null | undefined): QualityRow | undefined {
  return QUALITY_TABLE.find((row) => row.key === key);
}
