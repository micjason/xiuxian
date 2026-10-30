/**
 * 第三批：首领规则、章节、立绘（后台共用）。
 * 规则字段和服务端 backend/src/modules/content/boss-rules.ts 一一对应；立绘 / 背景缩略图在 admin/public/art（和游戏客户端的图同名）。
 */
import { api } from "../api";

/** 首领外观档次（第四批起只管画面：章末关用章末的边框 / 特效，规则只有一套） */
export type BossTier = "elite" | "chief";
export type GearQuality = "white" | "green" | "blue" | "purple" | "orange";
export type StatMulKey = "hp" | "attack" | "defense";
/** 每关可单独改的一套规则（第四批：不再分精英 / 章末两列） */
export type BossRuleSet = {
  statMode: "auto" | "manual";
  statMul: Record<StatMulKey, number>;
  allowRepeat: boolean;
  repeatRewards: boolean;
  gearQualityPct: Record<GearQuality, number>;
  repeatGearQualityPct: Record<GearQuality, number>;
  autoChallenge: boolean;
  autoChallengePowerPct: number;
  autoChallengeRetrySeconds: number;
  idleSpawn: boolean;
  idleSpawnWaves: number;
  idleSpawnCountsDaily: boolean;
  unlockNeedsBossWin: boolean;
  unlockNeedsRealm: boolean;
};
/** 配置概览的首领规则 = 一套默认规则 + 只有全局的两项 */
export type BossRules = BossRuleSet & { dailyChallengeTotal: number; idleSpawnMaxPerSettle: number };
export type GroupRuleKey = "statMul" | "gearQualityPct" | "repeatGearQualityPct";
/** 单关覆盖：只存改过的项（倍率、品质按小项） */
export type BossRuleOverride = Partial<Omit<BossRuleSet, GroupRuleKey>> & {
  statMul?: Partial<Record<StatMulKey, number>>;
  gearQualityPct?: Partial<Record<GearQuality, number>>;
  repeatGearQualityPct?: Partial<Record<GearQuality, number>>;
};
export type ScalarRuleKey = Exclude<keyof BossRuleSet, GroupRuleKey>;
export const GROUP_RULE_KEYS: GroupRuleKey[] = ["statMul", "gearQualityPct", "repeatGearQualityPct"];

/** 读不到首领规则时的占位（和服务端 DEFAULT_BOSS_RULES 一样） */
export const FALLBACK_BOSS_RULES: BossRules = {
  statMode: "auto",
  statMul: { hp: 6.5, attack: 1.55, defense: 1.4 },
  allowRepeat: true,
  repeatRewards: true,
  gearQualityPct: { white: 0, green: 70, blue: 25, purple: 5, orange: 0 },
  repeatGearQualityPct: { white: 0, green: 50, blue: 35, purple: 13, orange: 2 },
  autoChallenge: true,
  autoChallengePowerPct: 100,
  autoChallengeRetrySeconds: 60,
  idleSpawn: true,
  idleSpawnWaves: 1000,
  idleSpawnCountsDaily: false,
  unlockNeedsBossWin: true,
  unlockNeedsRealm: true,
  dailyChallengeTotal: 5,
  idleSpawnMaxPerSettle: 20,
};

export const TIER_NAME: Record<BossTier, string> = { elite: "首领", chief: "首领 · 章末关" };
export const TIER_SHORT: Record<BossTier, string> = { elite: "首领", chief: "章末关" };
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

