import { randomBytes } from "node:crypto";
import { eq } from "drizzle-orm";
import type { BossRepeatReward, BossRewardEntry, MonsterDropOverride, StageMonster } from "./combat-types.js";
import { contentDropEntries, contentDropTables, contentGlobals, contentItems, contentRealms, contentSkillCategories, contentSkills, contentStages, playerItems, type StageBoss } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { loadDraftSnapshot } from "./snapshot.js";
import { stageAutoPower, stagePowerSource, stageRawPower } from "./stage-power.js";
import { compactDropOverride, customDropCount, MONSTER_QUALITIES, resolveMonsterDrop } from "./stage-defaults.js";
import { tuningOf, type Tuning } from "./tuning.js";
import { readGameRules } from "./rules.js";
import type { ContentSnapshot } from "./validate.js";

type BossInput = {
  name?: string;
  attack?: number;
  defense?: number;
  hp?: number;
  interval?: number;
  drops?: { itemId?: string; chancePercent?: number }[];
  /** 首通固定奖励：物品（可填功法编号，会变成功法书）或修为。不传 = 保持原样。 */
  firstClear?: ({ kind?: string; itemId?: string; quantity?: number; amount?: number })[] | null;
  /** 首通之后每天前几次胜利的奖励。不传 = 保持原样。 */
  repeat?: { gear?: boolean; orangeChancePercent?: number | null; extras?: { itemId?: string; chancePercent?: number; minQty?: number; maxQty?: number }[] } | null;
};

type MonsterInput = { name?: string; attack?: number; defense?: number; hp?: number; interval?: number; killCultivation?: number };
/** 关卡掉落：null / 不填的项 = 跟随配置概览；填了和默认一样的值也按「跟随默认」存。 */
type MonsterDropInput = { chancePercent?: number | null; weights?: Partial<Record<"white" | "green" | "blue" | "purple" | "orange", number | null>> } | null;

function newId(prefix: string): string {
  return `${prefix}${randomBytes(8).toString("hex")}`;
}

function textOf(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function numberOf(value: unknown, label: string): number {
  if (value === undefined || value === null || value === "") {
    throw new AppError("INVALID_INPUT", `请填写${label}`);
  }
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) {
    throw new AppError("INVALID_INPUT", `${label}不能小于 0`);
  }
  return number;
}

async function tuningFor(db: Db): Promise<Tuning> {
  const [row] = await db.select().from(contentGlobals).limit(1);
  return tuningOf(row?.tuning);
}

async function realmByCode(db: Db, code: number) {
  const [realm] = await db.select().from(contentRealms).where(eq(contentRealms.sortOrder, code)).limit(1);
  return realm ?? null;
}

function readMonsters(monsters: MonsterInput[] | undefined): StageMonster[] | undefined {
  if (monsters === undefined) {
    return undefined;
  }
  return monsters.map((monster) => {
    const name = textOf(monster.name);
    if (!name) {
      throw new AppError("INVALID_INPUT", "请填写怪物名称");
    }
    const hp = numberOf(monster.hp, "怪物气血");
    const interval = numberOf(monster.interval, "怪物出手间隔");
    if (hp <= 0 || interval <= 0) {
      throw new AppError("INVALID_INPUT", "怪物气血和出手间隔必须大于 0");
    }
    const killCultivation = numberOf(monster.killCultivation ?? 0, "击杀修为");
    if (!Number.isInteger(killCultivation)) {
      throw new AppError("INVALID_INPUT", "击杀修为要填整数");
    }
    return { name, attack: numberOf(monster.attack, "怪物攻击"), defense: numberOf(monster.defense, "怪物防御"), hp, interval, killCultivation };
  });
}

function readMonsterDrop(input: MonsterDropInput | undefined, tuning: Tuning): MonsterDropOverride | null | undefined {
  if (input === undefined) {
    return undefined;
  }
  if (input === null) {
    return null;
  }
  const override: MonsterDropOverride = {};
  if (input.chancePercent !== undefined && input.chancePercent !== null) {
    const percent = numberOf(input.chancePercent, "怪物掉率");
    if (percent > 100) {
      throw new AppError("INVALID_INPUT", "怪物掉率不能超过 100%");
    }
    override.chanceBp = Math.round(percent * 100);
  }
  const weights: NonNullable<MonsterDropOverride["qualityWeights"]> = {};
  for (const key of MONSTER_QUALITIES) {
    const value = input.weights?.[key];
    if (value !== undefined && value !== null) {
      weights[key] = numberOf(value, "品质权重");
    }
  }
  if (input.weights?.orange) {
    throw new AppError("INVALID_INPUT", "普通怪不掉橙装：橙装只由首领掉");
  }
  override.qualityWeights = weights;
  const effective = resolveMonsterDrop(override, tuning);
  if (effective.chanceBp > 0 && Object.values(effective.qualityWeights).every((value) => !value)) {
    throw new AppError("INVALID_INPUT", "品质权重至少有一档大于 0");
  }
  return compactDropOverride(override, tuning);
}

