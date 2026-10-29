/**
 * 洞府 v1 后台草稿：读写 content_globals.dongfu。
 * 保存时严格校验；配方 effect 同步到产出物品的 content_items.effect（使用丹药读物品 effect）。
 */
import { eq, inArray } from "drizzle-orm";
import { contentGlobals, contentItems } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import {
  DEFAULT_DONGFU,
  dongfuConfigFromInput,
  dongfuReferencedItemSlugs,
  type DongfuConfig,
} from "./config.js";

export async function readDongfuView(db: Db) {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  const config = row?.dongfu ?? null;
  return { config, starting: DEFAULT_DONGFU };
}

export async function saveDongfuConfig(db: Db, input: unknown, adminId: string | null) {
  const [current] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  if (!current) {
    throw new AppError("INVALID_INPUT", "请先新建境界");
  }
  const config = dongfuConfigFromInput(input);
  const needed = dongfuReferencedItemSlugs(config);
  if (needed.length > 0) {
    const items = await db
      .select({ slug: contentItems.slug, kind: contentItems.kind, enabled: contentItems.enabled, stackable: contentItems.stackable })
      .from(contentItems)
      .where(inArray(contentItems.slug, needed));
    const bySlug = new Map(items.map((item) => [item.slug, item]));
    const missing = needed.filter((slug) => !bySlug.has(slug));
    if (missing.length > 0) {
      throw new AppError("INVALID_INPUT", `物品不存在：${missing.join("、")}（请先在「物品」页创建）`);
    }
    for (const recipe of config.recipes) {
      const out = bySlug.get(recipe.outputItemSlug);
      if (out && out.kind !== "pill" && out.kind !== "material") {
        throw new AppError("INVALID_INPUT", `配方产出 ${recipe.outputItemSlug} 必须是丹药或材料`);
      }
    }
    const wood = bySlug.get(config.woodItemSlug);
    if (wood && (!wood.stackable || (wood.kind !== "material" && wood.kind !== "pill"))) {
      throw new AppError("INVALID_INPUT", `灵木 ${config.woodItemSlug} 必须是可堆叠材料`);
    }
  }

  await db
    .update(contentGlobals)
    .set({ dongfu: config, updatedAt: new Date(), updatedBy: adminId })
    .where(eq(contentGlobals.id, 1));

  // 有 effect 的配方：把效果写回产出物品，保证 useItem 读到同一份。
  for (const recipe of config.recipes) {
    if (!recipe.effect) continue;
    await db
      .update(contentItems)
      .set({ effect: recipe.effect, updatedAt: new Date(), updatedBy: adminId })
      .where(eq(contentItems.slug, recipe.outputItemSlug));
  }

  return readDongfuView(db);
}

export type { DongfuConfig };
