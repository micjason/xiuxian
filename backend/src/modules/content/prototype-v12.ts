import { eq } from "drizzle-orm";
import { contentChapters, contentDropTables, contentGlobals, contentItems, contentRealms, contentSkillCategories, contentSkills, contentStages, type StageBoss } from "../../db/schema.js";
import type { Db } from "../operations/record.js";
import { DEFAULT_OPTIONAL_RULES, type QualityWeights } from "./combat-types.js";
import { STARTING_BREAK_MATERIALS, STARTING_ENHANCE_RULES, STARTING_ESSENCE_ITEM } from "./enhance.js";
import { syncGear } from "./gear.js";
import { ensureSkillBook } from "./ops-content.js";
import { gearPieceSlug } from "./gear.js";
import { compactDropOverride } from "./stage-defaults.js";
import { DEFAULT_TUNING } from "./tuning.js";
import { DEFAULT_BOSS_RULES } from "./boss-rules.js";

/**
 * 原型数值表 v1.2（/workspace/prototype_design_numbers.md）的内容数据：9 层 3 个大境界、9 个关卡、3 个首领、3 门功法。
 * 数字和 tools/sim/prototype-v1.2.config.json 一致（prototype-v12.test.ts 里对照，改一边忘了另一边会报错）。
 * 用途：端到端测试，以及在新环境里一键灌入原型内容（后台改动之后以后台为准，这里只是起点）。
 */

type Stats = { hp: number; attack: number; defense: number; speed: number };

export const PROTOTYPE_MAJORS = [
  { key: "qi", name: "炼气", ultMultBp: 40000, ultCooldown: 20, weights: { white: 70, green: 25, blue: 5, purple: 0 } as QualityWeights },
  { key: "foundation", name: "筑基", ultMultBp: 50000, ultCooldown: 18, weights: { white: 50, green: 35, blue: 13, purple: 2 } as QualityWeights },
  { key: "core", name: "金丹", ultMultBp: 60000, ultCooldown: 16, weights: { white: 35, green: 40, blue: 20, purple: 5 } as QualityWeights },
] as const;

/** 每层“到达后累计的面板”（表 1.1）；入库时按层相减变成“到达该境界增加的属性”。 */
export const PROTOTYPE_LAYERS: { slug: string; name: string; major: 0 | 1 | 2; gainPerTick: number; costToNext: number | null; stats: Stats }[] = [
  { slug: "lianqi_1", name: "炼气一层", major: 0, gainPerTick: 1, costToNext: 60, stats: { hp: 300, attack: 30, defense: 10, speed: 20 } },
  { slug: "lianqi_2", name: "炼气二层", major: 0, gainPerTick: 1, costToNext: 300, stats: { hp: 360, attack: 36, defense: 12, speed: 20 } },
  { slug: "lianqi_3", name: "炼气三层", major: 0, gainPerTick: 1, costToNext: 1800, stats: { hp: 430, attack: 43, defense: 14, speed: 20 } },
  { slug: "zhuji_1", name: "筑基一层", major: 1, gainPerTick: 3, costToNext: 28800, stats: { hp: 780, attack: 78, defense: 26, speed: 30 } },
  { slug: "zhuji_2", name: "筑基二层", major: 1, gainPerTick: 3, costToNext: 72000, stats: { hp: 940, attack: 94, defense: 31, speed: 30 } },
  { slug: "zhuji_3", name: "筑基三层", major: 1, gainPerTick: 3, costToNext: 144000, stats: { hp: 1130, attack: 113, defense: 37, speed: 30 } },
  { slug: "jindan_1", name: "金丹一层", major: 2, gainPerTick: 9, costToNext: 252000, stats: { hp: 2050, attack: 205, defense: 68, speed: 40 } },
  { slug: "jindan_2", name: "金丹二层", major: 2, gainPerTick: 9, costToNext: 504000, stats: { hp: 2460, attack: 246, defense: 82, speed: 40 } },
  { slug: "jindan_3", name: "金丹三层", major: 2, gainPerTick: 9, costToNext: null, stats: { hp: 2950, attack: 295, defense: 98, speed: 40 } },
];

type Mob = { name: string; hp: number; attack: number; defense: number; interval: number; killXp: number; art: string };
type Lord = { slug: string; name: string; hp: number; attack: number; defense: number; interval: number; recommendedPower: number; art: string };

