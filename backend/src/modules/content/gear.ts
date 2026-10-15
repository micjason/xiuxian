import { eq, inArray } from "drizzle-orm";
import { contentDropEntries, contentGlobals, contentItems, contentRealms, contentStages, playerItems } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { ratePower, sumReachedRealmStats } from "../combat/stats.js";

export const GEAR_BUDGET_RATIO = 0.55;

/**
 * 装备速度比例：鞋子、饰品上的“速度”数值按预算算出来的值再乘这个比例（0–1），
 * 省下的战力原样补到同一部位的另一项属性（鞋子补气血、饰品补攻击），所以每件装备的战力不变，只是少一点速度。
 * 1 = 不压速度（第 1 周之前的行为）；越小，出手间隔越难缩短。默认 0.1：第 1b 周模拟里，这个值让三个大境界的参考出手间隔落在 1.2 / 1.1 / 1.0 左右，和设计表 2.1 一致，普通怪击杀间隔与设计表 2.5 相差不到 10%（见 tools/sim 报告）。
 */
export const DEFAULT_GEAR_SPEED_FACTOR = 0.3;

type GearStat = "attack" | "defense" | "hp" | "speed";

export const GEAR_SLOTS: { key: string; name: string; share: number; stats: readonly GearStat[] }[] = [
  { key: "weapon", name: "武器", share: 0.25, stats: ["attack"] },
  { key: "clothes", name: "衣服", share: 0.2, stats: ["defense", "hp"] },
  { key: "helmet", name: "头冠", share: 0.13, stats: ["defense", "hp"] },
  { key: "gloves", name: "护手", share: 0.12, stats: ["attack", "defense"] },
  { key: "shoes", name: "鞋子", share: 0.15, stats: ["speed", "hp"] },
  { key: "accessory", name: "饰品", share: 0.15, stats: ["attack", "speed"] },
];

export const GEAR_QUALITIES = [
  { key: "white", name: "白" },
  { key: "green", name: "绿" },
  { key: "blue", name: "蓝" },
  { key: "purple", name: "紫" },
  { key: "orange", name: "橙" },
] as const;

export const DEFAULT_GEAR_QUALITY_FACTORS = {
  white: 1,
  green: 1.15,
  blue: 1.3,
  purple: 1.5,
  orange: 1.8,
} as const;

export type GearQualityKey = keyof typeof DEFAULT_GEAR_QUALITY_FACTORS;
export type GearQualityFactors = Record<GearQualityKey, number>;

type Weights = { attack: number; defense: number; hp: number; speed: number };
type Stats = Weights;

const FACTOR_FIELDS: { key: GearQualityKey; label: string }[] = [
  { key: "white", label: "白品质系数" },
  { key: "green", label: "绿品质系数" },
  { key: "blue", label: "蓝品质系数" },
  { key: "purple", label: "紫品质系数" },
  { key: "orange", label: "橙品质系数" },
];

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function gearPieceSlug(major: string, slot: string, quality: string): string {
  return `gear_${major}_${slot}_${quality}`;
}

export function majorKeyFor(realms: { slug: string; sortOrder: number; majorKey: string | null }[]): string {
  const saved = realms.map((realm) => realm.majorKey).find((key) => key);
  if (saved) {
    return saved;
  }
  const prefixes = realms.map((realm) => realm.slug.match(/^(.*)_(early|mid|late)$/)?.[1] ?? "");
  const unique = [...new Set(prefixes.filter((prefix) => prefix))];
  if (unique.length === 1 && prefixes.every((prefix) => prefix === unique[0])) {
    return unique[0] ?? "major1";
  }
  const first = [...realms].sort((left, right) => left.sortOrder - right.sortOrder)[0];
  return `major${first?.sortOrder ?? 1}`;
}

export function gearSpeedFactorOf(value: unknown): number {
  if (value === undefined || value === null || value === "") {
    return DEFAULT_GEAR_SPEED_FACTOR;
  }
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || number > 1) {
    throw new AppError("INVALID_INPUT", "装备速度比例要在 0 到 1 之间");
  }
  return number;
}

