import { STARTING_BREAK_MATERIALS, STARTING_ENHANCE_RULES, STARTING_ESSENCE_ITEM } from "./enhance.js";
import { bossPower } from "../combat/stats.js";
import { DEFAULT_GEAR_QUALITY_FACTORS, GEAR_BUDGET_RATIO, GEAR_SLOTS, splitGearBudget } from "./gear.js";
import { stageRecommendedPower } from "./stage-power.js";
import type { ContentSnapshot } from "./validate.js";

export const SCHEME_WEIGHTS = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };
export const SCHEME_SPEED_BASE = 100;
export const SCHEME_MIN_INTERVAL = 0.5;
export const SCHEME_BASE_INTERVAL = 1.5;
export const SCHEME_DEFENSE_CONSTANT = 1;
export const SCHEME_TIME_LIMIT_SECONDS = 45;
export const SCHEME_MARGIN = 1.05;

const CUMULATIVE: [number, number, number, number][] = [
  [10, 10, 33, 0],
  [12, 12, 40, 4],
  [14, 14, 48, 8],
  [23, 23, 77, 12],
  [28, 28, 92, 16],
  [33, 33, 110, 20],
  [53, 53, 177, 24],
  [64, 64, 212, 28],
  [76, 76, 255, 32],
  [122, 122, 407, 36],
  [147, 147, 489, 40],
  [176, 176, 586, 44],
  [282, 282, 938, 48],
  [338, 338, 1126, 52],
  [406, 406, 1351, 56],
];

export const MAJORS = [
  { key: "qi", name: "炼气" },
  { key: "foundation", name: "筑基" },
  { key: "core", name: "金丹" },
  { key: "infant", name: "元婴" },
  { key: "spirit", name: "化神" },
] as const;

export const PHASES = [
  { key: "early", name: "初期", difficulty: 0.85 },
  { key: "mid", name: "中期", difficulty: 1 },
  { key: "late", name: "后期", difficulty: 1.15 },
] as const;

const SLOTS = GEAR_SLOTS;

const QUALITIES = [
  { key: "white", name: "白", factor: DEFAULT_GEAR_QUALITY_FACTORS.white },
  { key: "green", name: "绿", factor: DEFAULT_GEAR_QUALITY_FACTORS.green },
  { key: "blue", name: "蓝", factor: DEFAULT_GEAR_QUALITY_FACTORS.blue },
  { key: "purple", name: "紫", factor: DEFAULT_GEAR_QUALITY_FACTORS.purple },
  { key: "orange", name: "橙", factor: DEFAULT_GEAR_QUALITY_FACTORS.orange },
] as const;

const RANKS = [
  { key: "yellow", name: "黄阶", percent: 5 },
  { key: "xuan", name: "玄阶", percent: 8 },
  { key: "earth", name: "地阶", percent: 12 },
  { key: "heaven", name: "天阶", percent: 18 },
] as const;

const SKILL_STATS = [
  { key: "atk", name: "攻击", field: "attack" },
  { key: "def", name: "防御", field: "defense" },
  { key: "hp", name: "气血", field: "hp" },
] as const;

export const FEATURED_SLOTS = SLOTS.map((slot) => slot.key);

type Stats = { attack: number; defense: number; hp: number; speed: number };

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function gearSlug(major: string, slot: string, quality: string): string {
  return `gear_${major}_${slot}_${quality}`;
}

export function skillSlug(major: string, stat: string, rank: string): string {
  return `skill_${major}_${stat}_${rank}`;
}

export function schemeBookSlugs(major: string): string[] {
  return SKILL_STATS.flatMap((stat) => RANKS.map((rank) => skillSlug(major, stat.key, rank.key)));
}

export function plannedSeconds(index: number): number {
  let seconds = 300;
  for (let step = 1; step <= index; step += 1) {
    seconds *= 1.3;
    if (step % 3 === 0) {
      seconds *= 2;
    }
  }
  return seconds;
}

