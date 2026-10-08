import { and, eq, ne } from "drizzle-orm";
import { contentReleases, items, realms, skills } from "../../db/schema.js";
import { writeOperation, type Db } from "../operations/record.js";
import { copyDocuments, readDocument, stageRecords } from "./pack.js";
import { validatePublish, type PublishDraft } from "./publish-rules.js";

export class PublishRejected extends Error {
  constructor(readonly reasons: string[]) {
    super(reasons.join("；"));
    this.name = "PublishRejected";
  }
}

const DEFAULT_OFFLINE_CAP_SECONDS = 28800;

export type RealmInput = {
  slug: string;
  displayName: string;
  sortOrder: number;
  gainPerSecond: number;
  breakthroughCost: number;
  nextSlug: string | null;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
};

export type SkillInput = {
  slug: string;
  displayName: string;
  description: string;
  role: string;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  cultivateBonus: number;
  minRealmOrder: number;
  prerequisiteSlugs?: string[];
};

export type ItemInput = {
  slug: string;
  displayName: string;
  description: string;
  kind: string;
  quality: string;
  slot: string | null;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  grantable?: boolean;
  skillSlug?: string | null;
};

export type RealmRow = {
  slug: string;
  displayName: string;
  gainPerSecond: number;
  breakthroughCost: number;
  nextSlug: string | null;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  offlineCapSeconds: number;
};

type Actor = { id: string; name: string; actorType?: "player" | "admin" };

export async function ensureDraft(db: Db): Promise<string> {
  const [existing] = await db
    .select()
    .from(contentReleases)
    .where(eq(contentReleases.status, "draft"))
    .limit(1);
  if (existing) {
    return existing.id;
  }
  const [created] = await db
    .insert(contentReleases)
    .values({ status: "draft", offlineCapSeconds: DEFAULT_OFFLINE_CAP_SECONDS })
    .returning({ id: contentReleases.id });
  if (!created) {
    throw new Error("draft insert failed");
  }
  return created.id;
}

export async function saveRealm(db: Db, _adminId: string, input: RealmInput): Promise<void> {
  const releaseId = await ensureDraft(db);
  await db
    .insert(realms)
    .values({ releaseId, ...input })
    .onConflictDoUpdate({
      target: [realms.releaseId, realms.slug],
      set: {
        displayName: input.displayName,
        sortOrder: input.sortOrder,
        gainPerSecond: input.gainPerSecond,
        breakthroughCost: input.breakthroughCost,
        nextSlug: input.nextSlug,
        attack: input.attack,
        defense: input.defense,
        hp: input.hp,
        speed: input.speed,
      },
    });
}

export async function saveSkill(db: Db, input: SkillInput): Promise<void> {
  const releaseId = await ensureDraft(db);
  const row = { ...input, prerequisiteSlugs: input.prerequisiteSlugs ?? [] };
  await db
    .insert(skills)
    .values({ releaseId, ...row })
    .onConflictDoUpdate({
      target: [skills.releaseId, skills.slug],
      set: row,
    });
}

export async function saveItem(db: Db, input: ItemInput): Promise<void> {
  const releaseId = await ensureDraft(db);
  const row = {
    ...input,
    grantable: input.grantable ?? false,
    skillSlug: input.kind === "skill_book" ? input.skillSlug || null : null,
  };
  await db
    .insert(items)
    .values({ releaseId, ...row })
    .onConflictDoUpdate({
      target: [items.releaseId, items.slug],
      set: row,
    });
}

