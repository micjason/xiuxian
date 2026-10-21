/**
 * 第三批：首领规则、章节、立绘（后台共用）。
 * 规则字段和服务端 backend/src/modules/content/boss-rules.ts 一一对应；立绘 / 背景缩略图在 admin/public/art（和游戏客户端的图同名）。
 */
import { api } from "../api";

export type BossTier = "elite" | "chief";
export type GearQuality = "white" | "green" | "blue" | "purple" | "orange";
export type StatMulKey = "hp" | "attack" | "defense";
export type BossRuleSet = {
  statMode: "auto" | "manual";
  statMul: Record<StatMulKey, number>;
  allowRepeat: boolean;
  repeatRewards: boolean;
  dailyRewardLimit: number;
  gearQualityPct: Record<GearQuality, number>;
  autoChallenge: boolean;
  autoChallengePowerPct: number;
  autoChallengeRetrySeconds: number;
  unlockNeedsBossWin: boolean;
  unlockNeedsRealm: boolean;
};
export type BossRules = Record<BossTier, BossRuleSet>;
/** 单关覆盖：只存改过的项（倍率、品质按小项） */
export type BossRuleOverride = Partial<Omit<BossRuleSet, "statMul" | "gearQualityPct">> & { statMul?: Partial<Record<StatMulKey, number>>; gearQualityPct?: Partial<Record<GearQuality, number>> };
export type ScalarRuleKey = Exclude<keyof BossRuleSet, "statMul" | "gearQualityPct">;

export const TIER_NAME: Record<BossTier, string> = { elite: "小首领 · 精英", chief: "大首领 · 章末" };
export const TIER_SHORT: Record<BossTier, string> = { elite: "精英", chief: "章末" };
export const GEAR_QUALITIES: { key: GearQuality; name: string; color: string }[] = [
  { key: "white", name: "白", color: "#b9bfbb" },
  { key: "green", name: "绿", color: "#2f7d53" },
  { key: "blue", name: "蓝", color: "#2f6fb0" },
  { key: "purple", name: "紫", color: "#7a4bb5" },
  { key: "orange", name: "橙", color: "#a85a0f" },
];
export const STAT_MULS: { key: StatMulKey; name: string }[] = [
  { key: "hp", name: "气血" },
  { key: "attack", name: "攻击" },
  { key: "defense", name: "防御" },
];

/** 规则的问号说明（ADMIN_SPEC §11） */
export const RULE_HELP: Record<string, string> = {
  statMul: "精英属性 = 本关第一只普通怪 × 倍数（四舍五入），出手间隔和普通怪一样。关卡里可以单独改倍数，也可以直接改某一项属性。",
  statMode: "自动 = 按上面的倍率从本关普通怪算；手填 = 每关自己填攻防血和出手间隔。",
  allowRepeat: "首通之后还能不能再打这个首领。",
  repeatRewards: "首通之后再赢有没有奖励（消耗每日次数）。不给 = 只有首通奖励。",
  dailyRewardLimit: "每天能拿重打奖励的次数，每日重置整点（挂机与战斗节奏）换天；用完仍可打，没奖励。0 = 不给重打奖励。",
  gearQualityPct: "首领给 1 件本境界装备时（首通奖励里的「随机装备」和每次有奖励的重打）按这个抽品质，合计必须 100%。",
  autoChallenge: "挂机中满足下面的条件时，服务器结算时自动挑战本关首领（每次最多打一场）。",
  autoChallengePowerPct: "挂机中玩家战力 ≥ 推荐战力 × 这个比例时，自动挑战首领。",
  autoChallengeRetrySeconds: "自动挑战输了以后，隔多少秒再自动试一次。",
  unlock: "下一关什么时候解锁：需要击败本关首领、需要达到下一关的境界（两个都开 = 两个都要满足）。",
};

export function cloneRules<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

/** 默认值 + 单关覆盖 → 生效值 */
export function resolveRules(defaults: BossRuleSet, override: BossRuleOverride | null | undefined): BossRuleSet {
  const out = cloneRules(defaults);
  if (!override) return out;
  for (const [key, value] of Object.entries(override)) {
    if (value === undefined || value === null) continue;
    if (key === "statMul" || key === "gearQualityPct") {
      Object.assign(out[key], Object.fromEntries(Object.entries(value as object).filter(([, v]) => v !== undefined && v !== null)));
    } else {
      (out as Record<string, unknown>)[key] = value;
    }
  }
  return out;
}

/** 单关改过几项（倍率、品质按小项算） */
export function overrideCount(override: BossRuleOverride | null | undefined): number {
  if (!override) return 0;
  let count = 0;
  for (const [key, value] of Object.entries(override)) {
    if (value === undefined || value === null) continue;
    count += key === "statMul" || key === "gearQualityPct" ? Object.values(value as object).filter((v) => v !== undefined && v !== null).length : 1;
  }
  return count;
}

export function qualityTotal(pct: Record<GearQuality, number>): number {
  return Math.round(GEAR_QUALITIES.reduce((sum, q) => sum + (Number(pct[q.key]) || 0), 0) * 100) / 100;
}

export type ArtCatalog = {
  monsters: { key: string; name: string; sprite: string }[];
  chapterBackgrounds: { key: string; name: string; image: string }[];
  bossFx: { key: string; name: string }[];
};
let artLoading: Promise<ArtCatalog> | null = null;
export function loadArtKeys(): Promise<ArtCatalog> {
  if (!artLoading) {
    artLoading = api<ArtCatalog>("/admin/draft/art-keys").catch((cause: unknown) => {
      artLoading = null;
      throw cause;
    });
  }
  return artLoading;
}
/** 立绘缩略图（admin/public/art/mon_<key>.png，和游戏 res://assets/art/q/sprites/mon_<key>.png 同名） */
export function monsterThumb(key: string | null | undefined): string {
  return key ? `${import.meta.env.BASE_URL}art/mon_${key}.png` : "";
}
/** 章节战斗区背景缩略图（admin/public/art/bg_<key>.webp；游戏里是 bg_<key>_1080x960） */
export function chapterBgThumb(key: string | null | undefined): string {
  return key ? `${import.meta.env.BASE_URL}art/bg_${key}.webp` : "";
}

export type ChapterRow = {
  id: string;
  displayName: string;
  sortOrder: number;
  bgKey: string;
  bossFx: string;
  chiefStageSlug: string | null;
  effectiveChiefStageSlug: string | null;
  enabled: boolean;
  stages: { id: string; displayName: string; sortOrder: number; realmCode: number; chief: boolean }[];
  updatedAt?: string;
};
export function loadChapters(): Promise<ChapterRow[]> {
  return api<ChapterRow[]>("/admin/draft/chapters");
}

export type BossRulesView = {
  rules: BossRules;
  defaults: BossRules;
  usage: Record<BossTier, { stages: number; customized: number; customizedStages: { id: string; displayName: string; customCount: number }[] }>;
};
export function loadBossRules(): Promise<BossRulesView> {
  return api<BossRulesView>("/admin/draft/boss-rules");
}