export function breakthroughCostOf(index: number): number {
  return Math.round(plannedSeconds(index) * 0.7);
}

function cumulativeAt(index: number): Stats {
  const row = CUMULATIVE[index];
  if (!row) {
    throw new Error(`境界序号 ${index} 不在方案里`);
  }
  return { attack: row[0], defense: row[1], hp: row[2], speed: row[3] };
}

function deltaAt(index: number): Stats {
  const current = cumulativeAt(index);
  if (index === 0) {
    return current;
  }
  const previous = cumulativeAt(index - 1);
  return {
    attack: current.attack - previous.attack,
    defense: current.defense - previous.defense,
    hp: current.hp - previous.hp,
    speed: current.speed - previous.speed,
  };
}

export function gearStats(majorIndex: number, slotKey: string, qualityKey: string): Stats {
  const early = cumulativeAt(majorIndex * 3);
  const midSpeed = cumulativeAt(majorIndex * 3 + 1).speed;
  const factor = DEFAULT_GEAR_QUALITY_FACTORS[qualityKey as keyof typeof DEFAULT_GEAR_QUALITY_FACTORS];
  if (factor === undefined || !SLOTS.some((row) => row.key === slotKey)) {
    throw new Error("部位或品质不在方案里");
  }
  return splitGearBudget({
    budget: {
      attack: early.attack * GEAR_BUDGET_RATIO,
      defense: early.defense * GEAR_BUDGET_RATIO,
      hp: early.hp * GEAR_BUDGET_RATIO,
      speed: midSpeed * GEAR_BUDGET_RATIO,
    },
    slotKey,
    factor,
    weights: SCHEME_WEIGHTS,
    // 标准方案是固定的示例世界（速度只有个位数，压低后两位小数的取整会破坏品质比例），保持不压速度。
    speedFactor: 1,
  });
}

function panelRaw(index: number): Stats {
  const majorIndex = Math.floor(index / 3);
  const major = MAJORS[majorIndex];
  if (!major) {
    throw new Error(`境界序号 ${index} 不在方案里`);
  }
  const base = cumulativeAt(index);
  const weapon = gearStats(majorIndex, "weapon", "white");
  const clothes = gearStats(majorIndex, "clothes", "white");
  const helmet = gearStats(majorIndex, "helmet", "white");
  const gloves = gearStats(majorIndex, "gloves", "white");
  const shoes = gearStats(majorIndex, "shoes", "white");
  const accessory = gearStats(majorIndex, "accessory", "white");
  return {
    attack: base.attack * 1.18 + weapon.attack + gloves.attack + accessory.attack,
    defense: base.defense * 1.18 + clothes.defense + helmet.defense + gloves.defense,
    hp: base.hp * 1.18 + clothes.hp + helmet.hp + shoes.hp,
    speed: base.speed + shoes.speed + accessory.speed,
  };
}

export function standardPanel(index: number): Stats {
  const raw = panelRaw(index);
  return { attack: round2(raw.attack), defense: round2(raw.defense), hp: round2(raw.hp), speed: round2(raw.speed) };
}

export function intervalOf(speed: number): number {
  return Math.max(SCHEME_MIN_INTERVAL, (SCHEME_BASE_INTERVAL * SCHEME_SPEED_BASE) / (SCHEME_SPEED_BASE + Math.max(speed, 0)));
}

export type SchemeBoss = {
  name: string;
  attack: number;
  defense: number;
  hp: number;
  interval: number;
  drops: [];
  reward: { major: string; stageIndex: number; nextMajor: string | null };
};

export function bossOf(index: number): SchemeBoss {
  const phase = PHASES[index % 3];
  const major = MAJORS[Math.floor(index / 3)];
  if (!phase || !major) {
    throw new Error(`境界序号 ${index} 不在方案里`);
  }
  const raw = panelRaw(index);
  const panel = standardPanel(index);
  const next = MAJORS[Math.floor(index / 3) + 1];
  return {
    name: `${major.name}${phase.name}·守关`,
    attack: round2(raw.attack * phase.difficulty),
    defense: round2(raw.defense * phase.difficulty),
    hp: round2(raw.hp * phase.difficulty),
    interval: intervalOf(panel.speed),
    drops: [],
    reward: { major: major.key, stageIndex: index, nextMajor: next?.key ?? null },
  };
}

