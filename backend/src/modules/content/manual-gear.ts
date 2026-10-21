/**
 * 手动装备与套装（ADMIN_SPEC §10、§12）。
 * - 手动装备：编号 gear_m_0001…，数值手填，「重新生成」永远不碰（syncGear 只管公式 90 件）；强化 / 分解和公式装备完全一样（按品质读强化规则）。
 *   默认不参与随机掉落（只靠指定掉落、补发）；打开后进入「需求境界所在大境界 + 品质」的随机池，按掉率倍数分配。
 * - 套装：只有手动装备能进；一件最多属于一个套装；同一套装每个部位最多 1 件、成员必须同一个大境界。
 *   加成按件数分档（2–6 件，不重复），穿够的档全部生效；百分比按角色总属性算，固定值直接加。
 */
import { eq, inArray, like } from "drizzle-orm";
import { contentGearSets, contentItems, contentRealms, contentStages, playerItems } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { isQualityKey, isSlotKey, QUALITY_TABLE, SLOT_TABLE } from "./catalog.js";
import { SET_STATS, type SetTier } from "./combat-types.js";
import { GEAR_DROP_MULT_MAX } from "./gear.js";

export const MANUAL_PREFIX = "gear_m_";
const ICON = /^[a-z][a-z0-9_]{0,63}$/;
const SET_SLUG = /^set_[a-z0-9_]{1,40}$/;

export type ManualGearInput = {
  displayName?: unknown;
  description?: unknown;
  iconKey?: unknown;
  slot?: unknown;
  quality?: unknown;
  requiredRealmOrder?: unknown;
  attack?: unknown;
  defense?: unknown;
  hp?: unknown;
  speed?: unknown;
  setSlug?: unknown;
  randomDrop?: unknown;
  dropMult?: unknown;
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function stat(value: unknown, label: string): number {
  if (value === undefined || value === null || value === "") {
    return 0;
  }
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || number > 1_000_000) {
    throw new AppError("INVALID_INPUT", `${label}要在 0 到 1000000 之间`);
  }
  return Math.round(number * 100) / 100;
}

async function realmsOf(db: Db) {
  return db.select({ sortOrder: contentRealms.sortOrder, majorKey: contentRealms.majorKey, majorName: contentRealms.majorName, displayName: contentRealms.displayName }).from(contentRealms);
}

function majorOf(realms: Awaited<ReturnType<typeof realmsOf>>, order: number): string | null {
  const realm = realms.find((row) => row.sortOrder === order);
  return realm ? realm.majorKey || realm.majorName || null : null;
}

/** 下一个手动装备编号 gear_m_0001、gear_m_0002…（取现有最大号 + 1）。 */
export async function nextManualSlug(db: Db): Promise<string> {
  const rows = await db.select({ slug: contentItems.slug }).from(contentItems).where(like(contentItems.slug, `${MANUAL_PREFIX}%`));
  const max = rows.reduce((top, row) => Math.max(top, Number(row.slug.slice(MANUAL_PREFIX.length)) || 0), 0);
  return `${MANUAL_PREFIX}${String(max + 1).padStart(4, "0")}`;
}

/** 套装成员检查：手动装备、同大境界、部位不重复、最多 6 件。 */
async function assertSetFits(db: Db, setSlug: string, member: { slug: string; slot: string; major: string | null }) {
  const [set] = await db.select().from(contentGearSets).where(eq(contentGearSets.slug, setSlug)).limit(1);
  if (!set) {
    throw new AppError("INVALID_INPUT", "没有这个套装");
  }
  const realms = await realmsOf(db);
  const others = (await db.select().from(contentItems).where(eq(contentItems.setSlug, setSlug))).filter((row) => row.slug !== member.slug);
  const clash = others.find((row) => row.slot === member.slot);
  if (clash) {
    throw new AppError("INVALID_INPUT", `套装「${set.displayName}」的${SLOT_TABLE.find((row) => row.key === member.slot)?.name ?? "这个部位"}已经有「${clash.displayName}」`);
  }
  const otherMajor = others.map((row) => majorOf(realms, row.requiredRealmOrder)).find((key) => key);
  if (otherMajor && member.major && otherMajor !== member.major) {
    throw new AppError("INVALID_INPUT", `套装「${set.displayName}」的成员都要是同一个大境界`);
  }
}

