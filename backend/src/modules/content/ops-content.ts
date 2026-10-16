import { randomBytes } from "node:crypto";
import { eq } from "drizzle-orm";
import type { BossRepeatReward, BossRewardEntry, MonsterDropConfig, QualityWeights, StageMonster } from "./combat-types.js";
import { contentDropEntries, contentDropTables, contentItems, contentRealms, contentSkillCategories, contentSkills, contentStages, playerItems, type StageBoss } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { loadDraftSnapshot } from "./snapshot.js";
import { stageAutoPower } from "./stage-power.js";
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
  repeat?: { gear?: boolean; extras?: { itemId?: string; chancePercent?: number; minQty?: number; maxQty?: number }[] } | null;
};

type MonsterInput = { name?: string; attack?: number; defense?: number; hp?: number; interval?: number; killCultivation?: number };
type MonsterDropInput = { chancePercent?: number; weights?: Partial<Record<"white" | "green" | "blue" | "purple", number>> } | null;

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

function readMonsterDrop(input: MonsterDropInput | undefined): MonsterDropConfig | null | undefined {
  if (input === undefined) {
    return undefined;
  }
  if (input === null) {
    return null;
  }
  const percent = numberOf(input.chancePercent ?? 0, "怪物掉率");
  if (percent > 100) {
    throw new AppError("INVALID_INPUT", "怪物掉率不能超过 100%");
  }
  const weights: QualityWeights = {};
  for (const key of ["white", "green", "blue", "purple"] as const) {
    weights[key] = numberOf(input.weights?.[key] ?? 0, "品质权重");
  }
  if (percent > 0 && Object.values(weights).every((value) => value === 0)) {
    throw new AppError("INVALID_INPUT", "品质权重至少有一档大于 0");
  }
  return { chanceBp: Math.round(percent * 100), qualityWeights: weights };
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
  return { gear: input.gear === true, extras };
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

type StagePowerView = { recommendedPower: number; effectivePower: number | null; autoPower: number | null; powerProblem: string | null };

/** recommendedPower = 后台手填的值（0 = 没填，按首领自动算）；autoPower = 按首领数值算出的参考值；effectivePower = 玩家实际看到的。 */
function stagePowerOf(world: ContentSnapshot, slug: string): StagePowerView {
  const stage = world.stages.find((candidate) => candidate.slug === slug);
  if (!stage) {
    throw new AppError("INTERNAL");
  }
  const manual = Math.max(0, Math.round(Number(stage.recommendedPower ?? 0)));
  if ((stage.bosses ?? []).length === 0) {
    return { recommendedPower: manual, effectivePower: manual > 0 ? manual : null, autoPower: null, powerProblem: null };
  }
  try {
    const auto = stageAutoPower(world, stage);
    return { recommendedPower: manual, effectivePower: manual > 0 ? manual : auto, autoPower: auto, powerProblem: null };
  } catch (cause) {
    if (cause instanceof AppError) {
      return { recommendedPower: manual, effectivePower: manual > 0 ? manual : null, autoPower: null, powerProblem: manual > 0 ? null : cause.message };
    }
    throw cause;
  }
}

function readRecommendedPower(value: unknown): number | undefined {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0 || number > 10_000_000) {
    throw new AppError("INVALID_INPUT", "推荐战力要填 0 到 1000 万的整数（0 表示按首领数值自动算）");
  }
  return number;
}

function stageView(
  row: typeof contentStages.$inferSelect,
  realms: { slug: string; displayName: string; sortOrder: number }[],
  items: { slug: string; displayName: string }[],
  skills: { slug: string; displayName: string }[],
  power: StagePowerView,
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
    monsterDrop: row.monsterDrop ? { chancePercent: row.monsterDrop.chanceBp / 100, weights: row.monsterDrop.qualityWeights } : null,
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
  return stages
    .sort((left, right) => left.requiredRealmOrder - right.requiredRealmOrder || left.displayName.localeCompare(right.displayName, "zh"))
    .map((row) => stageView(row, realms, items, skills, stagePowerOf(world, row.slug)));
}

export async function createOpsStage(
  db: Db,
  input: { displayName?: string; realmCode?: number; recommendedPower?: number; bosses?: BossInput[]; monsters?: MonsterInput[]; monsterDrop?: MonsterDropInput },
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
  const monsterDrop = readMonsterDrop(input.monsterDrop) ?? null;
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
    recommendedPower: readRecommendedPower(input.recommendedPower) ?? 0,
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
  input: { displayName?: string; realmCode?: number; recommendedPower?: number; bosses?: BossInput[]; monsters?: MonsterInput[]; monsterDrop?: MonsterDropInput },
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
  const monsterDrop = readMonsterDrop(input.monsterDrop);
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

function itemView(row: typeof contentItems.$inferSelect) {
  return {
    id: row.slug,
    displayName: row.displayName,
    description: row.description,
  };
}

export async function listOpsItems(db: Db) {
  const rows = await db.select().from(contentItems);
  return rows
    .filter((row) => row.kind !== "equipment" && row.kind !== "skill_book")
    .sort((left, right) => left.displayName.localeCompare(right.displayName, "zh"))
    .map(itemView);
}

export async function createOpsItem(db: Db, input: { displayName?: string; description?: string }, adminId: string | null) {
  const values = itemValues(input, adminId);
  const slug = newId("i");
  await db.insert(contentItems).values({ ...values, slug });
  return { id: slug };
}

export async function updateOpsItem(db: Db, id: string, input: { displayName?: string; description?: string }, adminId: string | null) {
  const [current] = await db.select().from(contentItems).where(eq(contentItems.slug, id)).limit(1);
  if (!current || current.kind === "equipment" || current.kind === "skill_book") {
    throw new AppError("NOT_FOUND", "没有这个物品");
  }
  await db.update(contentItems).set(itemValues(input, adminId)).where(eq(contentItems.slug, id));
  return { id };
}

function itemValues(input: { displayName?: string; description?: string }, adminId: string | null) {
  const displayName = textOf(input.displayName);
  if (!displayName) {
    throw new AppError("INVALID_INPUT", "请填写物品名称");
  }
  return {
    displayName,
    description: textOf(input.description),
    kind: null,
    slot: null,
    skillSlug: null,
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
  };
}

export async function listOpsSkills(db: Db) {
  const [rows, categories] = await Promise.all([db.select().from(contentSkills), db.select().from(contentSkillCategories)]);
  return rows.sort((left, right) => left.displayName.localeCompare(right.displayName, "zh")).map((row) => skillView(row, categories));
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
    description: "",
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
  },
  adminId: string | null,
) {
  const values = await skillValues(db, input, adminId);
  const slug = newId("k");
  await db.insert(contentSkills).values({ ...values, slug, prerequisiteSkillSlugs: [] });
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
  },
  adminId: string | null,
) {
  const [current] = await db.select().from(contentSkills).where(eq(contentSkills.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个功法");
  }
  const next = await skillValues(db, input, adminId);
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
  },
  adminId: string | null,
) {
  const displayName = textOf(input.displayName);
  if (!displayName) {
    throw new AppError("INVALID_INPUT", "请填写功法名称");
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
    role: null,
    skillCategorySlug: categoryId,
    attack: percentBp(input.attack, "攻击百分比"),
    defense: percentBp(input.defense, "防御百分比"),
    hp: percentBp(input.hp, "气血百分比"),
    speed: 0,
    cultivateBonusBp: numberOf(input.cultivateBonus, "修炼加成"),
    prerequisiteSkillSlugs: [] as string[],
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