function readFirstClear(entries: BossInput["firstClear"], known: Set<string>): BossRewardEntry[] | undefined {
  if (entries === undefined) {
    return undefined;
  }
  return (entries ?? []).map((entry) => {
    if (entry.kind === "cultivation") {
      const amount = numberOf(entry.amount, "首通修为");
      if (!Number.isInteger(amount) || amount < 1) {
        throw new AppError("INVALID_INPUT", "首通修为要填不小于 1 的整数");
      }
      return { kind: "cultivation" as const, amount };
    }
    const itemSlug = textOf(entry.itemId);
    if (!itemSlug || !known.has(itemSlug)) {
      throw new AppError("INVALID_INPUT", "首通奖励里选的物品或功法不存在");
    }
    const quantity = numberOf(entry.quantity ?? 1, "首通奖励数量");
    if (!Number.isInteger(quantity) || quantity < 1) {
      throw new AppError("INVALID_INPUT", "首通奖励数量要填不小于 1 的整数");
    }
    return { kind: "item" as const, itemSlug, quantity };
  });
}

function readRepeat(input: BossInput["repeat"], known: Set<string>): BossRepeatReward | null | undefined {
  if (input === undefined) {
    return undefined;
  }
  if (input === null) {
    return null;
  }
  const extras = (input.extras ?? []).map((extra) => {
    const itemSlug = textOf(extra.itemId);
    if (!itemSlug || !known.has(itemSlug)) {
      throw new AppError("INVALID_INPUT", "重复挑战奖励里选的物品不存在");
    }
    const percent = numberOf(extra.chancePercent, "重复挑战奖励掉率");
    if (percent > 100) {
      throw new AppError("INVALID_INPUT", "掉率不能超过 100%");
    }
    const minQty = numberOf(extra.minQty ?? 1, "最少数量");
    const maxQty = numberOf(extra.maxQty ?? minQty, "最多数量");
    if (!Number.isInteger(minQty) || !Number.isInteger(maxQty) || minQty < 1 || maxQty < minQty) {
      throw new AppError("INVALID_INPUT", "数量区间不正确");
    }
    return { itemSlug, chanceBp: Math.round(percent * 100), minQty, maxQty };
  });
  const out: BossRepeatReward = { gear: input.gear === true, extras };
  if (input.orangeChancePercent !== undefined && input.orangeChancePercent !== null) {
    const percent = numberOf(input.orangeChancePercent, "橙装概率");
    if (percent > 100) {
      throw new AppError("INVALID_INPUT", "橙装概率不能超过 100%");
    }
    out.orangeChanceBp = Math.round(percent * 100);
  }
  return out;
}

async function readBosses(db: Db, bosses: BossInput[] | undefined, current: StageBoss[] = []): Promise<StageBoss[]> {
  if (!bosses || bosses.length === 0) {
    return [];
  }
  const items = await db.select().from(contentItems);
  const skills = await db.select().from(contentSkills);
  const known = new Set([...items.map((item) => item.slug), ...skills.map((skill) => skill.slug)]);
  return bosses.map((boss) => {
    const name = textOf(boss.name);
    if (!name) {
      throw new AppError("INVALID_INPUT", "请填写首领名称");
    }
    const attack = numberOf(boss.attack, "攻击");
    const defense = numberOf(boss.defense, "防御");
    const hp = numberOf(boss.hp, "气血");
    const interval = numberOf(boss.interval, "出手间隔");
    if (hp <= 0) {
      throw new AppError("INVALID_INPUT", "首领气血必须大于 0");
    }
    if (interval <= 0) {
      throw new AppError("INVALID_INPUT", "出手间隔必须大于 0");
    }
    const seen = new Set<string>();
    const drops = (boss.drops ?? []).map((drop) => {
      const itemSlug = textOf(drop.itemId);
      if (!itemSlug) {
        throw new AppError("INVALID_INPUT", `首领「${name}」有一行没选物品`);
      }
      if (!known.has(itemSlug)) {
        throw new AppError("INVALID_INPUT", "选的武器、物品或功法不存在");
      }
      if (seen.has(itemSlug)) {
        throw new AppError("INVALID_INPUT", "同一个首领上物品不能重复");
      }
      seen.add(itemSlug);
      const percent = numberOf(drop.chancePercent, "掉率");
      if (percent > 100) {
        throw new AppError("INVALID_INPUT", "掉率不能超过 100%");
      }
      return { itemSlug, chanceBp: Math.round(percent * 100) };
    });
    // 没有传的字段保持原样（按同名首领对应），避免后台只改数值时把奖励配置清掉。
    const previous = current.find((row) => row.name === name) ?? (current.length === bosses.length ? current[bosses.indexOf(boss)] : undefined);
    const firstClear = readFirstClear(boss.firstClear, known) ?? previous?.firstClear;
    const repeat = readRepeat(boss.repeat, known);
    const kept = repeat === undefined ? previous?.repeat : (repeat ?? undefined);
    const out: StageBoss = { name, attack, defense, hp, interval, drops };
    if (previous?.reward) {
      out.reward = previous.reward;
    }
    if (firstClear && firstClear.length > 0) {
      out.firstClear = firstClear;
    }
    if (kept) {
      out.repeat = kept;
    }
    return out;
  });
}