function manualValues(input: ManualGearInput, realms: Awaited<ReturnType<typeof realmsOf>>) {
  const displayName = text(input.displayName);
  if (!displayName) {
    throw new AppError("INVALID_INPUT", "请填写装备名称");
  }
  if (displayName.length > 40) {
    throw new AppError("INVALID_INPUT", "装备名称最多 40 个字");
  }
  const description = text(input.description);
  if (description.length > 200) {
    throw new AppError("INVALID_INPUT", "描述最多 200 个字");
  }
  const iconKey = text(input.iconKey);
  if (!iconKey) {
    throw new AppError("INVALID_INPUT", "请选择图标");
  }
  if (!ICON.test(iconKey)) {
    throw new AppError("INVALID_INPUT", "图标标识只能用小写字母、数字和下划线");
  }
  if (!isSlotKey(input.slot)) {
    throw new AppError("INVALID_INPUT", "请选择部位");
  }
  if (!isQualityKey(input.quality)) {
    throw new AppError("INVALID_INPUT", "请选择品质");
  }
  const order = Number(input.requiredRealmOrder);
  if (!Number.isInteger(order) || !realms.some((row) => row.sortOrder === order)) {
    throw new AppError("INVALID_INPUT", "请选择需求境界");
  }
  const stats = { attack: stat(input.attack, "攻击"), defense: stat(input.defense, "防御"), hp: stat(input.hp, "气血"), speed: stat(input.speed, "速度") };
  if (stats.attack + stats.defense + stats.hp + stats.speed <= 0) {
    throw new AppError("INVALID_INPUT", "攻击、防御、气血、速度至少填一项");
  }
  const randomDrop = input.randomDrop === true;
  let dropMult = 1;
  if (randomDrop && input.dropMult !== undefined && input.dropMult !== null && input.dropMult !== "") {
    dropMult = Number(input.dropMult);
    if (!Number.isFinite(dropMult) || dropMult < 0 || dropMult > GEAR_DROP_MULT_MAX) {
      throw new AppError("INVALID_INPUT", `掉率倍数要在 0 到 ${GEAR_DROP_MULT_MAX} 之间`);
    }
    dropMult = Math.round(dropMult * 100) / 100;
  }
  const setSlug = text(input.setSlug) || null;
  return {
    displayName,
    description,
    iconKey,
    slot: input.slot,
    quality: input.quality,
    requiredRealmOrder: order,
    ...stats,
    randomDrop,
    dropMult,
    setSlug,
  };
}

export async function createManualGear(db: Db, input: ManualGearInput, adminId: string | null) {
  const realms = await realmsOf(db);
  const values = manualValues(input, realms);
  const slug = await nextManualSlug(db);
  if (values.setSlug) {
    await assertSetFits(db, values.setSlug, { slug, slot: values.slot, major: majorOf(realms, values.requiredRealmOrder) });
  }
  await db.insert(contentItems).values({
    slug,
    kind: "equipment",
    origin: "manual",
    stackable: false,
    nameCustom: true,
    descriptionCustom: true,
    ...values,
    updatedAt: new Date(),
    updatedBy: adminId,
  });
  return { id: slug };
}