export const PROTOTYPE_STAGES: { slug: string; name: string; monster: Mob; boss?: Lord }[] = [
  { slug: "lianqi_1", name: "黑风岭·一", monster: { name: "青鬃狼", hp: 110, attack: 24, defense: 14, interval: 1.5, killXp: 3, art: "wolf" } },
  { slug: "lianqi_2", name: "黑风岭·二", monster: { name: "赤眼狐妖", hp: 125, attack: 32, defense: 15, interval: 1.25, killXp: 3, art: "fox" } },
  { slug: "lianqi_3", name: "黑风岭·三", monster: { name: "毒牙蟒", hp: 190, attack: 36, defense: 17, interval: 1.5, killXp: 3, art: "snake" }, boss: { slug: "b_lq_bear", name: "黑风熊王", hp: 1640, attack: 42, defense: 20, interval: 1.5, recommendedPower: 900, art: "bear" } },
  { slug: "zhuji_1", name: "幽冥古道·一", monster: { name: "游魂", hp: 335, attack: 100, defense: 42, interval: 1.5, killXp: 10, art: "ghost" } },
  { slug: "zhuji_2", name: "幽冥古道·二", monster: { name: "骨傀", hp: 365, attack: 110, defense: 46, interval: 1.25, killXp: 10, art: "bone_golem" } },
  { slug: "zhuji_3", name: "幽冥古道·三", monster: { name: "血蝠", hp: 565, attack: 125, defense: 50, interval: 1.5, killXp: 10, art: "bat" }, boss: { slug: "b_zj_ghost", name: "噬魂老鬼", hp: 5760, attack: 113, defense: 61, interval: 1.5, recommendedPower: 2450, art: "ghost_elder" } },
  { slug: "jindan_1", name: "赤炎火山·一", monster: { name: "炎鳞蜥", hp: 1310, attack: 275, defense: 120, interval: 1.5, killXp: 30, art: "lava_lizard" } },
  { slug: "jindan_2", name: "赤炎火山·二", monster: { name: "火鸦", hp: 1430, attack: 305, defense: 130, interval: 1.25, killXp: 30, art: "fire_crow" } },
  { slug: "jindan_3", name: "赤炎火山·三", monster: { name: "熔岩傀", hp: 2470, attack: 265, defense: 140, interval: 1.5, killXp: 30, art: "lava_golem" }, boss: { slug: "b_jd_jiao", name: "赤焰蛟", hp: 20400, attack: 309, defense: 170, interval: 1.5, recommendedPower: 6590, art: "fire_jiao" } },
];

/** 三章（第三批）：每章 3 关，第 3 关是章末（大首领），第 1、2 关的首领是本关小怪的精英版。 */
export const PROTOTYPE_CHAPTERS = [
  { slug: "heifeng", name: "黑风岭", bgKey: "heifeng", bossFx: "default", battleBgKey: "heifeng" },
  { slug: "youming", name: "幽冥古道", bgKey: "youming", bossFx: "default", battleBgKey: "youming" },
  { slug: "chiyan", name: "赤炎火山", bgKey: "chiyan", bossFx: "chiyan", battleBgKey: "chiyan" },
] as const;

/** 第四批：第 1、2 关首领的默认名字（策划定，后台可改；章末关的名字不变）。迁移 0046 用同一张表。 */
export const PROTOTYPE_BOSS_NAMES: Record<string, string> = {
  lianqi_1: "青鬃狼王",
  lianqi_2: "赤眼妖狐",
  zhuji_1: "游魂统领",
  zhuji_2: "白骨傀将",
  jindan_1: "炎鳞蜥皇",
  jindan_2: "焚天火鸦",
};

/** 精英首通奖励的灵石（起始值，后台可改）：炼气 50 / 筑基 150 / 金丹 450。 */
export const PROTOTYPE_ELITE_STONES = [50, 150, 450] as const;

export const PROTOTYPE_SKILLS = [
  { slug: "skill_tuna", name: "吐纳诀", bonusBp: 500 },
  { slug: "skill_qingyuan", name: "青元诀", bonusBp: 1500 },
  { slug: "skill_zifu", name: "紫府金章", bonusBp: 3000 },
] as const;

export const PROTOTYPE_BOSS_ULT_NAME = "剑诀·破军";