/** 规则的问号说明（第四批：一套规则） */
export const RULE_HELP: Record<string, string> = {
  statMul: "首领属性 = 本关第一只普通怪 × 倍数（四舍五入），出手间隔和普通怪一样。关卡里可以单独改倍数，也可以直接改某一项属性。本关没有普通怪时用首领自己填的数。",
  statMode: "自动 = 按上面的倍率从本关普通怪算；手填 = 每关自己填攻防血和出手间隔（原章末首领迁移后是手填）。",
  allowRepeat: "击败之后还能不能手动再打这个首领（挂机刷首领不看这一项）。",
  repeatRewards: "击败过以后再赢（手动重打、挂机刷出来的首领）给不给重复奖励。不给 = 只有首通奖励。",
  dailyChallengeTotal: "所有首领合计，每天能拿几次重复奖励。手动重打赢了算 1 次；还没击败过的首领第一次挑战不算；挂机刷出来的首领看下面「算不算每日次数」。用完了照样能打，但没有奖励。每日重置整点（挂机与战斗节奏）换天。",
  gearQualityPct: "首通奖励里的「随机装备」按这个抽品质，合计必须 100%。",
  repeatGearQualityPct: "重复奖励里的装备按这个抽品质，合计必须 100%。",
  autoChallenge: "还没击败的首领：挂机中满足下面的条件时，服务器结算时自动挑战（每次最多打一场）。",
  autoChallengePowerPct: "挂机中玩家战力 ≥ 推荐战力 × 这个比例时，自动挑战首领。",
  autoChallengeRetrySeconds: "自动挑战输了以后，隔多少秒再自动试一次。",
  idleSpawn: "已击败的首领：在本关挂机每刷够 N 波小怪，自动打一次首领（离线也算，按离线时长折算波数）。",
  idleSpawnWaves: "每多少波小怪刷一次首领。",
  idleSpawnCountsDaily: "挂机刷出来的首领算不算「每日首领挑战总次数」。不算（默认）= 不消耗次数，次数用完了照样有奖励；算 = 有次数时消耗 1 次给奖励，用完了照样打但没有奖励。",
  idleSpawnMaxPerSettle: "一次结算最多打几只挂机首领（离线很久时防止一次打太多），多出来的不补。",
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
    if ((GROUP_RULE_KEYS as string[]).includes(key)) {
      Object.assign(out[key as GroupRuleKey], Object.fromEntries(Object.entries(value as object).filter(([, v]) => v !== undefined && v !== null)));
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
    count += (GROUP_RULE_KEYS as string[]).includes(key) ? Object.values(value as object).filter((v) => v !== undefined && v !== null).length : 1;
  }
  return count;
}

export function qualityTotal(pct: Record<GearQuality, number>): number {
  return Math.round(GEAR_QUALITIES.reduce((sum, q) => sum + (Number(pct[q.key]) || 0), 0) * 100) / 100;
}

export type ArtCatalog = {
  monsters: { key: string; name: string; sprite: string }[];
  /** 第四批：统一首领立绘 boss_*（只给首领选） */
  bosses?: { key: string; name: string; sprite: string }[];
  /** 第四批：章节战斗背景（首领战斗页 1080×1640） */
  battleBackgrounds?: { key: string; name: string; image: string }[];
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
/**
 * 立绘缩略图（admin/public/art/mon_<key>.png，和游戏 res://assets/art/q/sprites/mon_<key>.png 同名）。
 * 第四批：统一首领立绘 boss_<怪> → art/boss_<怪>.png（游戏 sprites/boss_<怪>.png）；精英 / 章末两套预渲染图（elite_* / chief_*）已废弃（SPEC_Q §17.10），不再引用。
 * tier 参数只为兼容旧调用，不再影响缩略图。
 */
export function monsterThumb(key: string | null | undefined, _tier?: "elite" | "chief" | null): string {
  if (!key) {
    return "";
  }
  return key.startsWith("boss_") ? `${import.meta.env.BASE_URL}art/${key}.png` : `${import.meta.env.BASE_URL}art/mon_${key}.png`;
}
/** 章节首领战斗页背景缩略图（admin/public/art/bg_battle_<key>.webp；游戏里是 bg_battle_<key>_1080x1640） */
export function battleBgThumb(key: string | null | undefined): string {
  return key ? `${import.meta.env.BASE_URL}art/bg_battle_${key}.webp` : "";
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
  /** 第四批：首领战斗页背景；null = 跟随 bgKey */
  battleBgKey?: string | null;
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
  usage: { stages: number; customized: number; customizedStages: { id: string; displayName: string; customCount: number }[] };
};
export function loadBossRules(): Promise<BossRulesView> {
  return api<BossRulesView>("/admin/draft/boss-rules");
}