export async function publish(db: Db, admin: Actor, now: Date): Promise<{ releaseId: string }> {
  if (admin.actorType === "player") {
    throw new Error("admin required");
  }
  const draftId = await ensureDraft(db);
  const draftRealms = await db.select().from(realms).where(eq(realms.releaseId, draftId));
  const draftSkills = await db.select().from(skills).where(eq(skills.releaseId, draftId));
  const draftItems = await db.select().from(items).where(eq(items.releaseId, draftId));
  const names = [
    ...draftRealms.map((row) => row.displayName),
    ...draftSkills.map((row) => row.displayName),
    ...draftItems.map((row) => row.displayName),
  ];
  if (names.some((name) => name.trim() === "")) {
    throw new Error("empty name");
  }
  const adventure = await readDocument(db, draftId, "adventure");
  const stages = stageRecords(adventure);
  const reasons = validatePublish(await publishDraft(db, draftRealms, draftSkills, draftItems, stages));
  if (reasons.length > 0) {
    throw new PublishRejected(reasons);
  }
  const [current] = await db
    .select()
    .from(contentReleases)
    .where(eq(contentReleases.status, "published"))
    .limit(1);
  const [draft] = await db.select().from(contentReleases).where(eq(contentReleases.id, draftId)).limit(1);
  if (!draft) {
    throw new Error("draft missing");
  }
  const [created] = await db
    .insert(contentReleases)
    .values({
      status: "published",
      offlineCapSeconds: draft.offlineCapSeconds,
      publishedAt: now,
    })
    .returning({ id: contentReleases.id });
  if (!created) {
    throw new Error("release insert failed");
  }
  if (draftRealms.length > 0) {
    await db.insert(realms).values(
      draftRealms.map((row) => ({
        releaseId: created.id,
        slug: row.slug,
        displayName: row.displayName,
        sortOrder: row.sortOrder,
        gainPerSecond: row.gainPerSecond,
        breakthroughCost: row.breakthroughCost,
        nextSlug: row.nextSlug,
        attack: row.attack,
        defense: row.defense,
        hp: row.hp,
        speed: row.speed,
      })),
    );
  }
  if (draftSkills.length > 0) {
    await db.insert(skills).values(
      draftSkills.map((row) => ({
        releaseId: created.id,
        slug: row.slug,
        displayName: row.displayName,
        description: row.description,
        role: row.role,
        attack: row.attack,
        defense: row.defense,
        hp: row.hp,
        speed: row.speed,
        cultivateBonus: row.cultivateBonus,
        minRealmOrder: row.minRealmOrder,
        prerequisiteSlugs: row.prerequisiteSlugs,
      })),
    );
  }
  if (draftItems.length > 0) {
    await db.insert(items).values(
      draftItems.map((row) => ({
        releaseId: created.id,
        slug: row.slug,
        displayName: row.displayName,
        description: row.description,
        kind: row.kind,
        quality: row.quality,
        slot: row.slot,
        attack: row.attack,
        defense: row.defense,
        hp: row.hp,
        speed: row.speed,
        grantable: row.grantable,
        skillSlug: row.skillSlug,
      })),
    );
  }
  await copyDocuments(db, draftId, created.id);
  if (current) {
    await db
      .update(contentReleases)
      .set({ status: "archived" })
      .where(eq(contentReleases.id, current.id));
  }
  await writeOperation(db, {
    at: now,
    actorType: "admin",
    actorId: admin.id,
    actorName: admin.name,
    action: "publish",
    result: "success",
    contentReleaseId: created.id,
    summary: { previousReleaseId: current?.id ?? null, releaseId: created.id },
  });
  return { releaseId: created.id };
}

export type ContentChange = {
  kind: "realm" | "skill" | "item" | "settings";
  slug: string;
  field: string;
  before: string | number | null;
  after: string | number | null;
};

const realmFields = [
  "displayName",
  "sortOrder",
  "gainPerSecond",
  "breakthroughCost",
  "nextSlug",
  "attack",
  "defense",
  "hp",
  "speed",
] as const;

const skillFields = [
  "displayName",
  "description",
  "role",
  "attack",
  "defense",
  "hp",
  "speed",
  "cultivateBonus",
  "minRealmOrder",
  "prerequisiteSlugs",
] as const;