export function splitGearBudget(input: { budget: Stats; slotKey: string; factor: number; weights: Weights; speedFactor?: number }): Stats {
  const slot = GEAR_SLOTS.find((row) => row.key === input.slotKey);
  if (!slot) {
    throw new AppError("INVALID_INPUT", "请选择部位：武器、头冠、衣服、鞋子、饰品");
  }
  const budgetPower =
    input.budget.attack * input.weights.attack +
    input.budget.defense * input.weights.defense +
    input.budget.hp * input.weights.hp +
    input.budget.speed * input.weights.speed;
  const weightSum = slot.stats.reduce((sum, key) => sum + input.weights[key], 0);
  if (!(weightSum > 0)) {
    throw new AppError("INVALID_INPUT", "请先在后台填写：攻击权重、防御权重、气血权重、速度权重");
  }
  const each = (budgetPower * slot.share * input.factor) / weightSum;
  const speedFactor = gearSpeedFactorOf(input.speedFactor);
  const values: Stats = { attack: 0, defense: 0, hp: 0, speed: 0 };
  const others = slot.stats.filter((key) => key !== "speed");
  if (!slot.stats.includes("speed") || others.length === 0 || speedFactor === 1) {
    for (const key of slot.stats) {
      values[key] = round2(each);
    }
    return values;
  }
  // 速度压低后省下的战力，补给同一部位的其他属性，部位总战力不变。
  const speed = each * speedFactor;
  const otherWeightSum = others.reduce((sum, key) => sum + input.weights[key], 0);
  const refill = otherWeightSum > 0 ? (each * weightSum - speed * input.weights.speed) / otherWeightSum : each;
  values.speed = round2(speed);
  for (const key of others) {
    values[key] = round2(refill);
  }
  return values;
}

export function gearBudgetOf(
  realms: { sortOrder: number; baseAttack: number; baseDefense: number; baseHp: number; baseSpeed: number }[],
  majorOrders: number[],
): Stats {
  const ordered = [...majorOrders].sort((left, right) => left - right);
  const earlyOrder = ordered[0];
  const speedOrder = ordered[1] ?? earlyOrder;
  if (earlyOrder === undefined || speedOrder === undefined) {
    throw new AppError("INVALID_INPUT", "请先填写大境界");
  }
  const rows = realms.map((realm) => ({
    sortOrder: realm.sortOrder,
    attack: realm.baseAttack,
    defense: realm.baseDefense,
    hp: realm.baseHp,
    speed: realm.baseSpeed,
  }));
  const early = sumReachedRealmStats(rows, earlyOrder);
  const speed = sumReachedRealmStats(rows, speedOrder);
  return {
    attack: early.attack * GEAR_BUDGET_RATIO,
    defense: early.defense * GEAR_BUDGET_RATIO,
    hp: early.hp * GEAR_BUDGET_RATIO,
    speed: speed.speed * GEAR_BUDGET_RATIO,
  };
}

export function gearQualityFactorsFromInput(input: Record<string, unknown> | null | undefined): GearQualityFactors {
  const factors = {} as GearQualityFactors;
  for (const field of FACTOR_FIELDS) {
    const value = input?.[field.key];
    if (value === undefined || value === null || value === "") {
      throw new AppError("INVALID_INPUT", `请填写${field.label}`);
    }
    const number = Number(value);
    if (!Number.isFinite(number) || number <= 0) {
      throw new AppError("INVALID_INPUT", `${field.label}必须大于 0`);
    }
    factors[field.key] = number;
  }
  return factors;
}

function storedFactors(value: GearQualityFactors | null | undefined): GearQualityFactors | null {
  if (!value) {
    return null;
  }
  const missing = FACTOR_FIELDS.filter((field) => {
    const number = Number(value[field.key]);
    return !Number.isFinite(number) || number <= 0;
  }).map((field) => field.label);
  if (missing.length > 0) {
    throw new AppError("INVALID_INPUT", `请先在后台填写：${missing.join("、")}`);
  }
  return {
    white: Number(value.white),
    green: Number(value.green),
    blue: Number(value.blue),
    purple: Number(value.purple),
    orange: Number(value.orange),
  };
}

