import { breakMaterialProblems, enhanceRulesFromInput } from "./enhance.js";
import { stagePowerErrors } from "./stage-power.js";
import type { BossRepeatReward, BossRewardEntry, MonsterDropConfig, OptionalRuleValues, StageMonster } from "./combat-types.js";
import { bossRuleProblems, type BossRuleOverride, type BossRuleSet, type BossStatKey, type BossTier } from "./boss-rules.js";
import { BOSS_ART_KEY_SET, CHAPTER_BATTLE_BG_KEY_SET, CHAPTER_BG_KEY_SET, CHAPTER_BOSS_FX_SET, MONSTER_ART_KEY_SET } from "./art-keys.js";

const SLUG = /^[a-z][a-z0-9_]{1,47}$/;

export type ContentError = { kind: string; slug: string; field: string; message: string };

export type ContentSnapshot = {
  globals: {
    startingRealmSlug: string;
    starterItems: { itemSlug: string; quantity: number }[];
    offlineCapSeconds?: number;
    bagCapacity?: number;
    powerWeights?: { attack: number; defense: number; hp: number; speed: number };
    combat?: {
      baseInterval?: number;
      minInterval?: number;
      challengeCooldownSeconds?: number;
      timeLimitSeconds?: number;
      defenseConstant?: number;
      speedBase?: number;
      recommendedPowerMargin?: number;
      gearSpeedFactor?: number;
    } & OptionalRuleValues;
    enhance?: import("./enhance.js").EnhanceRules;
    tuning?: import("./tuning.js").Tuning;
    artSlotRules?: { minRealmOrder: number; slots: number }[];
    /** 统一部位表 / 品质表（catalog.ts），游戏和后台都按这里的名字显示。 */
    slots?: readonly import("./catalog.js").SlotRow[];
    qualities?: readonly import("./catalog.js").QualityRow[];
  };
  realms: {
    slug: string;
    displayName?: string;
    sortOrder?: number;
    nextRealmSlug: string | null;
    tickSeconds: number;
    gainPerTick: number;
    breakthroughCost: number;
    baseAttack?: number;
    baseDefense?: number;
    baseHp?: number;
    baseSpeed?: number;
    baseInterval?: number;
    majorKey?: string;
    majorName?: string;
    ultName?: string;
    ultDamageMultBp?: number;
    ultCooldownSeconds?: number;
    ultFirstCooldownSeconds?: number;
    requiredStageSlug: string | null;
    recommendedPower: number;
    enabled: boolean;
  }[];
  stages: {
    slug: string;
    displayName?: string;
    sortOrder?: number;
    requiredRealmOrder?: number;
    nextStageSlug: string | null;
    bossDropTableSlug: string;
    idleDropTableSlug: string;
    firstClearDropTableSlug: string;
    bossName?: string;
    bossAttack?: number;
    bossDefense?: number;
    bossHp: number;
    bossInterval: number;
    bosses?: {
      name: string;
      attack: number;
      defense: number;
      hp: number;
      interval: number;
      drops: { itemSlug: string; chanceBp: number }[];
      reward?: { major: string; stageIndex: number; nextMajor: string | null };
      firstClear?: BossRewardEntry[];
      repeat?: BossRepeatReward;
      /** 立绘编号（精英没填时 = 本关普通怪的立绘，快照里已经填好）。 */
      artKey?: string;
      /** 小首领（精英）/ 大首领（章末），快照按章节算好。 */
      tier?: BossTier;
      /** 生效的首领规则（全局默认 + 单关覆盖，快照里已经合并好）。 */
      rules?: BossRuleSet;
      /** 单关覆盖（原样，后台和校验用）。 */
      ruleOverride?: BossRuleOverride | null;
      statsCustom?: BossStatKey[];
      /** 属性是不是按普通怪 × 倍率自动算的（快照里 attack/defense/hp/interval 已经是算好的数）。 */
      statsAuto?: boolean;
      /** 自动属性但本关没有普通怪：算不出来（发布校验报错）。 */
      statsProblem?: string;
    }[];
    monsters?: StageMonster[];
    monsterDrop?: MonsterDropConfig | null;
    /** 指定掉落（和随机掉落同时生效）。 */
    designatedDrops?: import("./combat-types.js").DesignatedDrop[];
    /** 生效的种子掉落（快照已合并全局 + 覆盖）。 */
    seedDrops?: import("./seed-drops.js").SeedDropEntry[];
    /** 单关覆盖原样；null = 跟随全局。 */
    seedDropsOverride?: import("./seed-drops.js").SeedDropEntry[] | null;
    recommendedPower: number;
    enabled: boolean;
    /** 所属章节；null = 没有章节（发布校验报错；运行时这一关单独算一章，首领按章末规则）。 */
    chapterSlug?: string | null;
    /** 本关首领的档次（= bosses[0].tier）。 */
    tier?: BossTier;
  }[];
  /** 章节（第三批）。chiefStageSlug 是算好的章末关（手动指定的，或本章 sortOrder 最大的一关）。 */
  chapters?: {
    slug: string;
    displayName: string;
    sortOrder: number;
    bgKey: string;
    bossFx: string;
    /** 第四批：首领战斗页背景（null = 跟随 bgKey）。 */
    battleBgKey?: string | null;
    /** 后台手动指定的章末关（null = 自动）。 */
    chiefStageSlugSetting: string | null;
    chiefStageSlug: string | null;
    enabled: boolean;
  }[];
  dropTables: {
    slug: string;
    entries: { itemSlug: string; chanceBp: number; minQty: number; maxQty: number }[];
  }[];
  items: {
    slug: string;
    displayName?: string;
    /** 物品说明（玩家物品详情里显示；v14 起下发给客户端）。 */
    description?: string;
    kind: string | null;
    slot: string | null;
    skillSlug: string | null;
    attack?: number;
    defense?: number;
    hp?: number;
    speed?: number;
    quality?: string;
    requiredRealmOrder?: number;
    stackable?: boolean;
    /** 后台给这件装备指定的图标（空 = 客户端按大境界 + 部位自动选） */
    iconKey?: string;
    /** 装备掉率倍数（默认 1） */
    dropMult?: number;
    /** formula = 公式生成；manual = 后台手动新建（gear_m_0001…） */
    origin?: "formula" | "manual";
    /** 所属套装 */
    setSlug?: string | null;
    /** 参与本境界本品质的随机掉落池（手动装备默认不参与） */
    randomDrop?: boolean;
    enabled: boolean;
  }[];
  /** 套装：成员是 setSlug 指向它的装备；tiers 按件数升序。 */
  gearSets?: {
    slug: string;
    displayName: string;
    description: string;
    tiers: import("./combat-types.js").SetTier[];
    members: string[];
  }[];
  skills: {
    slug: string;
    displayName?: string;
    role?: string | null;
    attack?: number;
    defense?: number;
    hp?: number;
    speed?: number;
    cultivateBonusBp?: number;
    requiredRealmOrder?: number;
    prerequisiteSkillSlugs: string[];
    rank?: string | null;
    enabled: boolean;
  }[];
};

