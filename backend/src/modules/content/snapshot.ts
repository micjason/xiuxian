import { createHash } from "node:crypto";
import { eq } from "drizzle-orm";
import {
  contentChapters,
  contentCurrent,
  contentDropEntries,
  contentDropTables,
  contentGearSets,
  contentGlobals,
  contentItems,
  contentKnownSlugs,
  contentRealms,
  contentSkills,
  contentStages,
  contentVersions,
} from "../../db/schema.js";
import { withTransaction, type Tx } from "../../db/tx.js";
import type { Db } from "../operations/record.js";
import { AppError } from "../../shared/errors.js";
import { validateContent, type ContentSnapshot } from "./validate.js";
import { resolveMonsterDrop } from "./stage-defaults.js";
import { tuningOf } from "./tuning.js";
import { QUALITY_TABLE, SLOT_KEYS, SLOT_TABLE } from "./catalog.js";
import { skillSlotRulesOf } from "./skill-slots.js";
import { expandBossStats, resolveBossRules } from "./boss-rules.js";
import { chiefStageOf } from "./stage-order.js";

export async function loadDraftSnapshot(db: Db | Tx): Promise<ContentSnapshot> {
  const [globals] = await db.select().from(contentGlobals).limit(1);
  const realms = await db.select().from(contentRealms);
  const items = await db.select().from(contentItems);
  const skills = await db.select().from(contentSkills);
  const tables = await db.select().from(contentDropTables);
  const entries = await db.select().from(contentDropEntries);
  const stages = await db.select().from(contentStages);
  const sets = await db.select().from(contentGearSets);
  const chapterRows = await db.select().from(contentChapters);
  const tuning = tuningOf(globals?.tuning);
  const chapters = [...chapterRows]
    .sort((left, right) => left.sortOrder - right.sortOrder || left.slug.localeCompare(right.slug))
    .map((row) => {
      const chapter = { slug: row.slug, displayName: row.displayName, sortOrder: row.sortOrder, bgKey: row.bgKey, bossFx: row.bossFx, chiefStageSlugSetting: row.chiefStageSlug ?? null, enabled: row.enabled };
      return { ...chapter, chiefStageSlug: chiefStageOf(chapter, stages) };
    });
  const chapterBySlug = new Map(chapters.map((row) => [row.slug, row]));
  return {
    globals: {
      startingRealmSlug: globals?.startingRealmSlug ?? "",
      starterItems: (globals?.starterItems as { itemSlug: string; quantity: number }[] | undefined) ?? [],
      offlineCapSeconds: globals?.offlineCapSeconds ?? undefined,
      bagCapacity: globals?.bagCapacity ?? undefined,
      powerWeights: globals?.powerWeights ?? undefined,
      combat: globals?.combat ?? undefined,
      enhance: globals?.enhance ?? undefined,
      tuning,
      artSlotRules: skillSlotRulesOf(globals?.artSlotRules),
      slots: SLOT_TABLE,
      qualities: QUALITY_TABLE,
    },
    realms: [...realms]
      .sort((left, right) => left.sortOrder - right.sortOrder)
      .map((row, index, ordered) => ({
      slug: row.slug,
      displayName: row.displayName,
      sortOrder: row.sortOrder,
      nextRealmSlug: ordered[index + 1]?.slug ?? null,
      tickSeconds: row.tickSeconds,
      gainPerTick: row.gainPerTick,
      breakthroughCost: row.breakthroughCost,
      requiredStageSlug: row.requiredStageSlug,
      recommendedPower: row.recommendedPower,
      baseAttack: row.baseAttack,
      baseDefense: row.baseDefense,
      baseHp: row.baseHp,
      baseSpeed: row.baseSpeed,
      baseInterval: row.baseInterval ?? undefined,
      majorKey: row.majorKey ?? undefined,
      majorName: row.majorName || undefined,
      ultName: row.ultName,
      ultDamageMultBp: row.ultDamageMultBp,
      ultCooldownSeconds: row.ultCooldownSeconds,
      ultFirstCooldownSeconds: row.ultFirstCooldownSeconds,
      enabled: row.enabled,
    })),
    stages: stages.map((row) => {
      const chapter = row.chapterSlug ? chapterBySlug.get(row.chapterSlug) : undefined;
      // 没有章节（老数据）的关卡单独算一章：首领按章末规则（和第三批之前一样，发布校验会报「没有所属章节」）。
      const tier = chapter && chapter.chiefStageSlug !== row.slug ? ("elite" as const) : ("chief" as const);
      const monster = row.monsters?.[0];
      const bosses = (row.bosses ?? []).map((boss) => {
        const rules = resolveBossRules(tuning.bossRules[tier], boss.rules ?? null);
        const stats = expandBossStats(boss, monster, rules);
        const { rules: ruleOverride, ...rest } = boss;
        return {
          ...rest,
          ...(stats ?? {}),
          // 精英没单独选立绘 = 用本关普通怪的立绘（客户端按 tier 加金边、放大）
          artKey: boss.artKey || (tier === "elite" ? monster?.artKey : undefined) || undefined,
          tier,
          rules,
          ruleOverride: ruleOverride ?? null,
          statsAuto: rules.statMode === "auto",
          ...(stats ? {} : { statsProblem: `首领「${boss.name}」设成按普通怪自动算属性，但本关没有普通怪` }),
        };
      });
      return {
      slug: row.slug,
      chapterSlug: row.chapterSlug ?? null,
      tier,
      displayName: row.displayName,
      sortOrder: row.sortOrder,
      nextStageSlug: row.nextStageSlug,
      requiredRealmOrder: row.requiredRealmOrder,
      bossDropTableSlug: row.bossDropTableSlug,
      idleDropTableSlug: row.idleDropTableSlug,
      firstClearDropTableSlug: row.firstClearDropTableSlug,
      bossName: row.bossName,
      bossAttack: row.bossAttack,
      bossDefense: row.bossDefense,
      bossHp: row.bossHp,
      bossInterval: row.bossInterval,
      bosses,
      monsters: row.monsters ?? [],
      // 关卡里只存改过的项；这里合并配置概览的默认值，游戏和客户端拿到的永远是完整的掉落配置。
      monsterDrop: resolveMonsterDrop(row.monsterDrop, tuning),
      designatedDrops: row.designatedDrops ?? [],
      // 0 = 没手动覆盖，按公式自动算（库里存 null）
      recommendedPower: row.recommendedPower ?? 0,
      enabled: row.enabled,
      };
    }),
    chapters,
    dropTables: tables.map((table) => ({
      slug: table.slug,
      entries: entries
        .filter((entry) => entry.dropTableSlug === table.slug)
        .map((entry) => ({
          itemSlug: entry.itemSlug,
          chanceBp: entry.chanceBp,
          minQty: entry.minQty,
          maxQty: entry.maxQty,
        })),
    })),
    items: items.map((row) => ({
      slug: row.slug,
      displayName: row.displayName,
      description: row.description,
      kind: row.kind,
      slot: row.slot,
      skillSlug: row.skillSlug,
      attack: row.attack,
      defense: row.defense,
      hp: row.hp,
      speed: row.speed,
      quality: row.quality,
      requiredRealmOrder: row.requiredRealmOrder,
      stackable: row.stackable,
      iconKey: row.iconKey ?? "",
      dropMult: row.dropMult ?? 1,
      origin: row.origin === "manual" ? ("manual" as const) : ("formula" as const),
      setSlug: row.setSlug ?? null,
      randomDrop: row.randomDrop,
      enabled: row.enabled,
    })),
    gearSets: [...sets]
      .sort((left, right) => left.slug.localeCompare(right.slug))
      .map((set) => ({
        slug: set.slug,
        displayName: set.displayName,
        description: set.description,
        tiers: [...(set.tiers ?? [])].sort((left, right) => left.pieces - right.pieces),
        members: items
          .filter((item) => item.setSlug === set.slug)
          .sort((left, right) => SLOT_KEYS.indexOf(left.slot as never) - SLOT_KEYS.indexOf(right.slot as never))
          .map((item) => item.slug),
      })),
    skills: skills.map((row) => ({
      slug: row.slug,
      displayName: row.displayName,
      role: row.role,
      attack: row.attack,
      defense: row.defense,
      hp: row.hp,
      speed: row.speed,
      cultivateBonusBp: row.cultivateBonusBp,
      rank: row.rank,
      requiredRealmOrder: row.requiredRealmOrder,
      prerequisiteSkillSlugs: row.prerequisiteSkillSlugs ?? [],
      enabled: row.enabled,
    })),
  };
}