export type SchemeContent = {
  startingRealmSlug: string;
  realms: {
    slug: string;
    displayName: string;
    majorName: string;
    sortOrder: number;
    nextRealmSlug: string | null;
    tickSeconds: number;
    gainPerTick: number;
    baseAttack: number;
    baseDefense: number;
    baseHp: number;
    baseSpeed: number;
    baseInterval: number;
    breakthroughCost: number;
  }[];
  items: {
    slug: string;
    displayName: string;
    description: string;
    kind: string;
    quality: string;
    slot: string | null;
    attack: number;
    defense: number;
    hp: number;
    speed: number;
    requiredRealmOrder: number;
    skillSlug: string | null;
    stackable: boolean;
  }[];
  skills: {
    slug: string;
    displayName: string;
    description: string;
    rank: string;
    attack: number;
    defense: number;
    hp: number;
    speed: number;
    cultivateBonusBp: number;
    requiredRealmOrder: number;
  }[];
  dropTables: { slug: string; displayName: string }[];
  dropEntries: { dropTableSlug: string; itemSlug: string; chanceBp: number; minQty: number; maxQty: number }[];
  stages: {
    slug: string;
    displayName: string;
    sortOrder: number;
    nextStageSlug: string | null;
    requiredRealmOrder: number;
    recommendedPower: number;
    bossName: string;
    bossAttack: number;
    bossDefense: number;
    bossHp: number;
    bossInterval: number;
    bosses: SchemeBoss[];
    bossDropTableSlug: string;
    idleDropTableSlug: string;
    firstClearDropTableSlug: string;
  }[];
};

