/**
 * 关卡顺序、章末关、首领档次和解锁（第三批，纯函数，只看内容快照和玩家进度）。
 *
 * 顺序：章节 sortOrder → 关卡 sortOrder → 所需境界 → 编号。没有章节的关卡排在最后（发布校验会报错）。
 * 章末关：章节手动指定的 chiefStageSlug；没指定 = 本章（启用的）关卡里排最后的一关（sortOrder 最大）。
 * 档次：章末关的首领是大首领（chief），其余是小首领（elite）。没有章节的关卡单独算一章，所以是 chief（和第三批之前一样）。
 *
 * 解锁（ADMIN_SPEC §11「解锁下一关」，规则取上一关首领的生效规则）：
 * - 第一关默认解锁；
 * - 后面的关：玩家有这一关的进度行（老玩家迁移补的、或以前解锁过的），或者上一关已解锁且（不要求击败首领 / 上一关首领已首通）；
 *   上一关没有首领（老数据）时只看境界；
 * - 能进（挂机、挑战）= 已解锁 且（不要求境界 / 境界 ≥ 本关所需境界）。第一关永远要求境界。
 */
import { DEFAULT_BOSS_RULES, resolveBossRules, type BossRuleSet, type BossTier } from "./boss-rules.js";
import type { ContentSnapshot } from "./validate.js";

type Stage = ContentSnapshot["stages"][number];
type Chapter = NonNullable<ContentSnapshot["chapters"]>[number];

function chapterRank(world: Pick<ContentSnapshot, "chapters">): Map<string, number> {
  const ranked = [...(world.chapters ?? [])].sort((a, b) => a.sortOrder - b.sortOrder || a.slug.localeCompare(b.slug));
  return new Map(ranked.map((row, index) => [row.slug, index]));
}

function compareInChapter(a: Pick<Stage, "slug" | "sortOrder" | "requiredRealmOrder">, b: Pick<Stage, "slug" | "sortOrder" | "requiredRealmOrder">): number {
  return (a.sortOrder ?? 0) - (b.sortOrder ?? 0) || (a.requiredRealmOrder ?? 0) - (b.requiredRealmOrder ?? 0) || a.slug.localeCompare(b.slug);
}

/** 启用的关卡按游戏顺序排好。 */
export function orderedStages<S extends Pick<Stage, "slug" | "sortOrder" | "requiredRealmOrder" | "enabled" | "chapterSlug">>(world: { stages: S[]; chapters?: ContentSnapshot["chapters"] }): S[] {
  const rank = chapterRank(world);
  const rankOf = (stage: S) => (stage.chapterSlug != null && rank.has(stage.chapterSlug) ? rank.get(stage.chapterSlug)! : Number.MAX_SAFE_INTEGER);
  return world.stages.filter((stage) => stage.enabled).sort((a, b) => rankOf(a) - rankOf(b) || compareInChapter(a, b));
}

/** 本章的章末关编号（手动指定优先，否则本章启用关卡里排最后的一关）；本章没有启用的关卡返回 null。 */
export function chiefStageOf(chapter: Pick<Chapter, "slug" | "chiefStageSlugSetting">, stages: Pick<Stage, "slug" | "sortOrder" | "requiredRealmOrder" | "enabled" | "chapterSlug">[]): string | null {
  if (chapter.chiefStageSlugSetting) {
    return chapter.chiefStageSlugSetting;
  }
  const own = stages.filter((stage) => stage.enabled && stage.chapterSlug === chapter.slug).sort(compareInChapter);
  return own[own.length - 1]?.slug ?? null;
}

/** 关卡首领的档次。快照里已经算好的直接用。 */
export function stageTier(world: Pick<ContentSnapshot, "chapters">, stage: Pick<Stage, "slug" | "chapterSlug" | "tier">): BossTier {
  if (stage.tier) {
    return stage.tier;
  }
  const chapter = stage.chapterSlug ? world.chapters?.find((row) => row.slug === stage.chapterSlug) : undefined;
  if (!chapter) {
    return "chief";
  }
  return chapter.chiefStageSlug === stage.slug ? "chief" : "elite";
}

/** 首领生效的规则：快照里合并好的直接用；手写的世界按档次取配置概览默认值 + 单关覆盖。 */
export function bossRulesFor(world: ContentSnapshot, stage: Stage): BossRuleSet {
  const boss = stage.bosses?.[0];
  if (boss?.rules) {
    return boss.rules;
  }
  const tier = stageTier(world, stage);
  const defaults = world.globals.tuning?.bossRules?.[tier] ?? DEFAULT_BOSS_RULES[tier];
  return resolveBossRules(defaults, boss?.ruleOverride ?? null);
}

export type StageProgressRow = { stageSlug: string; firstClearedAt: Date | null };

export type StageAccess = {
  slug: string;
  /** 已解锁（不看境界）。 */
  unlocked: boolean;
  /** 本关的境界条件满足（不要求境界时恒为 true）。 */
  realmOk: boolean;
  /** 能挂机、能挑战 = unlocked && realmOk。 */
  playable: boolean;
  /** 本关首领已首通。 */
  cleared: boolean;
  /** 解锁条件（客户端显示「✓ 击败上一关精英 ✗ 需筑基一层」用）。 */
  needs: {
    bossWin: { stageSlug: string; bossName: string; tier: BossTier; met: boolean } | null;
    realm: { order: number; met: boolean } | null;
  };
};

/** 每个启用关卡的解锁情况（按游戏顺序）。 */
export function stageAccessList(world: ContentSnapshot, realmOrder: number, progress: StageProgressRow[]): StageAccess[] {
  const rows = new Map(progress.map((row) => [row.stageSlug, row]));
  const ordered = orderedStages(world);
  const out: StageAccess[] = [];
  let previous: { stage: Stage; access: StageAccess } | null = null;
  for (const stage of ordered) {
    const own = rows.get(stage.slug);
    const cleared = Boolean(own?.firstClearedAt);
    const required = stage.requiredRealmOrder ?? 0;
    let unlocked: boolean;
    let needsBoss: StageAccess["needs"]["bossWin"] = null;
    let needsRealm = true;
    if (!previous) {
      unlocked = true;
    } else {
      const prevBoss = previous.stage.bosses?.[0];
      const prevRules = bossRulesFor(world, previous.stage);
      needsRealm = prevRules.unlockNeedsRealm;
      if (prevBoss && prevRules.unlockNeedsBossWin) {
        needsBoss = { stageSlug: previous.stage.slug, bossName: prevBoss.name, tier: stageTier(world, previous.stage), met: previous.access.cleared };
      }
      unlocked = Boolean(own) || (previous.access.unlocked && (needsBoss ? needsBoss.met : true));
    }
    const realmOk = !needsRealm || realmOrder >= required;
    const access: StageAccess = {
      slug: stage.slug,
      unlocked,
      realmOk,
      playable: unlocked && realmOk,
      cleared,
      needs: { bossWin: needsBoss, realm: needsRealm ? { order: required, met: realmOrder >= required } : null },
    };
    out.push(access);
    previous = { stage, access };
  }
  return out;
}

/** 游戏顺序里的下一关（启用的）。 */
export function nextStageOf(world: ContentSnapshot, slug: string): Stage | null {
  const ordered = orderedStages(world);
  const index = ordered.findIndex((stage) => stage.slug === slug);
  return index >= 0 ? (ordered[index + 1] ?? null) : null;
}
