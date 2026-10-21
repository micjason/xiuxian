import { and, eq } from "drizzle-orm";
import {
  contentDropEntries,
  contentDropTables,
  contentGlobals,
  contentItems,
  contentKnownSlugs,
  contentRealms,
  contentSkills,
  contentStages,
} from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";

const SLUG = /^[a-z][a-z0-9_]{1,47}$/;
const ITEM_KINDS = new Set(["equipment", "skill_book", "pill", "material"]);
const SLOTS = new Set(["weapon", "helmet", "clothes", "gloves", "shoes", "accessory"]);

function requireSlug(slug: string | undefined, label: string): string {
  if (!slug || !SLUG.test(slug)) {
    throw new AppError("INVALID_INPUT", `${label}编号不正确`);
  }
  return slug;
}

async function assertDeletable(db: Db, kind: string, slug: string) {
  const [known] = await db
    .select()
    .from(contentKnownSlugs)
    .where(and(eq(contentKnownSlugs.kind, kind), eq(contentKnownSlugs.slug, slug)))
    .limit(1);
  if (known) {
    throw new AppError("SLUG_PUBLISHED");
  }
}

export async function saveDraftItem(
  db: Db,
  input: {
    slug?: string;
    displayName?: string;
    kind?: string;
    slot?: string | null;
    skillSlug?: string | null;
    attack?: number;
    defense?: number;
    hp?: number;
    speed?: number;
  },
  adminId: string | null,
) {
  const slug = requireSlug(input.slug, "物品");
  if (!input.displayName || !input.kind || !ITEM_KINDS.has(input.kind)) {
    throw new AppError("INVALID_INPUT", "物品名称或类型不正确");
  }
  if (input.kind === "equipment" && (!input.slot || !SLOTS.has(input.slot))) {
    throw new AppError("INVALID_INPUT", "装备部位不正确");
  }
  if (input.kind === "skill_book") {
    if (!input.skillSlug) {
      throw new AppError("INVALID_INPUT", "功法书必须指向功法", { field: "skillSlug" });
    }
    const [skill] = await db.select().from(contentSkills).where(eq(contentSkills.slug, input.skillSlug)).limit(1);
    if (!skill) {
      throw new AppError("INVALID_INPUT", "功法不存在", { field: "skillSlug" });
    }
  }
  const values = {
    slug,
    displayName: input.displayName,
    kind: input.kind,
    slot: input.kind === "equipment" ? input.slot ?? null : null,
    skillSlug: input.kind === "skill_book" ? input.skillSlug ?? null : null,
    attack: input.attack ?? 0,
    defense: input.defense ?? 0,
    hp: input.hp ?? 0,
    speed: input.speed ?? 0,
    stackable: input.kind !== "equipment",
    updatedAt: new Date(),
    updatedBy: adminId,
  };
  await db.insert(contentItems).values(values).onConflictDoUpdate({ target: contentItems.slug, set: values });
  return { ok: true };
}

export async function deleteDraftItem(db: Db, slug: string) {
  await assertDeletable(db, "item", slug);
  await db.delete(contentItems).where(eq(contentItems.slug, slug));
  return { ok: true };
}

export async function saveDraftSkill(
  db: Db,
  input: { slug?: string; displayName?: string; role?: string; cultivateBonusBp?: number },
  adminId: string | null,
) {
  const slug = requireSlug(input.slug, "功法");
  if (!input.displayName || !input.role || !["heart", "attack", "body", "step"].includes(input.role)) {
    throw new AppError("INVALID_INPUT", "功法名称或类型不正确");
  }
  const values = {
    slug,
    displayName: input.displayName,
    role: input.role,
    cultivateBonusBp: input.cultivateBonusBp ?? 0,
    updatedAt: new Date(),
    updatedBy: adminId,
  };
  await db.insert(contentSkills).values(values).onConflictDoUpdate({ target: contentSkills.slug, set: values });
  return { ok: true };
}

export async function deleteDraftSkill(db: Db, slug: string) {
  await assertDeletable(db, "skill", slug);
  await db.delete(contentSkills).where(eq(contentSkills.slug, slug));
  return { ok: true };
}