export function buildScheme(): SchemeContent {
  const realms = CUMULATIVE.map((_, index) => {
    const major = MAJORS[Math.floor(index / 3)];
    const phase = PHASES[index % 3];
    if (!major || !phase) {
      throw new Error(`境界序号 ${index} 不在方案里`);
    }
    const delta = deltaAt(index);
    const slug = `${major.key}_${phase.key}`;
    const next = index + 1 < CUMULATIVE.length ? CUMULATIVE[index + 1] : undefined;
    const nextMajor = next ? MAJORS[Math.floor((index + 1) / 3)] : undefined;
    const nextPhase = next ? PHASES[(index + 1) % 3] : undefined;
    return {
      slug,
      displayName: `${major.name}${phase.name}`,
      majorName: major.name,
      sortOrder: index + 1,
      nextRealmSlug: nextMajor && nextPhase ? `${nextMajor.key}_${nextPhase.key}` : null,
      tickSeconds: 1,
      gainPerTick: 1,
      baseAttack: delta.attack,
      baseDefense: delta.defense,
      baseHp: delta.hp,
      baseSpeed: delta.speed,
      baseInterval: SCHEME_BASE_INTERVAL,
      breakthroughCost: breakthroughCostOf(index),
    };
  });
  const items: SchemeContent["items"] = [];
  const skills: SchemeContent["skills"] = [];
  for (const [majorIndex, major] of MAJORS.entries()) {
    const requiredRealmOrder = majorIndex * 3 + 1;
    for (const slot of SLOTS) {
      for (const quality of QUALITIES) {
        const stats = gearStats(majorIndex, slot.key, quality.key);
        items.push({
          slug: gearSlug(major.key, slot.key, quality.key),
          displayName: `${major.name}·${quality.name}·${slot.name}`,
          description: `${major.name}${slot.name}，品质${quality.name}`,
          kind: "equipment",
          quality: quality.key,
          slot: slot.key,
          ...stats,
          requiredRealmOrder,
          skillSlug: null,
          stackable: false,
        });
      }
    }
    for (const stat of SKILL_STATS) {
      for (const rank of RANKS) {
        const slug = skillSlug(major.key, stat.key, rank.key);
        skills.push({
          slug,
          displayName: `${major.name}·${rank.name}·${stat.name}`,
          description: `${stat.name}增加境界基础的 ${rank.percent}%`,
          rank: rank.key,
          attack: stat.field === "attack" ? rank.percent * 100 : 0,
          defense: stat.field === "defense" ? rank.percent * 100 : 0,
          hp: stat.field === "hp" ? rank.percent * 100 : 0,
          speed: 0,
          cultivateBonusBp: 0,
          requiredRealmOrder,
        });
        items.push({
          slug: `book_${slug}`,
          displayName: `${major.name}·${rank.name}·${stat.name}技能书`,
          description: "使用后学习或提升这门技能",
          kind: "skill_book",
          quality: "white",
          slot: null,
          attack: 0,
          defense: 0,
          hp: 0,
          speed: 0,
          requiredRealmOrder,
          skillSlug: slug,
          stackable: false,
        });
      }
    }
  }
  for (const material of [...STARTING_BREAK_MATERIALS, STARTING_ESSENCE_ITEM]) {
    items.push({
      slug: material.slug,
      displayName: material.displayName,
      description: material.description,
      kind: "material",
      quality: material.quality,
      slot: null,
      attack: 0,
      defense: 0,
      hp: 0,
      speed: 0,
      requiredRealmOrder: 0,
      skillSlug: null,
      stackable: true,
    });
  }
  const stages = realms.map((realm, index) => {
    const boss = bossOf(index);
    const next = realms[index + 1];
    return {
      slug: `stage_${realm.slug}`,
      displayName: realm.displayName,
      sortOrder: realm.sortOrder,
      nextStageSlug: next ? `stage_${next.slug}` : null,
      requiredRealmOrder: realm.sortOrder,
      recommendedPower: 0,
      bossName: boss.name,
      bossAttack: boss.attack,
      bossDefense: boss.defense,
      bossHp: boss.hp,
      bossInterval: boss.interval,
      bosses: [boss],
      bossDropTableSlug: "scheme_boss",
      idleDropTableSlug: "scheme_idle",
      firstClearDropTableSlug: "scheme_first",
    };
  });
  const content: SchemeContent = {
    startingRealmSlug: realms[0]?.slug ?? "",
    realms,
    items,
    skills,
    dropTables: [
      { slug: "scheme_boss", displayName: "方案首领掉落" },
      { slug: "scheme_idle", displayName: "方案挂机掉落" },
      { slug: "scheme_first", displayName: "方案首通掉落" },
    ],
    // 起始值：每次挑战首领成功后，有机会掉落突破石。全部可在后台「掉落表」里改。
    dropEntries: [
      { dropTableSlug: "scheme_boss", itemSlug: "enh_stone_low", chanceBp: 3500, minQty: 1, maxQty: 2 },
      { dropTableSlug: "scheme_boss", itemSlug: "enh_stone_mid", chanceBp: 1500, minQty: 1, maxQty: 1 },
      { dropTableSlug: "scheme_boss", itemSlug: "enh_stone_high", chanceBp: 500, minQty: 1, maxQty: 1 },
    ],
    stages,
  };
  const world = schemeWorld(content);
  for (const stage of world.stages) {
    const target = content.stages.find((row) => row.slug === stage.slug);
    if (!target) {
      throw new Error(`关卡 ${stage.slug} 没有写进方案`);
    }
    target.recommendedPower = stageRecommendedPower(world, stage);
  }
  return content;
}