const EQUIPMENT_SLOTS = new Set(["weapon", "helmet", "clothes", "gloves", "shoes", "accessory"]);
const QUALITY_ORDER = ["white", "green", "blue", "purple", "orange"];

const STAT_KEYS = ["attack", "defense", "hp", "speed"] as const;

export function equipmentPowerErrors(items: ContentSnapshot["items"]): { slug: string; message: string }[] {
  const errors: { slug: string; message: string }[] = [];
  // 手动装备数值由策划手填，不要求和公式装备成比例。
  const gear = items.filter((item) => item.kind === "equipment" && item.enabled && item.origin !== "manual");
  const bySlot = new Map<string, ContentSnapshot["items"]>();
  for (const item of gear) {
    const slot = `${item.slot ?? ""}:${item.requiredRealmOrder ?? 0}`;
    bySlot.set(slot, [...(bySlot.get(slot) ?? []), item]);
  }
  for (const rows of bySlot.values()) {
    const byQuality = new Map<string, ContentSnapshot["items"][number]>();
    let crowded = false;
    for (const item of rows) {
      const quality = item.quality ?? "white";
      if (byQuality.has(quality)) {
        crowded = true;
        break;
      }
      byQuality.set(quality, item);
    }
    if (crowded) {
      continue;
    }
    const ordered = QUALITY_ORDER.flatMap((quality) => {
      const item = byQuality.get(quality);
      return item ? [item] : [];
    });
    const base = ordered[0];
    if (!base) {
      continue;
    }
    for (const item of ordered.slice(1)) {
      const scales: number[] = [];
      let broken = false;
      for (const key of STAT_KEYS) {
        const from = base[key] ?? 0;
        const to = item[key] ?? 0;
        if (from === 0 && to === 0) {
          continue;
        }
        if (from === 0 || to === 0) {
          broken = true;
          break;
        }
        scales.push(to / from);
      }
      const sameScale = scales.length === 0 || scales.every((scale) => Math.abs(scale - (scales[0] ?? 0)) <= 0.02);
      if (broken || !sameScale) {
        errors.push({
          slug: item.slug,
          message: `部位 ${item.slot ?? "未填"}、境界 ${item.requiredRealmOrder ?? 0} 的「${item.displayName ?? item.slug}」和同部位低品质装备的属性比例不一致`,
        });
      }
    }
  }
  return errors;
}