export async function saveDraftDropTable(
  db: Db,
  input: {
    slug?: string;
    displayName?: string;
    entries?: { itemSlug?: string; chanceBp?: number; minQty?: number; maxQty?: number }[];
  },
  adminId: string | null,
) {
  const slug = requireSlug(input.slug, "掉落表");
  if (!input.displayName) {
    throw new AppError("INVALID_INPUT", "掉落表名称不能为空");
  }
  const entries = input.entries ?? [];
  for (const entry of entries) {
    if (!entry.itemSlug) {
      throw new AppError("INVALID_INPUT", "掉落物品不能为空", { field: "itemSlug" });
    }
    const [item] = await db.select().from(contentItems).where(eq(contentItems.slug, entry.itemSlug)).limit(1);
    if (!item) {
      throw new AppError("INVALID_INPUT", "掉落物品不存在", { field: "itemSlug" });
    }
    const chance = entry.chanceBp ?? -1;
    const minQty = entry.minQty ?? 0;
    const maxQty = entry.maxQty ?? 0;
    if (chance < 0 || chance > 10000 || minQty < 1 || maxQty < minQty) {
      throw new AppError("INVALID_INPUT", "掉落概率或数量不正确", { field: "chanceBp" });
    }
  }
  await db
    .insert(contentDropTables)
    .values({ slug, displayName: input.displayName, updatedAt: new Date(), updatedBy: adminId })
    .onConflictDoUpdate({
      target: contentDropTables.slug,
      set: { displayName: input.displayName, updatedAt: new Date(), updatedBy: adminId },
    });
  await db.delete(contentDropEntries).where(eq(contentDropEntries.dropTableSlug, slug));
  if (entries.length > 0) {
    await db.insert(contentDropEntries).values(
      entries.map((entry) => ({
        dropTableSlug: slug,
        itemSlug: entry.itemSlug!,
        chanceBp: entry.chanceBp!,
        minQty: entry.minQty!,
        maxQty: entry.maxQty!,
      })),
    );
  }
  return { ok: true };
}

export async function deleteDraftRealm(db: Db, slug: string) {
  await assertDeletable(db, "realm", slug);
  await db.delete(contentRealms).where(eq(contentRealms.slug, slug));
  return { ok: true };
}

export async function readDraftGlobals(db: Db) {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  return row ?? null;
}

export async function saveDraftGlobals(
  _db: Db,
  _input: { offlineCapSeconds?: number; bagCapacity?: number; startingRealmSlug?: string },
  _adminId: string | null,
) {
  throw new AppError("INVALID_INPUT", "请到规则页填写");
}

export async function saveDraftStage(
  db: Db,
  input: {
    slug?: string;
    displayName?: string;
    bossDropTableSlug?: string;
    idleDropTableSlug?: string;
    firstClearDropTableSlug?: string;
    bossHp?: number;
    bossInterval?: number;
  },
  adminId: string | null,
) {
  const slug = requireSlug(input.slug, "关卡");
  if (!input.displayName || !input.bossDropTableSlug || !input.idleDropTableSlug || !input.firstClearDropTableSlug) {
    throw new AppError("INVALID_INPUT", "关卡名称或掉落表不能为空");
  }
  if ((input.bossHp ?? 0) <= 0 || (input.bossInterval ?? 0) <= 0) {
    throw new AppError("INVALID_INPUT", "Boss 气血和出手间隔必须大于 0");
  }
  for (const tableSlug of [input.bossDropTableSlug, input.idleDropTableSlug, input.firstClearDropTableSlug]) {
    const [table] = await db.select().from(contentDropTables).where(eq(contentDropTables.slug, tableSlug)).limit(1);
    if (!table) {
      throw new AppError("INVALID_INPUT", "掉落表不存在", { field: "bossDropTableSlug" });
    }
  }
  const values = {
    slug,
    displayName: input.displayName,
    bossDropTableSlug: input.bossDropTableSlug,
    idleDropTableSlug: input.idleDropTableSlug,
    firstClearDropTableSlug: input.firstClearDropTableSlug,
    bossHp: input.bossHp ?? 1,
    bossInterval: input.bossInterval ?? 1.5,
    updatedAt: new Date(),
    updatedBy: adminId,
  };
  await db.insert(contentStages).values(values).onConflictDoUpdate({ target: contentStages.slug, set: values });
  return { ok: true };
}
