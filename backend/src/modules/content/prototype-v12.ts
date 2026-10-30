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
import { ensureFactoryRealms } from "./realm-seed.js";
import { REALM_FACTORY } from "./realm-factory.js";
import { DEFAULT_SKILLS } from "./default-skills.js";

/**
 * 原型数值表 v1.2（/workspace/prototype_design_numbers.md）扩到固定 24 小层：
 * 每层同名 slug 1 关 + 1 Boss；突破闸只挂各大境第 3 层共 7 个（不含大乘三层）。
 * 前 9 层数字仍对照 tools/sim/prototype-v1.2.config.json（prototype-v12.test.ts 漂移守卫）。
 */

type Stats = { hp: number; attack: number; defense: number; speed: number };

export const PROTOTYPE_MAJORS = [
  { key: "qi", name: "炼气", ultMultBp: 40000, ultCooldown: 20, weights: { white: 70, green: 25, blue: 5, purple: 0 } as QualityWeights },
  { key: "foundation", name: "筑基", ultMultBp: 50000, ultCooldown: 18, weights: { white: 50, green: 35, blue: 13, purple: 2 } as QualityWeights },
  { key: "core", name: "金丹", ultMultBp: 60000, ultCooldown: 16, weights: { white: 35, green: 40, blue: 20, purple: 5 } as QualityWeights },
  { key: "nascent", name: "元婴", ultMultBp: 70000, ultCooldown: 14, weights: { white: 25, green: 40, blue: 25, purple: 10 } as QualityWeights },
  { key: "spirit", name: "化神", ultMultBp: 80000, ultCooldown: 12, weights: { white: 15, green: 40, blue: 30, purple: 15 } as QualityWeights },
  { key: "void", name: "炼虚", ultMultBp: 90000, ultCooldown: 11, weights: { white: 10, green: 35, blue: 35, purple: 20 } as QualityWeights },
  { key: "unity", name: "合体", ultMultBp: 100000, ultCooldown: 10, weights: { white: 5, green: 30, blue: 40, purple: 25 } as QualityWeights },
  { key: "mahayana", name: "大乘", ultMultBp: 110000, ultCooldown: 9, weights: { white: 0, green: 25, blue: 45, purple: 30 } as QualityWeights },
] as const;

/** 每层“到达后累计的面板”（表 1.1）；入库时按层相减变成“到达该境界增加的属性”。仅前 9 层手填；10–24 由 ensureFactoryRealms 补出厂。 */
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

