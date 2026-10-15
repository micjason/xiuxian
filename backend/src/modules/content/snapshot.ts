import { createHash } from "node:crypto";
import { eq } from "drizzle-orm";
import {
  contentCurrent,
  contentDropEntries,
  contentDropTables,
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

export async function loadDraftSnapshot(db: Db | Tx): Promise<ContentSnapshot> {
  const [globals] = await db.select().from(contentGlobals).limit(1);
  const realms = await db.select().from(contentRealms);
  const items = await db.select().from(contentItems);
  const skills = await db.select().from(contentSkills);
  const tables = await db.select().from(contentDropTables);
  const entries = await db.select().from(contentDropEntries);
  const stages = await db.select().from(contentStages);
  return {
    globals: {
      startingRealmSlug: globals?.startingRealmSlug ?? "",
      starterItems: (globals?.starterItems as { itemSlug: string; quantity: number }[] | undefined) ?? [],
      offlineCapSeconds: globals?.offlineCapSeconds ?? undefined,
      bagCapacity: globals?.bagCapacity ?? undefined,
      powerWeights: globals?.powerWeights ?? undefined,
      combat: globals?.combat ?? undefined,
      enhance: globals?.enhance ?? undefined,
      artSlotRules: globals?.artSlotRules ?? undefined,
      idleKillCap: globals?.idleKillCap ?? undefined,
      minClientVersionCode: globals?.minClientVersionCode ?? undefined,
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
      minRateBp: row.minRateBp,
      baseRateBp: row.baseRateBp,
      maxRateBp: row.maxRateBp,
      failLossBp: row.failLossBp,
      pityStepBp: row.pityStepBp,
      powerFactorBp: row.powerFactorBp,
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
    stages: stages.map((row) => ({
      slug: row.slug,
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
      bosses: row.bosses ?? [],
      monsters: row.monsters ?? [],
      monsterDrop: row.monsterDrop ?? null,
      recommendedPower: row.recommendedPower,
      enabled: row.enabled,
    })),
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
      enabled: row.enabled,
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