/** 关卡有首领：配了首领列表，或者老写法里填了首领气血/名称。 */
export function hasBoss(stage: { bosses?: unknown[]; bossHp: number; bossName?: string }): boolean {
  return (stage.bosses ?? []).length > 0 || stage.bossHp > 0 || Boolean(stage.bossName);
}

export function validateContent(
  draft: ContentSnapshot,
  knownSlugs: { realms: string[]; stages: string[]; items: string[]; skills: string[]; dropTables: string[] } = {
    realms: [],
    stages: [],
    items: [],
    skills: [],
    dropTables: [],
  },
): { errors: ContentError[]; warnings: ContentError[] } {
  const errors: ContentError[] = [];
  const warnings: ContentError[] = [];
  const push = (kind: string, slug: string, field: string, message: string) => errors.push({ kind, slug, field, message });
  const warn = (kind: string, slug: string, field: string, message: string) => warnings.push({ kind, slug, field, message });

  for (const [kind, rows] of [
    ["realm", draft.realms],
    ["stage", draft.stages],
    ["item", draft.items],
    ["skill", draft.skills],
    ["dropTable", draft.dropTables],
  ] as const) {
    const seen = new Set<string>();
    for (const row of rows) {
      if (!SLUG.test(row.slug)) {
        push(kind, row.slug, "slug", "编号格式不正确");
      }
      if (seen.has(row.slug)) {
        push(kind, row.slug, "slug", "编号重复");
      }
      seen.add(row.slug);
    }
  }

  if (draft.items.some((item) => item.kind === "equipment" && item.enabled)) {
    try {
      const rules = enhanceRulesFromInput(draft.globals.enhance);
      for (const message of breakMaterialProblems(rules, draft.items)) {
        push("globals", "globals", "enhance", message);
      }
    } catch (cause) {
      push("globals", "globals", "enhance", cause instanceof Error ? cause.message : "强化规则不正确");
    }
  }

  const realmSlugs = new Set(draft.realms.map((row) => row.slug));
  const stageSlugs = new Set(draft.stages.map((row) => row.slug));
  const itemSlugs = new Set(draft.items.map((row) => row.slug));
  const skillSlugs = new Set(draft.skills.map((row) => row.slug));
  const dropSlugs = new Set(draft.dropTables.map((row) => row.slug));

  if (draft.realms.length === 0) {
    push("realm", "", "slug", "至少要有一个境界");
  } else {
    chainErrors("realm", draft.realms.map((row) => ({ slug: row.slug, next: row.nextRealmSlug })), push);
    if (!realmSlugs.has(draft.globals.startingRealmSlug)) {
      push("globals", "globals", "startingRealmSlug", "初始境界不存在");
    }
  }
  for (const realm of draft.realms) {
    if (realm.tickSeconds < 1) {
      push("realm", realm.slug, "tickSeconds", "节拍至少 1 秒");
    }
    if (realm.gainPerTick < 0 || realm.breakthroughCost < 0) {
      push("realm", realm.slug, "breakthroughCost", "修为数值不能为负");
    }
    // 突破必定成功（2026-10-21 Chengpeng 确认）：成功率那组列已停用，不再校验。
    if (realm.requiredStageSlug && !stageSlugs.has(realm.requiredStageSlug)) {
      push("realm", realm.slug, "requiredStageSlug", "要求的关卡不存在");
    }
    const gate = realm.requiredStageSlug ? draft.stages.find((row) => row.slug === realm.requiredStageSlug) : undefined;
    if (gate) {
      if (!hasBoss(gate)) {
        push("realm", realm.slug, "requiredStageSlug", "要求通关的关卡没有首领，永远通不了");
      }
      if (realm.sortOrder != null && gate.requiredRealmOrder != null && gate.requiredRealmOrder > realm.sortOrder) {
        push("realm", realm.slug, "requiredStageSlug", "要求通关的关卡境界要求比本境界还高，永远打不到");
      }
    }
  }

  chainErrors("stage", draft.stages.map((row) => ({ slug: row.slug, next: row.nextStageSlug })), push);
  for (const stage of draft.stages) {
    for (const field of ["bossDropTableSlug", "idleDropTableSlug", "firstClearDropTableSlug"] as const) {
      if (!dropSlugs.has(stage[field])) {
        push("stage", stage.slug, field, "掉落表不存在");
      }
    }
    if (hasBoss(stage)) {
      if (stage.bossHp <= 0) {
        push("stage", stage.slug, "bossHp", "Boss 气血必须大于 0");
      }
      if (stage.bossInterval <= 0) {
        push("stage", stage.slug, "bossInterval", "Boss 出手间隔必须大于 0");
      }
    }
    if ((stage.monsters?.length ?? 0) > 1) {
      // 老数据可能存了多只；游戏只用第一只，所以只提醒不拦发布，后台保存这关时会要求删到一只
      warn("stage", stage.slug, "monsters", `一关只能有一只普通怪，现有 ${stage.monsters!.length} 只，只会用第一只「${stage.monsters![0]!.name}」`);
    }
    for (const monster of stage.monsters ?? []) {
      if (!(monster.hp > 0) || !(monster.interval > 0) || monster.attack < 0 || monster.defense < 0) {
        push("stage", stage.slug, "monsters", `怪物「${monster.name}」的气血、出手间隔必须大于 0，攻击防御不能为负`);
      }
      if (!Number.isInteger(monster.killCultivation) || monster.killCultivation < 0) {
        push("stage", stage.slug, "monsters", `怪物「${monster.name}」的击杀修为要是不小于 0 的整数`);
      }
    }
    if (stage.monsterDrop) {
      if (!Number.isInteger(stage.monsterDrop.chanceBp) || stage.monsterDrop.chanceBp < 0 || stage.monsterDrop.chanceBp > 10000) {
        push("stage", stage.slug, "monsterDrop", "怪物掉落概率必须在 0 到 10000（万分比）");
      }
      const weights = Object.values(stage.monsterDrop.qualityWeights ?? {}).map(Number);
      if (weights.some((value) => !Number.isFinite(value) || value < 0) || (stage.monsterDrop.chanceBp > 0 && weights.reduce((sum, value) => sum + value, 0) <= 0)) {
        push("stage", stage.slug, "monsterDrop", "品质权重不能为负，且至少有一档大于 0");
      }
    }
    for (const boss of stage.bosses ?? []) {
      for (const entry of boss.firstClear ?? []) {
        if (entry.kind === "item") {
          if (!itemSlugs.has(entry.itemSlug) && !skillSlugs.has(entry.itemSlug)) {
            push("stage", stage.slug, "bosses", `首通奖励里的物品 ${entry.itemSlug} 不存在`);
          }
          if (!Number.isInteger(entry.quantity) || entry.quantity < 1) {
            push("stage", stage.slug, "bosses", "首通奖励的数量要是不小于 1 的整数");
          }
        } else if (entry.kind === "gear") {
          if (!Number.isInteger(entry.count) || entry.count < 1 || entry.count > 10) {
            push("stage", stage.slug, "bosses", "首通奖励的装备件数要是 1 到 10 的整数");
          }
        } else if (entry.kind === "spiritStones") {
          if (!Number.isInteger(entry.amount) || entry.amount < 1) {
            push("stage", stage.slug, "bosses", "首通灵石奖励要是不小于 1 的整数");
          }
        } else if (!Number.isInteger(entry.amount) || entry.amount < 1) {
          push("stage", stage.slug, "bosses", "首通修为奖励要是不小于 1 的整数");
        }
      }
      for (const extra of boss.repeat?.extras ?? []) {
        if (!itemSlugs.has(extra.itemSlug)) {
          push("stage", stage.slug, "bosses", `重复挑战奖励里的物品 ${extra.itemSlug} 不存在`);
        }
        if (extra.chanceBp < 0 || extra.chanceBp > 10000 || extra.minQty < 1 || extra.maxQty < extra.minQty) {
          push("stage", stage.slug, "bosses", "重复挑战奖励的概率或数量区间不正确");
        }
      }
    }
  }

  // 一个章节都没配 = 第三批之前的老内容（只在单元测试的小世界里出现；线上 0040 迁移后一定有章节），不做章节/首领档位检查
  if (draft.chapters && draft.chapters.length > 0) {
    chapterAndBossErrors(draft, push);
  }

  for (const problem of stagePowerErrors(draft)) {
    push("stage", problem.slug, "bosses", problem.message);
  }

  for (const table of draft.dropTables) {
    for (const entry of table.entries) {
      if (!itemSlugs.has(entry.itemSlug) || draft.items.find((item) => item.slug === entry.itemSlug)?.enabled === false) {
        push("dropTable", table.slug, "itemSlug", "掉落物品不存在或已停用");
      }
      if (entry.chanceBp < 0 || entry.chanceBp > 10000) {
        push("dropTable", table.slug, "chanceBp", "概率必须在 0 到 10000");
      }
      if (entry.minQty < 1 || entry.maxQty < entry.minQty) {
        push("dropTable", table.slug, "minQty", "数量区间不正确");
      }
    }
  }

  const bookBySkill = new Map<string, string>();
  for (const item of draft.items) {
    if (item.kind === "equipment" && !EQUIPMENT_SLOTS.has(item.slot ?? "")) {
      push("item", item.slug, "slot", "装备部位不合法");
    }
    if (item.kind === "skill_book") {
      if (!item.skillSlug || !skillSlugs.has(item.skillSlug)) {
        push("item", item.slug, "skillSlug", "功法书必须指向存在的功法");
      } else if (bookBySkill.has(item.skillSlug)) {
        push("item", item.slug, "skillSlug", "一门功法最多一本书");
      } else {
        bookBySkill.set(item.skillSlug, item.slug);
      }
    }
  }
  for (const problem of equipmentPowerErrors(draft.items)) {
    push("item", problem.slug, "quality", problem.message);
  }
  // 批次②：指定掉落的装备要存在、启用；套装成员要指向存在的套装
  for (const stage of draft.stages) {
    for (const drop of stage.designatedDrops ?? []) {
      const item = draft.items.find((row) => row.slug === drop.itemSlug);
      if (!item || !item.enabled || item.kind !== "equipment") {
        push("stage", stage.slug, "designatedDrops", `指定掉落的装备 ${drop.itemSlug} 不存在或已停用`);
      }
    }
    for (const drop of stage.seedDrops ?? []) {
      const item = draft.items.find((row) => row.slug === drop.itemSlug);
      if (!item || !item.enabled) {
        push("stage", stage.slug, "seedDrops", `种子掉落的物品 ${drop.itemSlug} 不存在或已停用`);
      }
      if (!Number.isInteger(drop.chanceBp) || drop.chanceBp < 0 || drop.chanceBp > 10000) {
        push("stage", stage.slug, "seedDrops", `种子掉落 ${drop.itemSlug} 概率必须在 0–10000（万分比）`);
      }
      if (!Number.isInteger(drop.minCount) || !Number.isInteger(drop.maxCount) || drop.minCount < 1 || drop.maxCount < drop.minCount) {
        push("stage", stage.slug, "seedDrops", `种子掉落 ${drop.itemSlug} 数量不合法`);
      }
    }
  }
  const setSlugs = new Set((draft.gearSets ?? []).map((set) => set.slug));
  for (const item of draft.items) {
    if (item.setSlug && !setSlugs.has(item.setSlug)) {
      push("item", item.slug, "setSlug", "所属套装不存在");
    }
  }
  for (const starter of draft.globals.starterItems) {
    const item = draft.items.find((row) => row.slug === starter.itemSlug);
    if (!item || !item.enabled) {
      push("globals", "globals", "starterItems", "新手物品不存在或已停用");
    }
  }

  const skillsBySlug = new Map(draft.skills.map((skill) => [skill.slug, skill]));
  for (const skill of draft.skills) {
    const stack = new Set<string>();
    const visit = (slug: string) => {
      if (stack.has(slug)) {
        push("skill", skill.slug, "prerequisiteSkillSlugs", "前置功法不能形成环");
        return;
      }
      const current = skillsBySlug.get(slug);
      if (!current) {
        push("skill", skill.slug, "prerequisiteSkillSlugs", "前置功法不存在");
        return;
      }
      stack.add(slug);
      for (const next of current.prerequisiteSkillSlugs) {
        visit(next);
      }
      stack.delete(slug);
    };
    visit(skill.slug);
    if (!bookBySkill.has(skill.slug)) {
      warn("skill", skill.slug, "skillSlug", "功法没有功法书");
    }
  }

  const droppedBooks = new Set(draft.dropTables.flatMap((table) => table.entries.map((entry) => entry.itemSlug)));
  const rewardedMajors = new Set(
    draft.stages.flatMap((stage) => (stage.bosses ?? []).flatMap((boss) => (boss.reward ? [boss.reward.major] : []))),
  );
  for (const [skillSlug, bookSlug] of bookBySkill) {
    const rewarded = [...rewardedMajors].some((major) => skillSlug.startsWith(`skill_${major}_`));
    if (!droppedBooks.has(bookSlug) && !rewarded) {
      warn("item", bookSlug, "slug", `功法 ${skillSlug} 的书不在任何掉落表里`);
    }
  }

  const present = { realms: realmSlugs, stages: stageSlugs, items: itemSlugs, skills: skillSlugs, dropTables: dropSlugs };
  for (const key of Object.keys(knownSlugs) as (keyof typeof knownSlugs)[]) {
    for (const slug of knownSlugs[key]) {
      if (!present[key].has(slug)) {
        push(key, slug, "slug", "已发布的编号不能删除");
      }
    }
  }

  return { errors, warnings };
}