export const PROTOTYPE_STAGES: { slug: string; name: string; monster: Mob; boss?: Lord; recommendedPower?: number }[] = [
  // 炼气首关：小怪保持表 2.x 挂机节奏；精英手填压到推荐 187（炼气≈187 可过），并关掉自动挑战以免开局被秒过
  { slug: "lianqi_1", name: "黑风岭·一", monster: { name: "青鬃狼", hp: 110, attack: 24, defense: 14, interval: 1.5, killXp: 3, art: "wolf" }, boss: { slug: "b_lq_wolf", name: "青鬃狼王", hp: 110, attack: 8, defense: 8, interval: 1.5, recommendedPower: 187, art: "wolf" }, recommendedPower: 187 },
  { slug: "lianqi_2", name: "黑风岭·二", monster: { name: "赤眼狐妖", hp: 125, attack: 32, defense: 15, interval: 1.25, killXp: 3, art: "fox" } },
  { slug: "lianqi_3", name: "黑风岭·三", monster: { name: "毒牙蟒", hp: 190, attack: 36, defense: 17, interval: 1.5, killXp: 3, art: "snake" }, boss: { slug: "b_lq_bear", name: "黑风熊王", hp: 1640, attack: 42, defense: 20, interval: 1.5, recommendedPower: 900, art: "bear" } },
  { slug: "zhuji_1", name: "幽冥古道·一", monster: { name: "游魂", hp: 335, attack: 100, defense: 42, interval: 1.5, killXp: 10, art: "ghost" } },
  { slug: "zhuji_2", name: "幽冥古道·二", monster: { name: "骨傀", hp: 365, attack: 110, defense: 46, interval: 1.25, killXp: 10, art: "bone_golem" } },
  { slug: "zhuji_3", name: "幽冥古道·三", monster: { name: "血蝠", hp: 565, attack: 125, defense: 50, interval: 1.5, killXp: 10, art: "bat" }, boss: { slug: "b_zj_ghost", name: "噬魂老鬼", hp: 5760, attack: 113, defense: 61, interval: 1.5, recommendedPower: 2450, art: "ghost_elder" } },
  { slug: "jindan_1", name: "赤炎火山·一", monster: { name: "炎鳞蜥", hp: 1310, attack: 275, defense: 120, interval: 1.5, killXp: 30, art: "lava_lizard" } },
  { slug: "jindan_2", name: "赤炎火山·二", monster: { name: "火鸦", hp: 1430, attack: 305, defense: 130, interval: 1.25, killXp: 30, art: "fire_crow" } },
  { slug: "jindan_3", name: "赤炎火山·三", monster: { name: "熔岩傀", hp: 2470, attack: 265, defense: 140, interval: 1.5, killXp: 30, art: "lava_golem" }, boss: { slug: "b_jd_jiao", name: "赤焰蛟", hp: 20400, attack: 309, defense: 170, interval: 1.5, recommendedPower: 6590, art: "fire_jiao" } },
  // 元婴～大乘：章名/怪名占位仙侠风，artKey 复用已有
  { slug: "yuanying_1", name: "紫霄秘境·一", monster: { name: "婴影魅", hp: 3668, attack: 770, defense: 336, interval: 1.5, killXp: 90, art: "wolf" } },
  { slug: "yuanying_2", name: "紫霄秘境·二", monster: { name: "紫霓蛇", hp: 4004, attack: 854, defense: 364, interval: 1.25, killXp: 90, art: "fox" } },
  { slug: "yuanying_3", name: "紫霄秘境·三", monster: { name: "元胎傀", hp: 5880, attack: 1176, defense: 420, interval: 1.5, killXp: 90, art: "ghost" }, boss: { slug: "b_yy_infant", name: "紫婴魔君", hp: 57120, attack: 865, defense: 476, interval: 1.5, recommendedPower: 18452, art: "ghost_elder" } },
  { slug: "huashen_1", name: "神游泽·一", monster: { name: "神识蝠", hp: 10270, attack: 2156, defense: 941, interval: 1.5, killXp: 270, art: "ghost" } },
  { slug: "huashen_2", name: "神游泽·二", monster: { name: "化影蜥", hp: 11211, attack: 2391, defense: 1019, interval: 1.25, killXp: 270, art: "lava_lizard" } },
  { slug: "huashen_3", name: "神游泽·三", monster: { name: "游神鸦", hp: 16464, attack: 3293, defense: 1176, interval: 1.5, killXp: 270, art: "fire_crow" }, boss: { slug: "b_hs_spirit", name: "化神天君", hp: 159936, attack: 2423, defense: 1333, interval: 1.5, recommendedPower: 51666, art: "lava_lizard" } },
  { slug: "lianxu_1", name: "太虚谷·一", monster: { name: "虚空狼", hp: 28757, attack: 6037, defense: 2634, interval: 1.5, killXp: 810, art: "wolf" } },
  { slug: "lianxu_2", name: "太虚谷·二", monster: { name: "炼虚狐", hp: 31391, attack: 6695, defense: 2854, interval: 1.25, killXp: 810, art: "fox" } },
  { slug: "lianxu_3", name: "太虚谷·三", monster: { name: "裂隙熊", hp: 46099, attack: 9220, defense: 3293, interval: 1.5, killXp: 810, art: "bear" }, boss: { slug: "b_lx_void", name: "太虚剑主", hp: 447821, attack: 6783, defense: 3732, interval: 1.5, recommendedPower: 144664, art: "fire_jiao" } },
  { slug: "heti_1", name: "合道峰·一", monster: { name: "合道骨傀", hp: 80520, attack: 16903, defense: 7376, interval: 1.5, killXp: 2430, art: "bone_golem" } },
  { slug: "heti_2", name: "合道峰·二", monster: { name: "双生游魂", hp: 87896, attack: 18747, defense: 7991, interval: 1.25, killXp: 2430, art: "ghost" } },
  { slug: "heti_3", name: "合道峰·三", monster: { name: "天台火鸦", hp: 129078, attack: 25816, defense: 9220, interval: 1.5, killXp: 2430, art: "fire_crow" }, boss: { slug: "b_ht_unity", name: "合道真君", hp: 1253898, attack: 18993, defense: 10449, interval: 1.5, recommendedPower: 405058, art: "bear" } },
  { slug: "dacheng_1", name: "大罗天·一", monster: { name: "大罗炎蜥", hp: 225456, attack: 47329, defense: 20652, interval: 1.5, killXp: 7290, art: "lava_lizard" } },
  { slug: "dacheng_2", name: "大罗天·二", monster: { name: "仙域骨将", hp: 246108, attack: 52492, defense: 22373, interval: 1.25, killXp: 7290, art: "bone_golem" } },
  { slug: "dacheng_3", name: "大罗天·三", monster: { name: "罗天蛟影", hp: 361418, attack: 72284, defense: 25816, interval: 1.5, killXp: 7290, art: "fire_jiao" }, boss: { slug: "b_dc_maha", name: "大罗仙尊", hp: 3510915, attack: 53180, defense: 29258, interval: 1.5, recommendedPower: 1134163, art: "bone_golem" } },
];