export async function readGearQualityFactors(db: Db): Promise<GearQualityFactors> {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  if (!row) {
    throw new AppError("INVALID_INPUT", "请先新建境界");
  }
  const stored = storedFactors(row.gearQualityFactors);
  if (stored) {
    return stored;
  }
  await db
    .update(contentGlobals)
    .set({ gearQualityFactors: { ...DEFAULT_GEAR_QUALITY_FACTORS }, updatedAt: new Date() })
    .where(eq(contentGlobals.id, 1));
  return { ...DEFAULT_GEAR_QUALITY_FACTORS };
}

function weightsOf(weights: Weights | null | undefined): Weights {
  if (!weights || [weights.attack, weights.defense, weights.hp, weights.speed].some((value) => value == null || !Number.isFinite(Number(value)))) {
    throw new AppError("INVALID_INPUT", "请先在后台填写：攻击权重、防御权重、气血权重、速度权重");
  }
  return {
    attack: Number(weights.attack),
    defense: Number(weights.defense),
    hp: Number(weights.hp),
    speed: Number(weights.speed),
  };
}

export function majorGearSlugs(majorKey: string): string[] {
  return GEAR_SLOTS.flatMap((slot) => GEAR_QUALITIES.map((quality) => gearPieceSlug(majorKey, slot.key, quality.key)));
}

export async function syncGear(db: Db, adminId: string | null): Promise<void> {
  const factors = await readGearQualityFactors(db);
  const [globals] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  const weights = weightsOf(globals?.powerWeights);
  const speedFactor = gearSpeedFactorOf(globals?.combat?.gearSpeedFactor);
  const realms = await db.select().from(contentRealms);
  const items = await db.select().from(contentItems);
  const groups = new Map<string, typeof realms>();
  for (const realm of realms) {
    const majorName = realm.majorName.trim();
    if (!majorName) {
      continue;
    }
    groups.set(majorName, [...(groups.get(majorName) ?? []), realm]);
  }
  const now = new Date();
  for (const [majorName, rows] of groups) {
    const majorKey = majorKeyFor(rows);
    for (const realm of rows) {
      if (realm.majorKey !== majorKey) {
        await db.update(contentRealms).set({ majorKey, updatedAt: now, updatedBy: adminId }).where(eq(contentRealms.slug, realm.slug));
      }
    }
    const budget = gearBudgetOf(realms, rows.map((realm) => realm.sortOrder));
    const requiredRealmOrder = Math.min(...rows.map((realm) => realm.sortOrder));
    for (const slot of GEAR_SLOTS) {
      for (const quality of GEAR_QUALITIES) {
        const slug = gearPieceSlug(majorKey, slot.key, quality.key);
        const stats = splitGearBudget({ budget, slotKey: slot.key, factor: factors[quality.key], weights, speedFactor });
        const current = items.find((item) => item.slug === slug);
        const values = {
          ...stats,
          quality: quality.key,
          slot: slot.key,
          requiredRealmOrder,
          kind: "equipment",
          stackable: false,
          weaponCategorySlug: null,
          skillSlug: null,
          updatedAt: now,
          updatedBy: adminId,
        };
        if (current) {
          await db.update(contentItems).set(values).where(eq(contentItems.slug, slug));
        } else {
          await db.insert(contentItems).values({
            ...values,
            slug,
            displayName: `${majorName}·${quality.name}·${slot.name}`,
            description: `${majorName}${slot.name}，品质${quality.name}`,
            iconKey: "",
            enabled: true,
          });
        }
      }
    }
  }
}