function chainErrors(
  kind: string,
  rows: { slug: string; next: string | null }[],
  push: (kind: string, slug: string, field: string, message: string) => void,
) {
  if (rows.length === 0) {
    return;
  }
  const bySlug = new Map(rows.map((row) => [row.slug, row]));
  const incoming = new Set(rows.flatMap((row) => (row.next ? [row.next] : [])));
  const starts = rows.filter((row) => !incoming.has(row.slug));
  const ends = rows.filter((row) => !row.next);
  if (starts.length !== 1 || ends.length !== 1) {
    push(kind, starts[0]?.slug ?? "", "next", "必须连成一条链");
    return;
  }
  const seen = new Set<string>();
  let cursor: { slug: string; next: string | null } | undefined = starts[0];
  while (cursor) {
    if (seen.has(cursor.slug)) {
      push(kind, cursor.slug, "next", "链条不能绕圈");
      return;
    }
    seen.add(cursor.slug);
    if (!cursor.next) {
      break;
    }
    const next = bySlug.get(cursor.next);
    if (!next) {
      push(kind, cursor.slug, "next", "下一环不存在");
      return;
    }
    cursor = next;
  }
  if (seen.size !== rows.length) {
    push(kind, "", "next", "链条不能分叉");
  }
}

/**
 * 第三批的校验（快照里有 chapters 才做；手写的测试世界没有章节就跳过）：
 * 章节字段、每个启用的关卡都要有章节和首领、立绘编号、首领规则合并后的问题、停用字段。
 */