export function schemeWorld(content: SchemeContent = buildScheme()): ContentSnapshot {
  return {
    globals: {
      enhance: STARTING_ENHANCE_RULES,
      startingRealmSlug: content.startingRealmSlug,
      starterItems: [],
      offlineCapSeconds: 28800,
      bagCapacity: 20,
      powerWeights: SCHEME_WEIGHTS,
      combat: {
        minInterval: SCHEME_MIN_INTERVAL,
        challengeCooldownSeconds: 0,
        timeLimitSeconds: SCHEME_TIME_LIMIT_SECONDS,
        defenseConstant: SCHEME_DEFENSE_CONSTANT,
        speedBase: SCHEME_SPEED_BASE,
        recommendedPowerMargin: SCHEME_MARGIN,
      },
    },
    realms: content.realms.map((realm) => ({
      slug: realm.slug,
      displayName: realm.displayName,
      sortOrder: realm.sortOrder,
      nextRealmSlug: realm.nextRealmSlug,
      tickSeconds: realm.tickSeconds,
      gainPerTick: realm.gainPerTick,
      breakthroughCost: realm.breakthroughCost,
      requiredStageSlug: null,
      recommendedPower: 0,
      baseAttack: realm.baseAttack,
      baseDefense: realm.baseDefense,
      baseHp: realm.baseHp,
      baseSpeed: realm.baseSpeed,
      baseInterval: realm.baseInterval,
      enabled: true,
    })),
    stages: content.stages.map((stage) => ({
      slug: stage.slug,
      displayName: stage.displayName,
      sortOrder: stage.sortOrder,
      nextStageSlug: stage.nextStageSlug,
      requiredRealmOrder: stage.requiredRealmOrder,
      bossDropTableSlug: stage.bossDropTableSlug,
      idleDropTableSlug: stage.idleDropTableSlug,
      firstClearDropTableSlug: stage.firstClearDropTableSlug,
      bossName: stage.bossName,
      bossAttack: stage.bossAttack,
      bossDefense: stage.bossDefense,
      bossHp: stage.bossHp,
      bossInterval: stage.bossInterval,
      bosses: stage.bosses,
      recommendedPower: stage.recommendedPower,
      enabled: true,
    })),
    dropTables: content.dropTables.map((table) => ({
      slug: table.slug,
      entries: content.dropEntries
        .filter((entry) => entry.dropTableSlug === table.slug)
        .map((entry) => ({ itemSlug: entry.itemSlug, chanceBp: entry.chanceBp, minQty: entry.minQty, maxQty: entry.maxQty })),
    })),
    items: content.items.map((item) => ({
      slug: item.slug,
      displayName: item.displayName,
      kind: item.kind,
      slot: item.slot,
      skillSlug: item.skillSlug,
      attack: item.attack,
      defense: item.defense,
      hp: item.hp,
      speed: item.speed,
      quality: item.quality,
      requiredRealmOrder: item.requiredRealmOrder,
      stackable: item.stackable,
      enabled: true,
    })),
    skills: content.skills.map((skill) => ({
      slug: skill.slug,
      displayName: skill.displayName,
      rank: skill.rank,
      attack: skill.attack,
      defense: skill.defense,
      hp: skill.hp,
      speed: skill.speed,
      cultivateBonusBp: skill.cultivateBonusBp,
      requiredRealmOrder: skill.requiredRealmOrder,
      prerequisiteSkillSlugs: [],
      enabled: true,
    })),
  };
}

export function schemeBudgetPower(majorIndex: number): number {
  const early = cumulativeAt(majorIndex * 3);
  const midSpeed = cumulativeAt(majorIndex * 3 + 1).speed;
  return (
    early.attack * GEAR_BUDGET_RATIO * SCHEME_WEIGHTS.attack +
    early.defense * GEAR_BUDGET_RATIO * SCHEME_WEIGHTS.defense +
    early.hp * GEAR_BUDGET_RATIO * SCHEME_WEIGHTS.hp +
    midSpeed * GEAR_BUDGET_RATIO * SCHEME_WEIGHTS.speed
  );
}

export function bossPowerOf(boss: SchemeBoss): number {
  return bossPower(boss, { baseInterval: SCHEME_BASE_INTERVAL, speedBase: SCHEME_SPEED_BASE, weights: SCHEME_WEIGHTS });
}