export async function updateManualGear(db: Db, slug: string, input: ManualGearInput, adminId: string | null) {
  const [current] = await db.select().from(contentItems).where(eq(contentItems.slug, slug)).limit(1);
  if (!current || current.origin !== "manual") {
    throw new AppError("NOT_FOUND", "没有这件手动装备");
  }
  const realms = await realmsOf(db);
  const values = manualValues(input, realms);
  if (values.slot !== current.slot) {
    const equipped = (await db.select({ equippedSlot: playerItems.equippedSlot }).from(playerItems).where(eq(playerItems.itemSlug, slug))).some((row) => row.equippedSlot);
    if (equipped) {
      throw new AppError("INVALID_INPUT", "有玩家穿着这件装备，不能改部位");
    }
  }
  if (values.setSlug) {
    await assertSetFits(db, values.setSlug, { slug, slot: values.slot, major: majorOf(realms, values.requiredRealmOrder) });
  }
  await db.update(contentItems).set({ ...values, updatedAt: new Date(), updatedBy: adminId }).where(eq(contentItems.slug, slug));
  return { id: slug };
}

// ---------------------------------------------------------------- 套装

export type SetInput = { slug?: unknown; displayName?: unknown; description?: unknown; tiers?: unknown; members?: unknown };

export const SET_LIMITS = { maxTiers: 5, maxStatsPerTier: 4, maxPct: 100, maxFlat: 1_000_000 } as const;

export function setTiersFromInput(raw: unknown): SetTier[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new AppError("INVALID_INPUT", "套装加成至少要有一档");
  }
  if (raw.length > SET_LIMITS.maxTiers) {
    throw new AppError("INVALID_INPUT", `套装加成最多 ${SET_LIMITS.maxTiers} 档`);
  }
  const seen = new Set<number>();
  const tiers = raw.map((tier, index) => {
    const label = `第 ${index + 1} 档`;
    const pieces = Number((tier as SetTier)?.pieces);
    if (!Number.isInteger(pieces) || pieces < 2 || pieces > 6) {
      throw new AppError("INVALID_INPUT", `${label}：件数要在 2–6 之间`);
    }
    if (seen.has(pieces)) {
      throw new AppError("INVALID_INPUT", `${label}：件数 ${pieces} 重复了`);
    }
    seen.add(pieces);
    const rows = (tier as SetTier)?.stats;
    if (!Array.isArray(rows) || rows.length === 0 || rows.length > SET_LIMITS.maxStatsPerTier) {
      throw new AppError("INVALID_INPUT", `${label}：要有 1–${SET_LIMITS.maxStatsPerTier} 条属性`);
    }
    const keys = new Set<string>();
    const stats = rows.map((row, rowIndex) => {
      const where = `${label}第 ${rowIndex + 1} 条`;
      if (!(SET_STATS as readonly string[]).includes(row?.stat)) {
        throw new AppError("INVALID_INPUT", `${where}：请选择属性`);
      }
      if (row?.mode !== "pct" && row?.mode !== "flat") {
        throw new AppError("INVALID_INPUT", `${where}：请选择加成方式`);
      }
      const key = `${row.stat}:${row.mode}`;
      if (keys.has(key)) {
        throw new AppError("INVALID_INPUT", `${where}：同一属性同一种加成方式只能写一次`);
      }
      keys.add(key);
      const value = Number(row?.value);
      const max = row.mode === "pct" ? SET_LIMITS.maxPct : SET_LIMITS.maxFlat;
      if (!Number.isFinite(value) || value <= 0 || value > max) {
        throw new AppError("INVALID_INPUT", `${where}：数值要大于 0、不超过 ${max}`);
      }
      return { stat: row.stat, mode: row.mode, value: Math.round(value * 100) / 100 };
    });
    return { pieces, stats };
  });
  return tiers.sort((left, right) => left.pieces - right.pieces);
}

async function nextSetSlug(db: Db): Promise<string> {
  const rows = await db.select({ slug: contentGearSets.slug }).from(contentGearSets);
  const max = rows.reduce((top, row) => Math.max(top, Number(row.slug.match(/^set_(\d+)$/)?.[1] ?? 0)), 0);
  return `set_${String(max + 1).padStart(4, "0")}`;
}