export async function saveGearQualityFactors(db: Db, input: Record<string, unknown>, adminId: string | null): Promise<GearQualityFactors> {
  const factors = gearQualityFactorsFromInput(input);
  const [current] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  if (!current) {
    throw new AppError("INVALID_INPUT", "请先新建境界");
  }
  await db
    .update(contentGlobals)
    .set({ gearQualityFactors: factors, updatedAt: new Date(), updatedBy: adminId })
    .where(eq(contentGlobals.id, 1));
  await syncGear(db, adminId);
  return factors;
}

export async function updateGearPiece(
  db: Db,
  slug: string,
  input: { displayName?: string; description?: string; iconKey?: string },
  adminId: string | null,
): Promise<{ id: string }> {
  const [current] = await db.select().from(contentItems).where(eq(contentItems.slug, slug)).limit(1);
  if (!current || current.kind !== "equipment") {
    throw new AppError("NOT_FOUND", "没有这件装备");
  }
  const displayName = typeof input.displayName === "string" ? input.displayName.trim() : "";
  if (!displayName) {
    throw new AppError("INVALID_INPUT", "请填写装备名称");
  }
  await db
    .update(contentItems)
    .set({
      displayName,
      description: typeof input.description === "string" ? input.description.trim() : "",
      iconKey: typeof input.iconKey === "string" ? input.iconKey.trim() : "",
      updatedAt: new Date(),
      updatedBy: adminId,
    })
    .where(eq(contentItems.slug, slug));
  return { id: slug };
}

export async function removeMajorGear(db: Db, majorKey: string): Promise<void> {
  const slugs = majorGearSlugs(majorKey);
  const held = await db.select().from(playerItems).where(inArray(playerItems.itemSlug, slugs)).limit(1);
  if (held.length > 0) {
    throw new AppError("INVALID_INPUT", "还有人拿着这一阶的装备");
  }
  const drops = await db.select().from(contentDropEntries);
  if (drops.some((entry) => slugs.includes(entry.itemSlug))) {
    throw new AppError("INVALID_INPUT", "这一阶的装备还挂在掉落上，先拿掉");
  }
  const stages = await db.select().from(contentStages);
  if (stages.some((stage) => (stage.bosses ?? []).some((boss) => boss.drops.some((drop) => slugs.includes(drop.itemSlug))))) {
    throw new AppError("INVALID_INPUT", "这一阶的装备还挂在掉落上，先拿掉");
  }
  await db.delete(contentItems).where(inArray(contentItems.slug, slugs));
}

export async function listGear(db: Db) {
  const factors = await readGearQualityFactors(db);
  const [globals] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  const weights = globals?.powerWeights ? weightsOf(globals.powerWeights) : null;
  const realms = await db.select().from(contentRealms);
  const items = await db.select().from(contentItems);
  const groups = new Map<string, typeof realms>();
  for (const realm of realms) {
    const majorName = realm.majorName.trim();
    if (!majorName) {
      continue;
    }
    groups.set(majorName, [...(groups.get(majorName) ?? []), realm]);
  }
  const majors = [...groups.entries()]
    .map(([majorName, rows]) => {
      const majorKey = majorKeyFor(rows);
      const requiredRealmOrder = Math.min(...rows.map((realm) => realm.sortOrder));
      const pieces = GEAR_SLOTS.flatMap((slot) =>
        GEAR_QUALITIES.map((quality) => {
          const slug = gearPieceSlug(majorKey, slot.key, quality.key);
          const item = items.find((row) => row.slug === slug);
          const stats = {
            attack: item?.attack ?? 0,
            defense: item?.defense ?? 0,
            hp: item?.hp ?? 0,
            speed: item?.speed ?? 0,
          };
          return {
            id: slug,
            displayName: item?.displayName ?? "",
            description: item?.description ?? "",
            iconKey: item?.iconKey ?? "",
            slot: slot.key,
            slotName: slot.name,
            quality: quality.key,
            qualityName: quality.name,
            ...stats,
            power: weights ? ratePower(stats, weights) : null,
            missing: !item,
          };
        }),
      );
      return { majorName, majorKey, requiredRealmOrder, pieces };
    })
    .sort((left, right) => left.requiredRealmOrder - right.requiredRealmOrder);
  return { factors, majors };
}