/** 八章：前三章沿用原型；后五章占位仙侠风，bgKey/battleBgKey 复用已有三套。 */
export const PROTOTYPE_CHAPTERS = [
  { slug: "heifeng", name: "黑风岭", bgKey: "heifeng", bossFx: "default", battleBgKey: "heifeng" },
  { slug: "youming", name: "幽冥古道", bgKey: "youming", bossFx: "default", battleBgKey: "youming" },
  { slug: "chiyan", name: "赤炎火山", bgKey: "chiyan", bossFx: "chiyan", battleBgKey: "chiyan" },
  { slug: "zixiao", name: "紫霄秘境", bgKey: "youming", bossFx: "default", battleBgKey: "youming" },
  { slug: "shenyou", name: "神游泽", bgKey: "heifeng", bossFx: "default", battleBgKey: "heifeng" },
  { slug: "taixu", name: "太虚谷", bgKey: "youming", bossFx: "default", battleBgKey: "youming" },
  { slug: "hedao", name: "合道峰", bgKey: "chiyan", bossFx: "chiyan", battleBgKey: "chiyan" },
  { slug: "daluo", name: "大罗天", bgKey: "heifeng", bossFx: "default", battleBgKey: "heifeng" },
] as const;

/** 第 1、2 关首领的默认名字（策划定，后台可改；章末关的名字不变）。 */
export const PROTOTYPE_BOSS_NAMES: Record<string, string> = {
  lianqi_1: "青鬃狼王",
  lianqi_2: "赤眼妖狐",
  zhuji_1: "游魂统领",
  zhuji_2: "白骨傀将",
  jindan_1: "炎鳞蜥皇",
  jindan_2: "焚天火鸦",
  yuanying_1: "婴影魅王",
  yuanying_2: "紫霓蛇后",
  huashen_1: "神识蝠王",
  huashen_2: "化影蜥皇",
  lianxu_1: "虚空狼王",
  lianxu_2: "炼虚狐仙",
  heti_1: "合道骨将",
  heti_2: "双生魂主",
  dacheng_1: "大罗炎皇",
  dacheng_2: "仙域骨尊",
};

/** 精英首通灵石：按大境界 3× 递进。 */
export const PROTOTYPE_ELITE_STONES = [50, 150, 450, 1350, 4050, 12150, 36450, 109350] as const;

/** 前三项顺序被首领首通奖励按下标引用。表现字段来自 DEFAULT_SKILLS。 */
export const PROTOTYPE_SKILLS = DEFAULT_SKILLS.map((skill) => ({
  slug: skill.slug,
  name: skill.displayName,
  bonusBp: skill.cultivateBonusBp,
  role: skill.role,
  attack: skill.attack,
  defense: skill.defense,
  hp: skill.hp,
  rank: skill.rank,
  description: skill.description,
  fxType: skill.fxType,
  fx: skill.fx,
  castMode: skill.castMode,
}));

