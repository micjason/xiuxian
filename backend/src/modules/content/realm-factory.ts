/**
 * 境界出厂 seed：固定 8 大境界 × 3 层。数字与预计时长照抄
 * realm_fixed_table §4.4 / realm_defaults.md，不随后台改数重算。
 *
 * 炼气三层、筑基三层的突破关卡是已经上线的原型门槛。出厂表没有这一列，
 * 但「恢复出厂」不能把它们清掉，所以写在这里。其余层的出厂关卡为空。
 */

export type RealmLayer = 1 | 2 | 3;

export type RealmFactoryRow = {
  code: number;
  slug: string;
  majorKey: string;
  majorName: string;
  layer: RealmLayer;
  displayName: string;
  gainPerTick: number;
  breakthroughCost: number;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  /** 出厂突破关卡。空字符串 = 不需要。 */
  requiredStageId: string;
  /** 出厂展示字符串，不随修为重算。 */
  etaLabel: string;
};

export type RealmNumbers = {
  gainPerTick: number;
  breakthroughCost: number;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  requiredStageId: string;
};

export type StoredRealmNumbers = {
  slug: string;
  displayName: string;
  sortOrder: number;
  gainPerTick: number;
  breakthroughCost: number;
  baseAttack: number;
  baseDefense: number;
  baseHp: number;
  baseSpeed: number;
  baseInterval: number | null;
  tickSeconds: number;
  requiredStageSlug: string | null;
};

export type FixedRealmView = RealmNumbers & {
  code: number;
  slug: string;
  majorKey: string;
  majorName: string;
  layer: RealmLayer;
  displayName: string;
  tickSeconds: number;
  interval: number | null;
  etaLabel: string;
  showBreakthroughCost: boolean;
  showGate: boolean;
  factory: RealmNumbers;
  changed: string[];
  tuned: boolean;
  stored: boolean;
};

const MAJORS: { key: string; name: string; slug: string }[] = [
  { key: "qi", name: "炼气", slug: "lianqi" },
  { key: "foundation", name: "筑基", slug: "zhuji" },
  { key: "core", name: "金丹", slug: "jindan" },
  { key: "nascent", name: "元婴", slug: "yuanying" },
  { key: "spirit", name: "化神", slug: "huashen" },
  { key: "void", name: "炼虚", slug: "lianxu" },
  { key: "unity", name: "合体", slug: "heti" },
  { key: "mahayana", name: "大乘", slug: "dacheng" },
];

const LAYER_LABEL = ["一层", "二层", "三层"] as const;

type Seed = [gain: number, cost: number, attack: number, defense: number, hp: number, speed: number, eta: string];

/** 每大境三层，顺序与 §4.4 一致。 */
const SEEDS: Seed[][] = [
  [
    [1, 1080, 10, 10, 33, 20, "约 30 分"],
    [1, 2160, 2, 2, 7, 0, "约 1.5 小时"],
    [1, 5400, 2, 2, 7, 0, "约 4 小时"],
  ],
  [
    [3, 16200, 9, 9, 30, 10, "约 6.5 小时"],
    [3, 16200, 5, 5, 17, 0, "约 9 小时"],
    [3, 19440, 5, 5, 17, 0, "约 2 天"],
  ],
  [
    [9, 77760, 20, 20, 67, 10, "约 2.5 天"],
    [9, 77760, 11, 11, 37, 0, "约 3.5 天"],
    [9, 77760, 12, 12, 40, 0, "约 4 天"],
  ],
  [
    [27, 466560, 46, 46, 153, 10, "约 5.5 天"],
    [27, 466560, 25, 25, 83, 0, "约 7 天"],
    [27, 466560, 29, 29, 97, 0, "约 8 天"],
  ],
  [
    [81, 2099520, 106, 106, 353, 10, "约 10 天"],
    [81, 2099520, 56, 56, 186, 0, "约 12 天"],
    [81, 2099520, 68, 68, 226, 0, "约 14 天"],
  ],
  [
    [243, 8398080, 243, 243, 809, 10, "约 17 天"],
    [243, 10497600, 130, 130, 433, 0, "约 20 天"],
    [243, 10497600, 156, 156, 519, 0, "约 23 天"],
  ],
  [
    [729, 39366000, 561, 561, 1868, 10, "约 28 天"],
    [729, 39366000, 299, 299, 996, 0, "约 32 天"],
    [729, 47239200, 359, 359, 1195, 0, "约 37 天"],
  ],
  [
    [2187, 165337200, 1292, 1292, 4302, 10, "约 43 天"],
    [2187, 165337200, 690, 690, 2298, 0, "约 48 天"],
    [2187, 0, 827, 827, 2754, 0, "约 55 天"],
  ],
];

function gateOf(slug: string): string {
  if (slug === "lianqi_3" || slug === "zhuji_3") return slug;
  return "";
}