function chapterAndBossErrors(draft: ContentSnapshot, push: (kind: string, slug: string, field: string, message: string) => void) {
  const chapters = draft.chapters ?? [];
  const chapterSlugs = new Set<string>();
  for (const chapter of chapters) {
    if (!SLUG.test(chapter.slug)) {
      push("chapter", chapter.slug, "slug", "编号格式不正确");
    }
    if (chapterSlugs.has(chapter.slug)) {
      push("chapter", chapter.slug, "slug", "编号重复");
    }
    chapterSlugs.add(chapter.slug);
    if (!chapter.displayName.trim()) {
      push("chapter", chapter.slug, "displayName", "请填写章节名称");
    }
    if (!CHAPTER_BG_KEY_SET.has(chapter.bgKey)) {
      push("chapter", chapter.slug, "bgKey", `背景「${chapter.bgKey}」不在可选列表里`);
    }
    if (!CHAPTER_BOSS_FX_SET.has(chapter.bossFx)) {
      push("chapter", chapter.slug, "bossFx", `首领特效只能是 ${[...CHAPTER_BOSS_FX_SET].join(" / ")}`);
    }
    if (chapter.battleBgKey && !CHAPTER_BATTLE_BG_KEY_SET.has(chapter.battleBgKey)) {
      push("chapter", chapter.slug, "battleBgKey", `战斗背景「${chapter.battleBgKey}」不在可选列表里`);
    }
    if (chapter.chiefStageSlugSetting) {
      const chief = draft.stages.find((row) => row.slug === chapter.chiefStageSlugSetting);
      if (!chief || chief.chapterSlug !== chapter.slug) {
        push("chapter", chapter.slug, "chiefStageSlug", "指定的章末关不存在或不属于这一章");
      }
    }
    if (chapter.enabled && !draft.stages.some((row) => row.enabled && row.chapterSlug === chapter.slug)) {
      push("chapter", chapter.slug, "slug", "这一章还没有启用的关卡");
    }
  }
  for (const stage of draft.stages) {
    if (!stage.enabled) {
      continue;
    }
    if (!stage.chapterSlug) {
      push("stage", stage.slug, "chapterSlug", "关卡没有所属章节");
    } else if (!chapterSlugs.has(stage.chapterSlug)) {
      push("stage", stage.slug, "chapterSlug", "所属章节不存在");
    }
    for (const monster of stage.monsters ?? []) {
      if (!monster.artKey) {
        push("stage", stage.slug, "monsters", `怪物「${monster.name}」还没选立绘`);
      } else if (!MONSTER_ART_KEY_SET.has(monster.artKey)) {
        push("stage", stage.slug, "monsters", `怪物「${monster.name}」的立绘「${monster.artKey}」不在可选列表里`);
      }
    }
    const boss = stage.bosses?.[0];
    if (!boss) {
      push("stage", stage.slug, "bosses", "每个关卡都要有首领");
      continue;
    }
    if ((stage.bosses?.length ?? 0) > 1) {
      push("stage", stage.slug, "bosses", "每个关卡只能有一个首领");
    }
    if (boss.artKey && !BOSS_ART_KEY_SET.has(boss.artKey)) {
      push("stage", stage.slug, "bosses", `首领「${boss.name}」的立绘「${boss.artKey}」不在可选列表里`);
    } else if (!boss.artKey) {
      push("stage", stage.slug, "bosses", `首领「${boss.name}」还没选立绘`);
    }
    if (boss.statsProblem) {
      push("stage", stage.slug, "bosses", boss.statsProblem);
    }
    if (boss.rules) {
      for (const message of bossRuleProblems(boss.rules)) {
        push("stage", stage.slug, "bosses", `首领规则：${message}`);
      }
    }
    if (boss.repeat?.orangeChanceBp !== undefined && boss.repeat?.orangeChanceBp !== null) {
      push("stage", stage.slug, "bosses", "「重复奖励橙装概率」已停用，请改用首领规则里的装备品质掉率（橙）");
    }
  }
}