type StagePowerView = {
  /** null = 自动；数字 = 手动覆盖 */
  recommendedPower: number | null;
  effectivePower: number | null;
  autoPower: number | null;
  /** 自动值怎么来的，例如「首领 噬魂老鬼 6101 × 1.05」 */
  autoFormula: string | null;
  powerProblem: string | null;
};

/** recommendedPower = 手动覆盖的值（null = 自动）；autoPower = 按首领（没首领按普通怪）算出的值；effectivePower = 玩家实际看到的。 */
function stagePowerOf(world: ContentSnapshot, slug: string, manualRaw: number | null): StagePowerView {
  const stage = world.stages.find((candidate) => candidate.slug === slug);
  if (!stage) {
    throw new AppError("INTERNAL");
  }
  const manual = manualRaw !== null && manualRaw > 0 ? Math.round(manualRaw) : null;
  const source = stagePowerSource(stage);
  if (!source) {
    return { recommendedPower: manual, effectivePower: manual, autoPower: null, autoFormula: null, powerProblem: null };
  }
  try {
    const auto = stageAutoPower(world, stage);
    const raw = stageRawPower(world, stage);
    const margin = readGameRules(world).recommendedPowerMargin;
    const formula = `${source.kind === "boss" ? "首领" : "本关无首领，按普通怪"} ${source.name} ${Math.round(raw * 10) / 10} × ${margin}`;
    return { recommendedPower: manual, effectivePower: manual ?? auto, autoPower: auto, autoFormula: formula, powerProblem: null };
  } catch (cause) {
    if (cause instanceof AppError) {
      return { recommendedPower: manual, effectivePower: manual, autoPower: null, autoFormula: null, powerProblem: manual !== null ? null : cause.message };
    }
    throw cause;
  }
}

/** undefined = 不改；null（或 0、空）= 恢复自动；正整数 = 手动覆盖。 */
function readRecommendedPower(value: unknown): number | null | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (value === null || value === "" || value === 0) {
    return null;
  }
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0 || number > 10_000_000) {
    throw new AppError("INVALID_INPUT", "推荐战力要填 1 到 1000 万的整数（不填 = 按公式自动算）");
  }
  return number;
}