export async function loadCurrentWorld(db: Db | Tx): Promise<(ContentSnapshot & { version: number }) | null> {
  const draft = await loadDraftSnapshot(db);
  if (draft.realms.length === 0) {
    return null;
  }
  return { ...draft, version: 0 };
}

export async function publishSnapshot(db: Db, note: string, adminId: string | null, now: Date) {
  if (!note.trim()) {
    throw new AppError("INVALID_INPUT", "发布说明不能为空");
  }
  return withTransaction(db, async (tx) => {
    const draft = await loadDraftSnapshot(tx);
    const knownRows = await tx.select().from(contentKnownSlugs);
    const known = { realms: [] as string[], stages: [] as string[], items: [] as string[], skills: [] as string[], dropTables: [] as string[] };
    for (const row of knownRows) {
      if (row.kind === "realm") known.realms.push(row.slug);
      if (row.kind === "stage") known.stages.push(row.slug);
      if (row.kind === "item") known.items.push(row.slug);
      if (row.kind === "skill") known.skills.push(row.slug);
      if (row.kind === "dropTable") known.dropTables.push(row.slug);
    }
    const checked = validateContent(draft, known);
    if (checked.errors.length > 0) {
      throw new AppError("PUBLISH_REJECTED", "发布校验未通过", { errors: checked.errors });
    }
    const [current] = await tx.select().from(contentCurrent).where(eq(contentCurrent.id, 1)).limit(1);
    const snapshot = { ...draft, version: (current?.version ?? 0) + 1 };
    const checksum = createHash("sha256").update(JSON.stringify(snapshot)).digest("hex");
    const [created] = await tx
      .insert(contentVersions)
      .values({ snapshot, checksum, note, publishedBy: adminId, publishedAt: now, sourceVersion: current?.version ?? null })
      .returning({ version: contentVersions.version });
    if (!created) {
      throw new AppError("INTERNAL");
    }
    if (current) {
      await tx.update(contentCurrent).set({ version: created.version }).where(eq(contentCurrent.id, 1));
    } else {
      await tx.insert(contentCurrent).values({ id: 1, version: created.version });
    }
    const slugs: { kind: string; slug: string }[] = [
      ...draft.realms.map((row) => ({ kind: "realm", slug: row.slug })),
      ...draft.stages.map((row) => ({ kind: "stage", slug: row.slug })),
      ...draft.items.map((row) => ({ kind: "item", slug: row.slug })),
      ...draft.skills.map((row) => ({ kind: "skill", slug: row.slug })),
      ...draft.dropTables.map((row) => ({ kind: "dropTable", slug: row.slug })),
    ];
    if (slugs.length > 0) {
      await tx.insert(contentKnownSlugs).values(slugs).onConflictDoNothing();
    }
    return { version: created.version, checksum };
  });
}