const itemFields = ["displayName", "description", "kind", "quality", "slot", "attack", "defense", "hp", "speed", "grantable", "skillSlug"] as const;

async function publishDraft(
  db: Db,
  draftRealms: { slug: string; nextSlug: string | null }[],
  draftSkills: { slug: string; prerequisiteSlugs: string[] }[],
  draftItems: { slug: string; kind: string; skillSlug: string | null }[],
  stages: ReturnType<typeof stageRecords>,
): Promise<PublishDraft> {
  const publishedReleases = await db.select().from(contentReleases).where(ne(contentReleases.status, "draft"));
  const publishedIds = publishedReleases.map((row) => row.id);
  const realmSlugs = new Set<string>();
  const skillSlugs = new Set<string>();
  const itemSlugs = new Set<string>();
  const stageSlugs = new Set<string>();
  for (const releaseId of publishedIds) {
    for (const row of await db.select({ slug: realms.slug }).from(realms).where(eq(realms.releaseId, releaseId))) {
      realmSlugs.add(row.slug);
    }
    for (const row of await db.select({ slug: skills.slug }).from(skills).where(eq(skills.releaseId, releaseId))) {
      skillSlugs.add(row.slug);
    }
    for (const row of await db.select({ slug: items.slug }).from(items).where(eq(items.releaseId, releaseId))) {
      itemSlugs.add(row.slug);
    }
    const document = await readDocument(db, releaseId, "adventure");
    for (const stage of stageRecords(document)) {
      stageSlugs.add(stage.slug);
    }
  }
  return {
    realms: draftRealms.map((row) => ({ slug: row.slug, nextSlug: row.nextSlug })),
    skills: draftSkills.map((row) => ({ slug: row.slug, prerequisiteSlugs: row.prerequisiteSlugs ?? [] })),
    items: draftItems.map((row) => ({ slug: row.slug, kind: row.kind, skillSlug: row.skillSlug })),
    stages: stages.map((stage) => ({ slug: stage.slug })),
    drops: stages.flatMap((stage) =>
      stage.drops.map((drop) => ({
        stageSlug: stage.slug,
        itemSlug: drop.itemSlug,
        chance: drop.chance,
        quantity: drop.quantity,
      })),
    ),
    publishedSlugs: {
      realms: [...realmSlugs],
      skills: [...skillSlugs],
      items: [...itemSlugs],
      stages: [...stageSlugs],
    },
  };
}

function pushSettingChange(
  changes: ContentChange[],
  field: string,
  before: unknown,
  after: unknown,
): void {
  if (typeof before === "number" && typeof after === "number" && before !== after) {
    changes.push({ kind: "settings", slug: "global", field, before, after });
  }
}

function displayValue(value: unknown): string | number | null {
  if (Array.isArray(value)) {
    return value.join(",");
  }
  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }
  if (typeof value === "string" || typeof value === "number") {
    return value;
  }
  return value == null ? null : String(value);
}

function rowChanges<T extends { slug: string }>(
  kind: ContentChange["kind"],
  draftRows: T[],
  publishedRows: T[],
  fields: readonly (keyof T & string)[],
): ContentChange[] {
  const published = new Map(publishedRows.map((row) => [row.slug, row]));
  const draft = new Map(draftRows.map((row) => [row.slug, row]));
  const changes: ContentChange[] = [];
  for (const [slug, row] of draft) {
    const previous = published.get(slug);
    if (!previous) {
      changes.push({ kind, slug, field: "slug", before: null, after: slug });
      continue;
    }
    for (const field of fields) {
      const before = displayValue(previous[field]);
      const after = displayValue(row[field]);
      if (before !== after) {
        changes.push({ kind, slug, field, before, after });
      }
    }
  }
  for (const slug of published.keys()) {
    if (!draft.has(slug)) {
      changes.push({ kind, slug, field: "slug", before: slug, after: null });
    }
  }
  return changes;
}