function stageView(
  row: typeof contentStages.$inferSelect,
  realms: { slug: string; displayName: string; sortOrder: number }[],
  items: { slug: string; displayName: string }[],
  skills: { slug: string; displayName: string }[],
  power: StagePowerView,
  tuning: Tuning,
) {
  const realm = realms.find((candidate) => candidate.sortOrder === row.requiredRealmOrder);
  const nameOf = (slug: string) => items.find((candidate) => candidate.slug === slug)?.displayName || skills.find((candidate) => candidate.slug === slug)?.displayName || "名称缺失";
  const bosses = (row.bosses ?? []).map((boss) => ({
    name: boss.name,
    attack: boss.attack,
    defense: boss.defense,
    hp: boss.hp,
    interval: boss.interval,
    drops: boss.drops.map((drop) => {
      const item = items.find((candidate) => candidate.slug === drop.itemSlug);
      const skill = skills.find((candidate) => candidate.slug === drop.itemSlug);
      return { itemId: drop.itemSlug, displayName: item?.displayName || skill?.displayName || "名称缺失", chancePercent: drop.chanceBp / 100 };
    }),
    firstClear: (boss.firstClear ?? []).map((entry) =>
      entry.kind === "cultivation"
        ? { kind: "cultivation", amount: entry.amount }
        : { kind: "item", itemId: entry.itemSlug, quantity: entry.quantity, displayName: nameOf(entry.itemSlug) },
    ),
    repeat: boss.repeat
      ? {
          gear: boss.repeat.gear,
          orangeChancePercent: boss.repeat.orangeChanceBp == null ? null : boss.repeat.orangeChanceBp / 100,
          extras: boss.repeat.extras.map((extra) => ({ itemId: extra.itemSlug, displayName: nameOf(extra.itemSlug), chancePercent: extra.chanceBp / 100, minQty: extra.minQty, maxQty: extra.maxQty })),
        }
      : null,
  }));
  return {
    id: row.slug,
    displayName: row.displayName,
    realmCode: row.requiredRealmOrder,
    realmName: realm?.displayName ?? "",
    realmMissing: realm == null,
    bosses,
    monsters: row.monsters ?? [],
    // 关卡自己改过的项（null = 跟随配置概览）
    monsterDrop: {
      chancePercent: row.monsterDrop?.chanceBp == null ? null : row.monsterDrop.chanceBp / 100,
      weights: Object.fromEntries(MONSTER_QUALITIES.map((key) => [key, row.monsterDrop?.qualityWeights?.[key] ?? null])),
    },
    dropCustomCount: customDropCount(row.monsterDrop),
    // 配置概览里的默认值（抽屉里灰字显示、「恢复默认」用）
    dropDefaults: {
      chancePercent: tuning.monsterDropChanceBp / 100,
      weights: Object.fromEntries(MONSTER_QUALITIES.map((key) => [key, tuning.monsterQualityWeights[key]])),
      orangeChancePercent: tuning.bossOrangeChanceBp / 100,
    },
    ...power,
  };
}

export async function listOpsStages(db: Db) {
  const [stages, realms, items, skills, world] = await Promise.all([
    db.select().from(contentStages),
    db.select().from(contentRealms),
    db.select().from(contentItems),
    db.select().from(contentSkills),
    loadDraftSnapshot(db),
  ]);
  const tuning = world.globals.tuning ?? tuningOf(null);
  return stages
    .sort((left, right) => left.requiredRealmOrder - right.requiredRealmOrder || left.displayName.localeCompare(right.displayName, "zh"))
    .map((row) => stageView(row, realms, items, skills, stagePowerOf(world, row.slug, row.recommendedPower), tuning));
}

export async function createOpsStage(
  db: Db,
  input: { displayName?: string; realmCode?: number; recommendedPower?: number | null; bosses?: BossInput[]; monsters?: MonsterInput[]; monsterDrop?: MonsterDropInput },
  adminId: string | null,
) {
  const displayName = textOf(input.displayName);
  if (!displayName) {
    throw new AppError("INVALID_INPUT", "请填写关卡名称");
  }
  const realmCode = Number(input.realmCode);
  if (!Number.isInteger(realmCode) || realmCode < 1) {
    throw new AppError("INVALID_INPUT", "请选择境界");
  }
  const realm = await realmByCode(db, realmCode);
  if (!realm) {
    throw new AppError("INVALID_INPUT", "没有这个境界");
  }
  const bosses = await readBosses(db, input.bosses);
  const monsters = readMonsters(input.monsters) ?? [];
  const monsterDrop = readMonsterDrop(input.monsterDrop, await tuningFor(db)) ?? null;
  const slug = newId("s");
  const now = new Date();
  const dropSlug = (suffix: string) => `${slug}_${suffix}`;
  await db.insert(contentDropTables).values([
    { slug: dropSlug("boss"), displayName: displayName, updatedAt: now, updatedBy: adminId },
    { slug: dropSlug("idle"), displayName: displayName, updatedAt: now, updatedBy: adminId },
    { slug: dropSlug("first"), displayName: displayName, updatedAt: now, updatedBy: adminId },
  ]);
  const first = bosses[0];
  await db.insert(contentStages).values({
    slug,
    displayName,
    sortOrder: 0,
    nextStageSlug: null,
    requiredRealmOrder: realmCode,
    recommendedPower: readRecommendedPower(input.recommendedPower) ?? null,
    bossName: first?.name ?? "",
    bossAttack: first?.attack ?? 0,
    bossDefense: first?.defense ?? 0,
    bossHp: first?.hp ?? 0,
    bossInterval: first?.interval ?? 0,
    bosses,
    monsters,
    monsterDrop,
    bossDropTableSlug: dropSlug("boss"),
    idleDropTableSlug: dropSlug("idle"),
    firstClearDropTableSlug: dropSlug("first"),
    updatedAt: now,
    updatedBy: adminId,
  });
  return { id: slug };
}