/** 在空的（或只有初始境界的）内容库里灌入原型内容；返回关键编号，方便测试引用。 */
export async function applyPrototypeV12(db: Db): Promise<{ stageSlugs: string[]; realmSlugs: string[]; bookSlugs: Record<string, string> }> {
  const now = new Date();
  await db.delete(contentStages);
  await db.delete(contentChapters);
  await db.delete(contentDropTables);
  await db.delete(contentRealms);
  await db.delete(contentGlobals);
  await db.insert(contentGlobals).values({
    id: 1,
    startingRealmSlug: PROTOTYPE_LAYERS[0]!.slug,
    offlineCapSeconds: 28800,
    bagCapacity: 20,
    starterItems: [],
    powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
    combat: {
      minInterval: 0.5,
      challengeCooldownSeconds: 0,
      timeLimitSeconds: 45,
      defenseConstant: 1,
      speedBase: 100,
      recommendedPowerMargin: 1.05,
      gearSpeedFactor: 0.3,
      ...DEFAULT_OPTIONAL_RULES,
    },
    enhance: STARTING_ENHANCE_RULES,
    updatedAt: now,
  });
  await db.insert(contentDropTables).values([
    { slug: "proto_boss", displayName: "原型首领掉落" },
    { slug: "proto_idle", displayName: "原型挂机掉落" },
    { slug: "proto_first", displayName: "原型首通掉落" },
  ]);
  // 突破石 + 炼器精粹（第五批）
  for (const stone of [...STARTING_BREAK_MATERIALS, STARTING_ESSENCE_ITEM]) {
    const [exists] = await db.select().from(contentItems).where(eq(contentItems.slug, stone.slug)).limit(1);
    if (!exists) {
      await db.insert(contentItems).values({ slug: stone.slug, displayName: stone.displayName, description: stone.description, kind: "material", quality: stone.quality, stackable: true });
    }
  }
  // 功法 + 功法书（三门都是心法，归在「心法」分类下，后台才能保存）
  const [heartCategory] = await db.select().from(contentSkillCategories).where(eq(contentSkillCategories.displayName, "心法")).limit(1);
  const heartSlug = heartCategory?.slug ?? "cat_heart";
  if (!heartCategory) {
    await db.insert(contentSkillCategories).values({ slug: heartSlug, displayName: "心法" });
  }
  const bookSlugs: Record<string, string> = {};
  for (const skill of PROTOTYPE_SKILLS) {
    await db.delete(contentSkills).where(eq(contentSkills.slug, skill.slug));
    await db.insert(contentSkills).values({ slug: skill.slug, displayName: skill.name, role: "heart", cultivateBonusBp: skill.bonusBp, skillCategorySlug: heartSlug });
    bookSlugs[skill.slug] = await ensureSkillBook(db, { slug: skill.slug, displayName: skill.name }, null);
  }
  // 境界：累计面板相减得到每层增加的属性
  let previous: Stats = { hp: 0, attack: 0, defense: 0, speed: 0 };
  for (const [index, layer] of PROTOTYPE_LAYERS.entries()) {
    const major = PROTOTYPE_MAJORS[layer.major];
    // 大境界突破门槛：炼气三层、筑基三层要先通关本层关卡的首领（金丹三层是最高境界）
    const gate = layer.slug === "lianqi_3" || layer.slug === "zhuji_3" ? layer.slug : null;
    await db.insert(contentRealms).values({
      slug: layer.slug,
      displayName: layer.name,
      majorName: major.name,
      sortOrder: index + 1,
      nextRealmSlug: PROTOTYPE_LAYERS[index + 1]?.slug ?? null,
      tickSeconds: 1,
      gainPerTick: layer.gainPerTick,
      breakthroughCost: layer.costToNext ?? 0,
      baseHp: layer.stats.hp - previous.hp,
      baseAttack: layer.stats.attack - previous.attack,
      baseDefense: layer.stats.defense - previous.defense,
      baseSpeed: layer.stats.speed - previous.speed,
      baseInterval: 1.5,
      ultName: PROTOTYPE_BOSS_ULT_NAME,
      ultDamageMultBp: major.ultMultBp,
      ultCooldownSeconds: major.ultCooldown,
      ultFirstCooldownSeconds: 8,
      requiredStageSlug: gate,
      updatedAt: now,
    });
    previous = layer.stats;
  }
  await syncGear(db, null);
  const realms = await db.select().from(contentRealms);
  const majorKeyOf = (order: number) => realms.find((row) => row.sortOrder === order)?.majorKey ?? `major${order}`;
  const tier = (major: number) => majorKeyOf(major * 3 + 1);
  const stone = (itemSlug: string, quantity: number) => ({ kind: "item" as const, itemSlug, quantity });
  const bosses: Record<string, StageBoss> = {
    b_lq_bear: {
      name: "黑风熊王", hp: 1640, attack: 42, defense: 20, interval: 1.5, drops: [],
      firstClear: [
        { kind: "cultivation", amount: 1500 },
        stone(PROTOTYPE_SKILLS[1].slug, 1),
        stone(gearPieceSlug(tier(0), "accessory", "blue"), 1),
        stone("enh_stone_low", 3),
      ],
      repeat: { gear: true, extras: [{ itemSlug: "enh_stone_low", chanceBp: 7000, minQty: 1, maxQty: 2 }] },
    },
    b_zj_ghost: {
      name: "噬魂老鬼", hp: 5760, attack: 113, defense: 61, interval: 1.5, drops: [],
      firstClear: [stone(PROTOTYPE_SKILLS[2].slug, 1), stone(gearPieceSlug(tier(1), "weapon", "purple"), 1), stone("enh_stone_low", 5), stone("enh_stone_mid", 1)],
      repeat: { gear: true, extras: [{ itemSlug: "enh_stone_low", chanceBp: 7000, minQty: 1, maxQty: 2 }, { itemSlug: "enh_stone_mid", chanceBp: 3000, minQty: 1, maxQty: 1 }] },
    },
    b_jd_jiao: {
      name: "赤焰蛟", hp: 20400, attack: 309, defense: 170, interval: 1.5, drops: [],
      firstClear: [stone(gearPieceSlug(tier(2), "accessory", "purple"), 1), stone("enh_stone_mid", 3)],
      repeat: { gear: true, extras: [{ itemSlug: "enh_stone_low", chanceBp: 7000, minQty: 1, maxQty: 2 }, { itemSlug: "enh_stone_mid", chanceBp: 3000, minQty: 1, maxQty: 1 }] },
    },
  };
  for (const [index, chapter] of PROTOTYPE_CHAPTERS.entries()) {
    await db.insert(contentChapters).values({ slug: chapter.slug, displayName: chapter.name, sortOrder: index + 1, bgKey: chapter.bgKey, bossFx: chapter.bossFx, battleBgKey: chapter.battleBgKey, updatedAt: now });
  }
  for (const [index, stage] of PROTOTYPE_STAGES.entries()) {
    const major = Math.floor(index / 3);
    // 第四批：一套首领规则。章末关是原来的大首领（手填数值 → 单关覆盖「属性 = 手填」）；
    // 第 1、2 关是本关小怪的精英版（属性按首领规则自动算，这里存一份按默认倍率算好的数方便后台看），重复奖励 = 1 件装备 + 70% 突破石·下品
    const boss: StageBoss = stage.boss
      ? { ...bosses[stage.boss.slug]!, artKey: `boss_${stage.boss.art}`, rules: { statMode: "manual" } }
      : {
          // 第四批：策划定的首领名（后台可改）；统一首领立绘 boss_<本关小怪>（SPEC_Q §17.10）
          name: PROTOTYPE_BOSS_NAMES[stage.slug] ?? `首领·${stage.monster.name}`,
          artKey: `boss_${stage.monster.art}`,
          attack: Math.round(stage.monster.attack * DEFAULT_BOSS_RULES.statMul.attack),
          defense: Math.round(stage.monster.defense * DEFAULT_BOSS_RULES.statMul.defense),
          hp: Math.round(stage.monster.hp * DEFAULT_BOSS_RULES.statMul.hp),
          interval: stage.monster.interval,
          drops: [],
          firstClear: [{ kind: "spiritStones", amount: PROTOTYPE_ELITE_STONES[major]! }, stone("enh_stone_low", 1), { kind: "gear", count: 1 }],
          repeat: { gear: true, extras: [{ itemSlug: "enh_stone_low", chanceBp: 7000, minQty: 1, maxQty: 1 }] },
        };
    await db.insert(contentStages).values({
      slug: stage.slug,
      displayName: stage.name,
      chapterSlug: PROTOTYPE_CHAPTERS[major]!.slug,
      sortOrder: index + 1,
      nextStageSlug: PROTOTYPE_STAGES[index + 1]?.slug ?? null,
      requiredRealmOrder: index + 1,
      recommendedPower: stage.boss?.recommendedPower ?? null,
      bossName: boss.name,
      bossAttack: boss.attack,
      bossDefense: boss.defense,
      bossHp: boss.hp,
      bossInterval: boss.interval,
      bosses: [boss],
      monsters: [{ name: stage.monster.name, attack: stage.monster.attack, defense: stage.monster.defense, hp: stage.monster.hp, interval: stage.monster.interval, killCultivation: stage.monster.killXp, artKey: stage.monster.art }],
      // 只存和配置概览默认值不同的项（炼气 = 默认值，存 null = 跟随默认）
      monsterDrop: compactDropOverride({ chanceBp: 500, qualityWeights: PROTOTYPE_MAJORS[major]!.weights }, DEFAULT_TUNING),
      bossDropTableSlug: "proto_boss",
      idleDropTableSlug: "proto_idle",
      firstClearDropTableSlug: "proto_first",
      updatedAt: now,
    });
  }
  return { stageSlugs: PROTOTYPE_STAGES.map((row) => row.slug), realmSlugs: PROTOTYPE_LAYERS.map((row) => row.slug), bookSlugs };
}