/** 把成员列表写进 content_items.set_slug：检查手动、同大境界、部位不重复、不在别的套装里。 */
async function writeMembers(db: Db, setSlug: string, raw: unknown, adminId: string | null) {
  if (raw === undefined) {
    return;
  }
  if (!Array.isArray(raw) || raw.length > SLOT_TABLE.length) {
    throw new AppError("INVALID_INPUT", `套装成员最多 ${SLOT_TABLE.length} 件`);
  }
  const slugs = [...new Set(raw.map((value) => text(value)).filter(Boolean))];
  const rows = slugs.length > 0 ? await db.select().from(contentItems).where(inArray(contentItems.slug, slugs)) : [];
  const realms = await realmsOf(db);
  const slots = new Set<string>();
  let major: string | null = null;
  for (const slug of slugs) {
    const row = rows.find((item) => item.slug === slug);
    if (!row || row.kind !== "equipment") {
      throw new AppError("INVALID_INPUT", `没有装备 ${slug}`);
    }
    if (row.origin !== "manual") {
      throw new AppError("INVALID_INPUT", `「${row.displayName}」是公式装备，只有手动装备能进套装`);
    }
    if (row.setSlug && row.setSlug !== setSlug) {
      throw new AppError("INVALID_INPUT", `「${row.displayName}」已经属于别的套装`);
    }
    if (slots.has(row.slot ?? "")) {
      throw new AppError("INVALID_INPUT", `套装里${SLOT_TABLE.find((item) => item.key === row.slot)?.name ?? "这个部位"}重复了`);
    }
    slots.add(row.slot ?? "");
    const rowMajor = majorOf(realms, row.requiredRealmOrder);
    if (major && rowMajor && major !== rowMajor) {
      throw new AppError("INVALID_INPUT", "套装成员都要是同一个大境界");
    }
    major = major ?? rowMajor;
  }
  const now = new Date();
  await db.update(contentItems).set({ setSlug: null, updatedAt: now, updatedBy: adminId }).where(eq(contentItems.setSlug, setSlug));
  if (slugs.length > 0) {
    await db.update(contentItems).set({ setSlug, updatedAt: now, updatedBy: adminId }).where(inArray(contentItems.slug, slugs));
  }
}

export async function createGearSet(db: Db, input: SetInput, adminId: string | null) {
  const displayName = text(input.displayName);
  if (!displayName || displayName.length > 20) {
    throw new AppError("INVALID_INPUT", "请填写套装名称（最多 20 个字）");
  }
  const tiers = setTiersFromInput(input.tiers);
  const wanted = text(input.slug);
  if (wanted && !SET_SLUG.test(wanted)) {
    throw new AppError("INVALID_INPUT", "套装编号只能是 set_ 开头的小写字母、数字、下划线");
  }
  const slug = wanted || (await nextSetSlug(db));
  const [exists] = await db.select({ slug: contentGearSets.slug }).from(contentGearSets).where(eq(contentGearSets.slug, slug)).limit(1);
  if (exists) {
    throw new AppError("INVALID_INPUT", "套装编号已经存在");
  }
  return db.transaction(async (tx) => {
    await tx.insert(contentGearSets).values({ slug, displayName, description: text(input.description).slice(0, 200), tiers, updatedAt: new Date(), updatedBy: adminId });
    await writeMembers(tx as unknown as Db, slug, input.members, adminId);
    return { id: slug };
  });
}

export async function updateGearSet(db: Db, slug: string, input: SetInput, adminId: string | null) {
  const [current] = await db.select().from(contentGearSets).where(eq(contentGearSets.slug, slug)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个套装");
  }
  const displayName = text(input.displayName);
  if (!displayName || displayName.length > 20) {
    throw new AppError("INVALID_INPUT", "请填写套装名称（最多 20 个字）");
  }
  const tiers = setTiersFromInput(input.tiers);
  return db.transaction(async (tx) => {
    await tx
      .update(contentGearSets)
      .set({ displayName, description: text(input.description).slice(0, 200), tiers, updatedAt: new Date(), updatedBy: adminId })
      .where(eq(contentGearSets.slug, slug));
    await writeMembers(tx as unknown as Db, slug, input.members, adminId);
    return { id: slug };
  });
}

