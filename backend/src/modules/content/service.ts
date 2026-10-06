import { and, eq } from "drizzle-orm";
import { contentReleases, items, realms, skills } from "../../db/schema.js";
import { writeOperation, type Db } from "../operations/record.js";

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
  await db
    .insert(skills)
    .values({ releaseId, ...input })
    .onConflictDoUpdate({
      target: [skills.releaseId, skills.slug],
      set: { ...input },
    });
}

export async function saveItem(db: Db, input: ItemInput): Promise<void> {
  const releaseId = await ensureDraft(db);
  await db
    .insert(items)
    .values({ releaseId, ...input })
    .onConflictDoUpdate({
      target: [items.releaseId, items.slug],
      set: { ...input },
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
      })),
    );
  }
  if (current) {
    await db
      .update(contentReleases)
      .set({ status: "archived" })
      .where(eq(contentReleases.id, current.id));
  }
  await writeOperation(db, {
    at: now,
    actorType: "admin",
    actorId: admin.id === "unused" ? null : admin.id,
    actorName: admin.name,
    action: "publish",
    result: "success",
    contentReleaseId: created.id,
    summary: { previousReleaseId: current?.id ?? null, releaseId: created.id },
  });
  return { releaseId: created.id };
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