export async function updateOpsStage(
  db: Db,
  id: string,
  input: { displayName?: string; realmCode?: number; recommendedPower?: number | null; bosses?: BossInput[]; monsters?: MonsterInput[]; monsterDrop?: MonsterDropInput },
  adminId: string | null,
) {
  const [current] = await db.select().from(contentStages).where(eq(contentStages.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个关卡");
  }
  const displayName = textOf(input.displayName);
  if (!displayName) {
    throw new AppError("INVALID_INPUT", "请填写关卡名称");
  }
  const realmCode = Number(input.realmCode);
  if (!Number.isInteger(realmCode) || realmCode < 1) {
    throw new AppError("INVALID_INPUT", "请选择境界");
  }
  const realm = await realmByCode(db, realmCode);
  if (!realm) {
    throw new AppError("INVALID_INPUT", "没有这个境界");
  }
  const bosses = await readBosses(db, input.bosses, current.bosses ?? []);
  const monsters = readMonsters(input.monsters);
  const monsterDrop = readMonsterDrop(input.monsterDrop, await tuningFor(db));
  const first = bosses[0];
  await db
    .update(contentStages)
    .set({
      displayName,
      requiredRealmOrder: realmCode,
      ...(readRecommendedPower(input.recommendedPower) === undefined ? {} : { recommendedPower: readRecommendedPower(input.recommendedPower) }),
      nextStageSlug: null,
      sortOrder: 0,
      bossName: first?.name ?? "",
      bossAttack: first?.attack ?? 0,
      bossDefense: first?.defense ?? 0,
      bossHp: first?.hp ?? 0,
      bossInterval: first?.interval ?? 0,
      bosses,
      ...(monsters === undefined ? {} : { monsters }),
      ...(monsterDrop === undefined ? {} : { monsterDrop }),
      updatedAt: new Date(),
      updatedBy: adminId,
    })
    .where(eq(contentStages.slug, id));
  return { id };
}

export async function deleteOpsStage(db: Db, id: string) {
  const [current] = await db.select().from(contentStages).where(eq(contentStages.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个关卡");
  }
  const gated = await db.select().from(contentRealms).where(eq(contentRealms.requiredStageSlug, id));
  if (gated.length > 0) {
    throw new AppError("INVALID_INPUT", `境界「${gated[0]?.displayName}」把这个关卡设为突破门槛，请先改掉再删除`);
  }
  const dropSlugs = [current.bossDropTableSlug, current.idleDropTableSlug, current.firstClearDropTableSlug];
  await db.delete(contentStages).where(eq(contentStages.slug, id));
  for (const dropSlug of dropSlugs) {
    await db.delete(contentDropEntries).where(eq(contentDropEntries.dropTableSlug, dropSlug));
    await db.delete(contentDropTables).where(eq(contentDropTables.slug, dropSlug));
  }
  return { ok: true };
}

/** 后台「物品」页能设的类型（装备、功法书各有自己的页面，不在这里改）。 */
export const OPS_ITEM_KINDS = ["material", "pill"] as const;
const OPS_ITEM_QUALITIES = ["white", "green", "blue", "purple", "orange"];

type OpsItemInput = { displayName?: string; description?: string; kind?: string; quality?: string; stackable?: boolean };

function itemView(row: typeof contentItems.$inferSelect) {
  return {
    id: row.slug,
    displayName: row.displayName,
    description: row.description,
    kind: row.kind ?? "",
    quality: row.quality,
    stackable: row.stackable,
  };
}

export async function listOpsItems(db: Db) {
  const rows = await db.select().from(contentItems);
  return rows
    .filter((row) => row.kind !== "equipment" && row.kind !== "skill_book")
    .sort((left, right) => left.displayName.localeCompare(right.displayName, "zh"))
    .map(itemView);
}

export async function createOpsItem(db: Db, input: OpsItemInput, adminId: string | null) {
  const values = itemValues(input, null, adminId);
  const slug = newId("i");
  await db.insert(contentItems).values({ ...values, slug });
  return { id: slug };
}

export async function updateOpsItem(db: Db, id: string, input: OpsItemInput, adminId: string | null) {
  const [current] = await db.select().from(contentItems).where(eq(contentItems.slug, id)).limit(1);
  if (!current || current.kind === "equipment" || current.kind === "skill_book") {
    throw new AppError("NOT_FOUND", "没有这个物品");
  }
  await db.update(contentItems).set(itemValues(input, current, adminId)).where(eq(contentItems.slug, id));
  return { id };
}

/**
 * 物品保存：只改传了的字段。类型 / 品质 / 能否叠加不传 = 保持原样（以前会把类型清空，突破石因此变成“没有类型”，
 * 强化突破就认不出它是材料）。新建时默认是可叠加的白色材料。
 */
function itemValues(input: OpsItemInput, current: typeof contentItems.$inferSelect | null, adminId: string | null) {
  const displayName = textOf(input.displayName);
  if (!displayName) {
    throw new AppError("INVALID_INPUT", "请填写物品名称");
  }
  const kindRaw = input.kind === undefined || input.kind === null || input.kind === "" ? undefined : String(input.kind);
  if (kindRaw !== undefined && !(OPS_ITEM_KINDS as readonly string[]).includes(kindRaw)) {
    throw new AppError("INVALID_INPUT", "物品类型只能是材料或丹药");
  }
  const qualityRaw = input.quality === undefined || input.quality === null || input.quality === "" ? undefined : String(input.quality);
  if (qualityRaw !== undefined && !OPS_ITEM_QUALITIES.includes(qualityRaw)) {
    throw new AppError("INVALID_INPUT", "品质不正确");
  }
  if (input.stackable !== undefined && input.stackable !== null && typeof input.stackable !== "boolean") {
    throw new AppError("INVALID_INPUT", "能否叠加要填是或否");
  }
  return {
    displayName,
    description: textOf(input.description),
    kind: kindRaw ?? current?.kind ?? "material",
    quality: qualityRaw ?? current?.quality ?? "white",
    stackable: typeof input.stackable === "boolean" ? input.stackable : (current?.stackable ?? true),
    updatedAt: new Date(),
    updatedBy: adminId,
  };
}

export async function deleteOpsItem(db: Db, id: string) {
  const [current] = await db.select().from(contentItems).where(eq(contentItems.slug, id)).limit(1);
  if (!current || current.kind === "skill_book") {
    throw new AppError("NOT_FOUND", current?.kind === "skill_book" ? "技能书跟着功法，请到技能页删除" : "没有这个物品");
  }
  const stages = await db.select().from(contentStages);
  const used = stages.some((stage) => (stage.bosses ?? []).some((boss) => boss.drops.some((drop) => drop.itemSlug === id)));
  if (used) {
    throw new AppError("INVALID_INPUT", "这个物品还挂在首领上，先拿掉");
  }
  await db.delete(contentItems).where(eq(contentItems.slug, id));
  return { ok: true };
}

const SKILL_ROLES = ["heart", "attack", "body", "step"];
const SKILL_RANKS = ["yellow", "xuan", "earth", "heaven"];

function skillView(row: typeof contentSkills.$inferSelect, categories: { slug: string; displayName: string }[]) {
  const category = categories.find((item) => item.slug === row.skillCategorySlug);
  return {
    id: row.slug,
    displayName: row.displayName,
    description: row.description,
    categoryId: row.skillCategorySlug ?? "",
    categoryName: category?.displayName ?? "",
    categoryMissing: Boolean(row.skillCategorySlug) && !category,
    attack: row.attack / 100,
    defense: row.defense / 100,
    hp: row.hp / 100,
    speed: 0,
    cultivateBonus: row.cultivateBonusBp,
    role: row.role ?? "",
    rank: row.rank,
    requiredRealmCode: row.requiredRealmOrder,
    prerequisiteIds: row.prerequisiteSkillSlugs ?? [],
  };
}

export async function listOpsSkills(db: Db) {
  const [rows, categories] = await Promise.all([db.select().from(contentSkills), db.select().from(contentSkillCategories)]);
  return rows.sort((left, right) => left.displayName.localeCompare(right.displayName, "zh")).map((row) => skillView(row, categories));
}

/** 功法书的默认说明（新建时写入；后台可以改）。和服务器 useItem 的规则一致：没学会→学会，学会了→升一层，7 层满后转修为。 */
export function skillBookDescription(skillName: string): string {
  return `使用后学会功法「${skillName}」；已学会时每用一本提升一层（最多 7 层），满层后再使用会转为修为。`;
}

export async function ensureSkillBook(db: Db, skill: { slug: string; displayName: string }, adminId: string | null) {
  const displayName = `${skill.displayName}技能书`;
  const [existing] = await db.select().from(contentItems).where(eq(contentItems.skillSlug, skill.slug)).limit(1);
  if (existing) {
    if (existing.kind !== "skill_book" || existing.displayName !== displayName || existing.stackable) {
      await db
        .update(contentItems)
        .set({ displayName, kind: "skill_book", skillSlug: skill.slug, stackable: false, updatedAt: new Date(), updatedBy: adminId })
        .where(eq(contentItems.slug, existing.slug));
    }
    return existing.slug;
  }
  const slug = newId("b");
  await db.insert(contentItems).values({
    slug,
    displayName,
    kind: "skill_book",
    skillSlug: skill.slug,
    stackable: false,
    description: skillBookDescription(skill.displayName),
    updatedAt: new Date(),
    updatedBy: adminId,
  });
  return slug;
}

export async function ensureSkillBooks(db: Db) {
  const skills = await db.select().from(contentSkills);
  for (const skill of skills) {
    await ensureSkillBook(db, skill, null);
  }
}

export async function createOpsSkill(
  db: Db,
  input: {
    displayName?: string;
    description?: string;
    categoryId?: string;
    attack?: number;
    defense?: number;
    hp?: number;
    speed?: number;
    cultivateBonus?: number;
    role?: string;
    rank?: string;
    requiredRealmCode?: number;
    prerequisiteIds?: string[];
  },
  adminId: string | null,
) {
  const values = await skillValues(db, input, adminId);
  const slug = newId("k");
  await db.insert(contentSkills).values({ ...values, slug });
  await ensureSkillBook(db, { slug, displayName: values.displayName }, adminId);
  return { id: slug };
}

export async function updateOpsSkill(
  db: Db,
  id: string,
  input: {
    displayName?: string;
    description?: string;
    categoryId?: string;
    attack?: number;
    defense?: number;
    hp?: number;
    speed?: number;
    cultivateBonus?: number;
    role?: string;
    rank?: string;
    requiredRealmCode?: number;
    prerequisiteIds?: string[];
  },
  adminId: string | null,
) {
  const [current] = await db.select().from(contentSkills).where(eq(contentSkills.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个功法");
  }
  const next = await skillValues(db, input, adminId, current);
  await db.update(contentSkills).set(next).where(eq(contentSkills.slug, id));
  await ensureSkillBook(db, { slug: id, displayName: next.displayName }, adminId);
  return { id };
}

function percentBp(value: unknown, label: string): number {
  const number = numberOf(value, label);
  if (number > 100) {
    throw new AppError("INVALID_INPUT", `${label}不能超过 100%`);
  }
  return Math.round(number * 100);
}

async function skillValues(
  db: Db,
  input: {
    displayName?: string;
    description?: string;
    categoryId?: string;
    attack?: number;
    defense?: number;
    hp?: number;
    speed?: number;
    cultivateBonus?: number;
    role?: string;
    rank?: string;
    requiredRealmCode?: number;
    prerequisiteIds?: string[];
  },
  adminId: string | null,
  current: typeof contentSkills.$inferSelect | null = null,
) {
  const displayName = textOf(input.displayName);
  if (!displayName) {
    throw new AppError("INVALID_INPUT", "请填写功法名称");
  }
  // 类型、品阶、所需境界、前置功法：不传 = 保持原样（以前每次保存都把类型和前置功法清空）。
  const role = input.role === undefined || input.role === null || input.role === "" ? (current?.role ?? null) : String(input.role);
  if (role !== null && !SKILL_ROLES.includes(role)) {
    throw new AppError("INVALID_INPUT", "功法类型不正确");
  }
  const rank = input.rank === undefined || input.rank === null || input.rank === "" ? (current?.rank ?? "yellow") : String(input.rank);
  if (!SKILL_RANKS.includes(rank)) {
    throw new AppError("INVALID_INPUT", "功法品阶只能是黄、玄、地、天");
  }
  let requiredRealmOrder = current?.requiredRealmOrder ?? 0;
  if (input.requiredRealmCode !== undefined && input.requiredRealmCode !== null) {
    const order = Number(input.requiredRealmCode);
    if (!Number.isInteger(order) || order < 0) {
      throw new AppError("INVALID_INPUT", "所需境界不正确");
    }
    requiredRealmOrder = order;
  }
  let prerequisiteSkillSlugs = current?.prerequisiteSkillSlugs ?? [];
  if (input.prerequisiteIds !== undefined && input.prerequisiteIds !== null) {
    if (!Array.isArray(input.prerequisiteIds)) {
      throw new AppError("INVALID_INPUT", "前置功法格式不正确");
    }
    const ids = [...new Set(input.prerequisiteIds.map((value) => String(value)).filter(Boolean))];
    if (current && ids.includes(current.slug)) {
      throw new AppError("INVALID_INPUT", "前置功法不能是自己");
    }
    const known = new Set((await db.select({ slug: contentSkills.slug }).from(contentSkills)).map((row) => row.slug));
    const missing = ids.find((value) => !known.has(value));
    if (missing) {
      throw new AppError("INVALID_INPUT", `前置功法 ${missing} 不存在`);
    }
    prerequisiteSkillSlugs = ids;
  }
  const categoryId = textOf(input.categoryId);
  if (!categoryId) {
    throw new AppError("INVALID_INPUT", "请选择分类");
  }
  const [category] = await db.select().from(contentSkillCategories).where(eq(contentSkillCategories.slug, categoryId)).limit(1);
  if (!category) {
    throw new AppError("INVALID_INPUT", "分类不存在");
  }
  return {
    displayName,
    description: textOf(input.description),
    role,
    rank,
    requiredRealmOrder,
    skillCategorySlug: categoryId,
    attack: percentBp(input.attack, "攻击百分比"),
    defense: percentBp(input.defense, "防御百分比"),
    hp: percentBp(input.hp, "气血百分比"),
    speed: 0,
    cultivateBonusBp: numberOf(input.cultivateBonus, "修炼加成"),
    prerequisiteSkillSlugs,
    updatedAt: new Date(),
    updatedBy: adminId,
  };
}

export async function deleteOpsSkill(db: Db, id: string) {
  const [current] = await db.select().from(contentSkills).where(eq(contentSkills.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个功法");
  }
  const stages = await db.select().from(contentStages);
  if (stages.some((stage) => (stage.bosses ?? []).some((boss) => boss.drops.some((drop) => drop.itemSlug === id)))) {
    throw new AppError("INVALID_INPUT", "这门功法还挂在首领上，先拿掉");
  }
  const items = await db.select().from(contentItems);
  const books = items.filter((item) => item.skillSlug === id && item.kind === "skill_book");
  const others = items.filter((item) => item.skillSlug === id && item.kind !== "skill_book");
  if (others.length > 0) {
    throw new AppError("INVALID_INPUT", "还有功法书指向这门功法");
  }
  for (const book of books) {
    const [held] = await db.select().from(playerItems).where(eq(playerItems.itemSlug, book.slug)).limit(1);
    if (held) {
      throw new AppError("INVALID_INPUT", "还有人拿着这本技能书");
    }
  }
  for (const book of books) {
    await db.delete(contentItems).where(eq(contentItems.slug, book.slug));
  }
  await db.delete(contentSkills).where(eq(contentSkills.slug, id));
  return { ok: true };
}

async function assertCategoryName(name: string) {
  if (!name) {
    throw new AppError("INVALID_INPUT", "请填写分类名称");
  }
}


export async function listSkillCategories(db: Db) {
  const rows = await db.select().from(contentSkillCategories);
  return rows
    .sort((left, right) => left.displayName.localeCompare(right.displayName, "zh"))
    .map((row) => ({ id: row.slug, displayName: row.displayName }));
}

export async function createSkillCategory(db: Db, input: { displayName?: string }, adminId: string | null) {
  const displayName = textOf(input.displayName);
  await assertCategoryName(displayName);
  const rows = await db.select().from(contentSkillCategories);
  if (rows.some((row) => row.displayName === displayName)) {
    throw new AppError("INVALID_INPUT", "名称不能重复");
  }
  const slug = newId("sc");
  await db.insert(contentSkillCategories).values({ slug, displayName, updatedAt: new Date(), updatedBy: adminId });
  return { id: slug };
}

export async function updateSkillCategory(db: Db, id: string, input: { displayName?: string }, adminId: string | null) {
  const [current] = await db.select().from(contentSkillCategories).where(eq(contentSkillCategories.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个分类");
  }
  const displayName = textOf(input.displayName);
  await assertCategoryName(displayName);
  const rows = await db.select().from(contentSkillCategories);
  if (rows.some((row) => row.displayName === displayName && row.slug !== id)) {
    throw new AppError("INVALID_INPUT", "名称不能重复");
  }
  await db
    .update(contentSkillCategories)
    .set({ displayName, updatedAt: new Date(), updatedBy: adminId })
    .where(eq(contentSkillCategories.slug, id));
  return { id };
}

export async function deleteSkillCategory(db: Db, id: string) {
  const [current] = await db.select().from(contentSkillCategories).where(eq(contentSkillCategories.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个分类");
  }
  const skills = await db.select().from(contentSkills);
  if (skills.some((skill) => skill.skillCategorySlug === id)) {
    throw new AppError("INVALID_INPUT", "这个分类下还有功法");
  }
  await db.delete(contentSkillCategories).where(eq(contentSkillCategories.slug, id));
  return { ok: true };
}