export async function deleteGearSet(db: Db, slug: string, adminId: string | null) {
  const [current] = await db.select().from(contentGearSets).where(eq(contentGearSets.slug, slug)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个套装");
  }
  return db.transaction(async (tx) => {
    await tx.update(contentItems).set({ setSlug: null, updatedAt: new Date(), updatedBy: adminId }).where(eq(contentItems.setSlug, slug));
    await tx.delete(contentGearSets).where(eq(contentGearSets.slug, slug));
    return { ok: true };
  });
}

/** 后台装备页要的手动装备 + 套装 + 品质 / 部位表。 */
export async function listManualAndSets(db: Db, weights: { attack: number; defense: number; hp: number; speed: number } | null) {
  const [items, sets, realms, stages] = await Promise.all([db.select().from(contentItems), db.select().from(contentGearSets), realmsOf(db), db.select().from(contentStages)]);
  const realmOf = (order: number) => realms.find((row) => row.sortOrder === order);
  const power = (row: { attack: number; defense: number; hp: number; speed: number }) =>
    weights ? Math.round(row.attack * weights.attack + row.defense * weights.defense + row.hp * weights.hp + row.speed * weights.speed) : null;
  const designatedUse = (slug: string) =>
    stages.flatMap((stage) => (stage.designatedDrops ?? []).filter((drop) => drop.itemSlug === slug).map((drop) => ({ stageId: stage.slug, stageName: stage.displayName, trigger: drop.trigger, chancePercent: drop.chanceBp / 100, count: drop.count })));
  const manual = items
    .filter((row) => row.origin === "manual")
    .sort((left, right) => left.slug.localeCompare(right.slug))
    .map((row) => ({
      id: row.slug,
      origin: "manual" as const,
      displayName: row.displayName,
      description: row.description,
      iconKey: row.iconKey,
      slot: row.slot,
      slotName: SLOT_TABLE.find((slot) => slot.key === row.slot)?.name ?? "",
      quality: row.quality,
      qualityName: QUALITY_TABLE.find((quality) => quality.key === row.quality)?.short ?? "",
      requiredRealmOrder: row.requiredRealmOrder,
      realmName: realmOf(row.requiredRealmOrder)?.displayName ?? "",
      majorKey: realmOf(row.requiredRealmOrder)?.majorKey ?? null,
      majorName: realmOf(row.requiredRealmOrder)?.majorName ?? "",
      attack: row.attack,
      defense: row.defense,
      hp: row.hp,
      speed: row.speed,
      power: power(row),
      setSlug: row.setSlug,
      setName: sets.find((set) => set.slug === row.setSlug)?.displayName ?? null,
      randomDrop: row.randomDrop,
      dropMult: row.dropMult,
      enabled: row.enabled,
      designated: designatedUse(row.slug),
    }));
  const setRows = sets
    .sort((left, right) => left.slug.localeCompare(right.slug))
    .map((set) => {
      const members = manual.filter((row) => row.setSlug === set.slug);
      const qualities = [...new Set(members.map((row) => row.quality))];
      return {
        id: set.slug,
        displayName: set.displayName,
        description: set.description,
        tiers: [...set.tiers].sort((left, right) => left.pieces - right.pieces),
        members: members.map((row) => ({ id: row.id, displayName: row.displayName, slot: row.slot, slotName: row.slotName, quality: row.quality, iconKey: row.iconKey, attack: row.attack, defense: row.defense, hp: row.hp, speed: row.speed })),
        majorName: members[0]?.majorName ?? "",
        majorKey: members[0]?.majorKey ?? null,
        quality: qualities.length === 1 ? qualities[0] : qualities.length > 1 ? "mixed" : null,
        updatedAt: set.updatedAt,
      };
    });
  return { manual, sets: setRows, qualities: QUALITY_TABLE, slotTable: SLOT_TABLE, nextManualId: await nextManualSlug(db) };
}
