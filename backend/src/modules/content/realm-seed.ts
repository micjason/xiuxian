import { eq } from "drizzle-orm";
import { contentGlobals, contentRealms } from "../../db/schema.js";
import type { Db } from "../operations/record.js";
import { REALM_FACTORY } from "./realm-factory.js";

async function globalBaseInterval(db: Db): Promise<number> {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  const value = Number(row?.combat?.baseInterval);
  return Number.isFinite(value) && value > 0 ? value : 1.5;
}

/**
 * 缺的固定境界补上出厂数字。已有的行不改数字、不改下一境。
 * 编号被别的境界占用时跳过，列表仍显示这一行，但保存会说明写不进去。
 */
export async function ensureFactoryRealms(db: Db, now: Date, adminId: string | null): Promise<void> {
  const rows = await db.select().from(contentRealms);
  const bySlug = new Set(rows.map((row) => row.slug));
  const occupied = new Set(rows.map((row) => row.sortOrder));
  const baseInterval = await globalBaseInterval(db);
  for (let index = 0; index < REALM_FACTORY.length; index += 1) {
    const seed = REALM_FACTORY[index]!;
    if (bySlug.has(seed.slug) || occupied.has(seed.code)) continue;
    await db.insert(contentRealms).values({
      slug: seed.slug,
      displayName: seed.displayName,
      majorName: seed.majorName,
      majorKey: seed.majorKey,
      sortOrder: seed.code,
      nextRealmSlug: REALM_FACTORY[index + 1]?.slug ?? null,
      tickSeconds: 1,
      gainPerTick: seed.gainPerTick,
      breakthroughCost: seed.breakthroughCost,
      baseAttack: seed.attack,
      baseDefense: seed.defense,
      baseHp: seed.hp,
      baseSpeed: seed.speed,
      baseInterval,
      ultName: "",
      ultDamageMultBp: 0,
      ultCooldownSeconds: 0,
      ultFirstCooldownSeconds: 0,
      requiredStageSlug: seed.requiredStageId || null,
      updatedAt: now,
      updatedBy: adminId,
    });
    bySlug.add(seed.slug);
    occupied.add(seed.code);
  }
}
