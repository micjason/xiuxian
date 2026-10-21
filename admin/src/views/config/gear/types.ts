// 装备配置页（公式装备 + 手动装备 + 套装）共用的类型。
export type Quality = "white" | "green" | "blue" | "purple" | "orange";
export type StatKey = "attack" | "defense" | "hp" | "speed";
export const STAT_KEYS: StatKey[] = ["attack", "defense", "hp", "speed"];
export const STAT_LABEL: Record<StatKey, string> = { attack: "攻击", defense: "防御", hp: "气血", speed: "速度" };
export const QUALITY_BG: Record<string, string> = { white: "#eceeea", green: "#e3f1e5", blue: "#e2ecf7", purple: "#efe6f7", orange: "#fbeadb" };

export type QualityRow = { key: Quality; name: string; short: string; color: string };
export type SlotRow = { key: string; name: string; glyph?: string };

export type DesignatedUse = { stageId: string; stageName: string; trigger: string; chancePercent: number; count: number };

export type ManualPiece = {
  id: string;
  origin: "manual";
  displayName: string;
  description: string;
  iconKey: string;
  slot: string;
  slotName: string;
  quality: Quality;
  qualityName: string;
  requiredRealmOrder: number;
  realmName: string;
  majorKey: string | null;
  majorName: string;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  power: number | null;
  setSlug: string | null;
  setName: string | null;
  randomDrop: boolean;
  dropMult: number;
  enabled: boolean;
  designated: DesignatedUse[];
};

export type SetStatRow = { stat: StatKey; mode: "pct" | "flat"; value: number };
export type SetTier = { pieces: number; stats: SetStatRow[] };
export type GearSet = {
  id: string;
  displayName: string;
  description: string;
  tiers: SetTier[];
  members: { id: string; displayName: string; slot: string; slotName: string; quality: Quality; iconKey: string; attack: number; defense: number; hp: number; speed: number }[];
  majorName: string;
  majorKey: string | null;
  quality: Quality | "mixed" | null;
  updatedAt: string;
};

export type FormulaPiece = { id: string; slot: string; quality: Quality; attack: number; defense: number; hp: number; speed: number; power: number | null; displayName: string };
export type MajorInfo = { majorKey: string; majorName: string; requiredRealmOrder: number; pieces: FormulaPiece[] };
export type RealmInfo = { code: number; displayName: string; majorName: string; majorKey?: string | null };

export function powerOf(stats: Record<StatKey, number | null | undefined>, weights: Record<StatKey, number> | null): number | null {
  if (!weights) return null;
  return Math.round((stats.attack ?? 0) * weights.attack + (stats.defense ?? 0) * weights.defense + (stats.hp ?? 0) * weights.hp + (stats.speed ?? 0) * weights.speed);
}

export function fmtStat(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(2).replace(/\.?0+$/, "");
}

export function tierText(tier: SetTier): string {
  return tier.stats.map((row) => `${STAT_LABEL[row.stat]} +${fmtStat(row.value)}${row.mode === "pct" ? "%" : ""}`).join(" · ");
}