export const PROTOTYPE_BOSS_ULT_NAME = "剑诀·破军";

const MAJOR_END_GATES = new Set([
  "lianqi_3",
  "zhuji_3",
  "jindan_3",
  "yuanying_3",
  "huashen_3",
  "lianxu_3",
  "heti_3",
]);

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
      baseInterval: 1.5,
      minInterval: 0.5,
      challengeCooldownSeconds: 0,
      timeLimitSeconds: 45,
      defenseConstant: 1,
      speedBase: 100,
      recommendedPowerMargin: 1.1,
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
  for (const stone of [...STARTING_BREAK_MATERIALS, STARTING_ESSENCE_ITEM]) {
    const [exists] = await db.select().from(contentItems).where(eq(contentItems.slug, stone.slug)).limit(1);
    if (!exists) {
      await db.insert(contentItems).values({ slug: stone.slug, displayName: stone.displayName, description: stone.description, kind: "material", quality: stone.quality, stackable: true });
    }
  }
  const [heartCategory] = await db.select().from(contentSkillCategories).where(eq(contentSkillCategories.displayName, "心法")).limit(1);
  const heartSlug = heartCategory?.slug ?? "cat_heart";
  if (!heartCategory) {
    await db.insert(contentSkillCategories).values({ slug: heartSlug, displayName: "心法" });
  }
  const bookSlugs: Record<string, string> = {};
  for (const skill of PROTOTYPE_SKILLS) {
    await db.delete(contentSkills).where(eq(contentSkills.slug, skill.slug));
    await db.insert(contentSkills).values({
      slug: skill.slug,
      displayName: skill.name,
      description: skill.description,
      role: skill.role,
      rank: skill.rank,
      attack: skill.attack,
      defense: skill.defense,
      hp: skill.hp,
      cultivateBonusBp: skill.bonusBp,
      skillCategorySlug: heartSlug,
      fxType: skill.fxType,
      fx: skill.fx,
      castMode: skill.castMode,
      prerequisiteSkillSlugs: [],
    });
    bookSlugs[skill.slug] = await ensureSkillBook(db, { slug: skill.slug, displayName: skill.name }, null);
  }
  let previous: Stats = { hp: 0, attack: 0, defense: 0, speed: 0 };
  for (const [index, layer] of PROTOTYPE_LAYERS.entries()) {
    const major = PROTOTYPE_MAJORS[layer.major];
    const gate = MAJOR_END_GATES.has(layer.slug) ? layer.slug : null;
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
      ultName: "",
      ultDamageMultBp: 0,
      ultCooldownSeconds: 0,
      ultFirstCooldownSeconds: 0,
      requiredStageSlug: gate,
      updatedAt: now,
    });
    previous = layer.stats;
  }
  // 补齐元婴～大乘出厂境界，并接上 next 链（含 jindan_3 → yuanying_1）
  await ensureFactoryRealms(db, now, null);
  await syncGear(db, null);
  const realms = await db.select().from(contentRealms);
  const majorKeyOf = (order: number) => realms.find((row) => row.sortOrder === order)?.majorKey ?? `major${order}`;
  const tier = (major: number) => majorKeyOf(major * 3 + 1);
  const stone = (itemSlug: string, quantity: number) => ({ kind: "item" as const, itemSlug, quantity });
  const bosses: Record<string, StageBoss> = {
    b_lq_wolf: {
      name: "青鬃狼王", hp: 110, attack: 8, defense: 8, interval: 1.5, drops: [],
      firstClear: [{ kind: "spiritStones", amount: PROTOTYPE_ELITE_STONES[0]! }, stone("enh_stone_low", 1), { kind: "gear", count: 1 }],
      repeat: { gear: true, extras: [{ itemSlug: "enh_stone_low", chanceBp: 7000, minQty: 1, maxQty: 1 }] },
      // 首关教学：推荐战力按手填，不自动挑战（避免开局战力 494 直接秒过）
      rules: { statMode: "manual", autoChallenge: false },
    },
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
    b_yy_infant: {
      name: "紫婴魔君", hp: 57120, attack: 865, defense: 476, interval: 1.5, drops: [],
      firstClear: [stone(gearPieceSlug(tier(3), "weapon", "purple"), 1), stone("enh_stone_mid", 4)],
      repeat: { gear: true, extras: [{ itemSlug: "enh_stone_mid", chanceBp: 5000, minQty: 1, maxQty: 2 }] },
    },
    b_hs_spirit: {
      name: "化神天君", hp: 159936, attack: 2423, defense: 1333, interval: 1.5, drops: [],
      firstClear: [stone(gearPieceSlug(tier(4), "weapon", "purple"), 1), stone("enh_stone_mid", 5)],
      repeat: { gear: true, extras: [{ itemSlug: "enh_stone_mid", chanceBp: 5000, minQty: 1, maxQty: 2 }] },
    },
    b_lx_void: {
      name: "太虚剑主", hp: 447821, attack: 6783, defense: 3732, interval: 1.5, drops: [],
      firstClear: [stone(gearPieceSlug(tier(5), "weapon", "purple"), 1), stone("enh_stone_high", 2)],
      repeat: { gear: true, extras: [{ itemSlug: "enh_stone_mid", chanceBp: 6000, minQty: 1, maxQty: 2 }] },
    },
    b_ht_unity: {
      name: "合道真君", hp: 1253898, attack: 18993, defense: 10449, interval: 1.5, drops: [],
      firstClear: [stone(gearPieceSlug(tier(6), "weapon", "purple"), 1), stone("enh_stone_high", 3)],
      repeat: { gear: true, extras: [{ itemSlug: "enh_stone_high", chanceBp: 4000, minQty: 1, maxQty: 1 }] },
    },
    b_dc_maha: {
      name: "大罗仙尊", hp: 3510915, attack: 53180, defense: 29258, interval: 1.5, drops: [],
      firstClear: [stone(gearPieceSlug(tier(7), "accessory", "orange"), 1), stone("enh_stone_high", 5)],
      repeat: { gear: true, extras: [{ itemSlug: "enh_stone_high", chanceBp: 5000, minQty: 1, maxQty: 2 }] },
    },
  };
  for (const [index, chapter] of PROTOTYPE_CHAPTERS.entries()) {
    await db.insert(contentChapters).values({ slug: chapter.slug, displayName: chapter.name, sortOrder: index + 1, bgKey: chapter.bgKey, bossFx: chapter.bossFx, battleBgKey: chapter.battleBgKey, updatedAt: now });
  }
  for (const [index, stage] of PROTOTYPE_STAGES.entries()) {
    const major = Math.floor(index / 3);
    const boss: StageBoss = stage.boss
      ? { ...bosses[stage.boss.slug]!, artKey: `boss_${stage.boss.art}`, rules: { statMode: "manual", ...bosses[stage.boss.slug]!.rules } }
      : {
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
      recommendedPower: stage.recommendedPower ?? stage.boss?.recommendedPower ?? null,
      bossName: boss.name,
      bossAttack: boss.attack,
      bossDefense: boss.defense,
      bossHp: boss.hp,
      bossInterval: boss.interval,
      bosses: [boss],
      monsters: [{ name: stage.monster.name, attack: stage.monster.attack, defense: stage.monster.defense, hp: stage.monster.hp, interval: stage.monster.interval, killCultivation: stage.monster.killXp, artKey: stage.monster.art }],
      monsterDrop: compactDropOverride({ chanceBp: 500, qualityWeights: PROTOTYPE_MAJORS[major]!.weights }, DEFAULT_TUNING),
      bossDropTableSlug: "proto_boss",
      idleDropTableSlug: "proto_idle",
      firstClearDropTableSlug: "proto_first",
      updatedAt: now,
    });
  }
  return { stageSlugs: PROTOTYPE_STAGES.map((row) => row.slug), realmSlugs: REALM_FACTORY.map((row) => row.slug), bookSlugs };
}