export async function listDraftRealms(db: Db) {
  const releaseId = await ensureDraft(db);
  return db.select().from(realms).where(eq(realms.releaseId, releaseId));
}

export async function listDraftSkills(db: Db) {
  const releaseId = await ensureDraft(db);
  const rows = await db.select().from(skills).where(eq(skills.releaseId, releaseId));
  return rows.map((row) => ({
    ...row,
    prerequisiteSlugs: (row.prerequisiteSlugs ?? []).join(","),
  }));
}

export async function listDraftItems(db: Db) {
  const releaseId = await ensureDraft(db);
  return db.select().from(items).where(eq(items.releaseId, releaseId));
}

export async function diffDraft(db: Db): Promise<{
  publishedAt: Date | null;
  releaseId: string | null;
  offlineCapSeconds: number;
  changes: ContentChange[];
}> {
  const draftId = await ensureDraft(db);
  const [draft] = await db.select().from(contentReleases).where(eq(contentReleases.id, draftId)).limit(1);
  const [published] = await db
    .select()
    .from(contentReleases)
    .where(eq(contentReleases.status, "published"))
    .limit(1);
  const settingChanges: ContentChange[] = [];
  if (draft && published && draft.offlineCapSeconds !== published.offlineCapSeconds) {
    settingChanges.push({
      kind: "settings",
      slug: "global",
      field: "offlineCapSeconds",
      before: published.offlineCapSeconds,
      after: draft.offlineCapSeconds,
    });
  }
  if (draft && published) {
    const draftAdventure = await readDocument(db, draft.id, "adventure");
    const publishedAdventure = await readDocument(db, published.id, "adventure");
    const draftLongterm = await readDocument(db, draft.id, "longterm");
    const publishedLongterm = await readDocument(db, published.id, "longterm");
    pushSettingChange(settingChanges, "inventoryCapacity", publishedAdventure?.inventory_capacity, draftAdventure?.inventory_capacity);
    pushSettingChange(settingChanges, "queueLimit", publishedLongterm?.queue_limit, draftLongterm?.queue_limit);
  }
  const draftRealms = await db.select().from(realms).where(eq(realms.releaseId, draftId));
  const draftSkills = await db.select().from(skills).where(eq(skills.releaseId, draftId));
  const draftItems = await db.select().from(items).where(eq(items.releaseId, draftId));
  const publishedRealms = published
    ? await db.select().from(realms).where(eq(realms.releaseId, published.id))
    : [];
  const publishedSkills = published
    ? await db.select().from(skills).where(eq(skills.releaseId, published.id))
    : [];
  const publishedItems = published
    ? await db.select().from(items).where(eq(items.releaseId, published.id))
    : [];
  return {
    publishedAt: published?.publishedAt ?? null,
    releaseId: published?.id ?? null,
    offlineCapSeconds: draft?.offlineCapSeconds ?? DEFAULT_OFFLINE_CAP_SECONDS,
    changes: [
      ...settingChanges,
      ...rowChanges("realm", draftRealms, publishedRealms, realmFields),
      ...rowChanges("skill", draftSkills, publishedSkills, skillFields),
      ...rowChanges("item", draftItems, publishedItems, itemFields),
    ],
  };
}

export async function getPublishedRealm(db: Db, slug: string): Promise<RealmRow | null> {
  const [row] = await db
    .select({
      slug: realms.slug,
      displayName: realms.displayName,
      gainPerSecond: realms.gainPerSecond,
      breakthroughCost: realms.breakthroughCost,
      nextSlug: realms.nextSlug,
      attack: realms.attack,
      defense: realms.defense,
      hp: realms.hp,
      speed: realms.speed,
      offlineCapSeconds: contentReleases.offlineCapSeconds,
    })
    .from(realms)
    .innerJoin(contentReleases, eq(realms.releaseId, contentReleases.id))
    .where(and(eq(contentReleases.status, "published"), eq(realms.slug, slug)))
    .limit(1);
  return row ?? null;
}