export const REALM_FACTORY: readonly RealmFactoryRow[] = MAJORS.flatMap((major, majorIndex) =>
  SEEDS[majorIndex]!.map((seed, layerIndex) => {
    const layer = (layerIndex + 1) as RealmLayer;
    const slug = `${major.slug}_${layer}`;
    const [gainPerTick, breakthroughCost, attack, defense, hp, speed, etaLabel] = seed;
    return {
      code: majorIndex * 3 + layer,
      slug,
      majorKey: major.key,
      majorName: major.name,
      layer,
      displayName: `${major.name}${LAYER_LABEL[layerIndex]}`,
      gainPerTick,
      breakthroughCost,
      attack,
      defense,
      hp,
      speed,
      requiredStageId: gateOf(slug),
      etaLabel,
    };
  }),
);

const BY_CODE = new Map(REALM_FACTORY.map((row) => [row.code, row]));
const NEXT_BY_SLUG = new Map<string, string | null>(REALM_FACTORY.map((row, index) => [row.slug, REALM_FACTORY[index + 1]?.slug ?? null]));

/** 固定表里的下一境。不是这 24 行时返回 undefined。大乘三层返回 null。 */
export function canonicalNextSlug(slug: string): string | null | undefined {
  if (!NEXT_BY_SLUG.has(slug)) return undefined;
  return NEXT_BY_SLUG.get(slug) ?? null;
}

export function factoryByCode(code: number): RealmFactoryRow | undefined {
  return BY_CODE.get(code);
}

/** 大乘三层没有下一层，不提供突破修为。 */
export function showsBreakthroughCost(row: Pick<RealmFactoryRow, "code">): boolean {
  return row.code !== 24;
}

/** 只有各大境三层可以配突破前通关。 */
export function showsGate(row: Pick<RealmFactoryRow, "layer">): boolean {
  return row.layer === 3;
}

export function editableKeys(row: RealmFactoryRow): string[] {
  const keys = ["gainPerTick", "attack", "defense", "hp", "speed"];
  if (showsBreakthroughCost(row)) keys.splice(1, 0, "breakthroughCost");
  if (showsGate(row)) keys.push("requiredStageId");
  return keys;
}

function sameNumber(left: number, right: number): boolean {
  return Number(left) === Number(right);
}

/** 相对出厂常量有差异的字段。预计时长不参与比较。一二层的关卡即使库里有值也不算改动（界面不提供）。 */
export function changedFieldKeys(seed: RealmFactoryRow, current: RealmNumbers): string[] {
  const changed: string[] = [];
  if (!sameNumber(current.gainPerTick, seed.gainPerTick)) changed.push("gainPerTick");
  if (!sameNumber(current.breakthroughCost, seed.breakthroughCost)) changed.push("breakthroughCost");
  if (!sameNumber(current.attack, seed.attack)) changed.push("attack");
  if (!sameNumber(current.defense, seed.defense)) changed.push("defense");
  if (!sameNumber(current.hp, seed.hp)) changed.push("hp");
  if (!sameNumber(current.speed, seed.speed)) changed.push("speed");
  if (showsGate(seed) && (current.requiredStageId ?? "") !== seed.requiredStageId) changed.push("requiredStageId");
  return changed;
}

function numbersFromSeed(seed: RealmFactoryRow): RealmNumbers {
  return {
    gainPerTick: seed.gainPerTick,
    breakthroughCost: seed.breakthroughCost,
    attack: seed.attack,
    defense: seed.defense,
    hp: seed.hp,
    speed: seed.speed,
    requiredStageId: seed.requiredStageId,
  };
}

function numbersFromStored(row: StoredRealmNumbers): RealmNumbers {
  return {
    gainPerTick: row.gainPerTick,
    breakthroughCost: row.breakthroughCost,
    attack: row.baseAttack,
    defense: row.baseDefense,
    hp: row.baseHp,
    speed: row.baseSpeed,
    requiredStageId: row.requiredStageSlug ?? "",
  };
}

/**
 * 固定 24 行。库里多出来的境界不进列表。
 * 名称用出厂表，不用库里改过的名字（名称已不可编辑）。
 * 缺行时用出厂数字占位，stored = false。
 */
export function listFixedRealms(rows: StoredRealmNumbers[]): FixedRealmView[] {
  const bySlug = new Map(rows.map((row) => [row.slug, row]));
  return REALM_FACTORY.map((seed) => {
    const stored = bySlug.get(seed.slug);
    const current = stored ? numbersFromStored(stored) : numbersFromSeed(seed);
    const changed = changedFieldKeys(seed, current);
    return {
      ...current,
      code: seed.code,
      slug: seed.slug,
      majorKey: seed.majorKey,
      majorName: seed.majorName,
      layer: seed.layer,
      displayName: seed.displayName,
      tickSeconds: stored?.tickSeconds ?? 1,
      interval: stored?.baseInterval ?? 1.5,
      etaLabel: seed.etaLabel,
      showBreakthroughCost: showsBreakthroughCost(seed),
      showGate: showsGate(seed),
      factory: numbersFromSeed(seed),
      changed,
      tuned: changed.length > 0,
      stored: Boolean(stored),
    };
  });
}
