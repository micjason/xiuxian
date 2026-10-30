import { and, eq } from "drizzle-orm";
import { contentDocuments, contentReleases, realms } from "../../db/schema.js";
import type { Db } from "../operations/record.js";
import { assertDropChance } from "./drops.js";
import { ensureDraft } from "./service.js";

export type JsonRecord = Record<string, unknown>;

const ADVENTURE = "adventure";
const LONGTERM = "longterm";

export async function readDocument(db: Db, releaseId: string, kind: string): Promise<JsonRecord | null> {
  const [row] = await db
    .select()
    .from(contentDocuments)
    .where(and(eq(contentDocuments.releaseId, releaseId), eq(contentDocuments.kind, kind)))
    .limit(1);
  return (row?.body as JsonRecord | undefined) ?? null;
}

export async function writeDocument(db: Db, releaseId: string, kind: string, body: JsonRecord): Promise<void> {
  await db
    .insert(contentDocuments)
    .values({ releaseId, kind, body })
    .onConflictDoUpdate({
      target: [contentDocuments.releaseId, contentDocuments.kind],
      set: { body },
    });
}

export async function copyDocuments(db: Db, fromReleaseId: string, toReleaseId: string): Promise<void> {
  const rows = await db.select().from(contentDocuments).where(eq(contentDocuments.releaseId, fromReleaseId));
  if (rows.length === 0) {
    return;
  }
  await db.insert(contentDocuments).values(
    rows.map((row) => ({
      releaseId: toReleaseId,
      kind: row.kind,
      body: row.body,
    })),
  );
}

async function draftAdventure(db: Db): Promise<{ releaseId: string; body: JsonRecord }> {
  const releaseId = await ensureDraft(db);
  const body = (await readDocument(db, releaseId, ADVENTURE)) ?? {
    schema_version: 1,
    inventory_capacity: 100,
    respawn_seconds: 0.8,
    loot_chance_scale: 0.2,
    realm_bases: {},
    items: [],
    skills: [],
    stages: [],
  };
  return { releaseId, body };
}

async function draftLongterm(db: Db): Promise<{ releaseId: string; body: JsonRecord }> {
  const releaseId = await ensureDraft(db);
  const body = (await readDocument(db, releaseId, LONGTERM)) ?? {
    schema_version: 1,
    queue_limit: 4,
    resources: {},
    cave_rates: {},
  };
  return { releaseId, body };
}

export async function readDraftSettings(db: Db) {
  const releaseId = await ensureDraft(db);
  const [release] = await db.select().from(contentReleases).where(eq(contentReleases.id, releaseId)).limit(1);
  const adventure = await readDocument(db, releaseId, ADVENTURE);
  const longterm = await readDocument(db, releaseId, LONGTERM);
  return {
    offlineCapSeconds: release?.offlineCapSeconds ?? 28800,
    inventoryCapacity: numberOf(adventure?.inventory_capacity, 100),
    queueLimit: numberOf(longterm?.queue_limit, 4),
  };
}

export async function updateDraftSettings(
  db: Db,
  input: { offlineCapSeconds?: number; inventoryCapacity?: number; queueLimit?: number },
): Promise<void> {
  const releaseId = await ensureDraft(db);
  if (input.offlineCapSeconds !== undefined) {
    if (input.offlineCapSeconds <= 0) {
      throw new Error("offline cap must be positive");
    }
    await db
      .update(contentReleases)
      .set({ offlineCapSeconds: input.offlineCapSeconds })
      .where(eq(contentReleases.id, releaseId));
  }
  if (input.inventoryCapacity !== undefined) {
    const { body } = await draftAdventure(db);
    body.inventory_capacity = input.inventoryCapacity;
    await writeDocument(db, releaseId, ADVENTURE, body);
  }
  if (input.queueLimit !== undefined) {
    const { body } = await draftLongterm(db);
    body.queue_limit = input.queueLimit;
    await writeDocument(db, releaseId, LONGTERM, body);
  }
}

export async function listStages(db: Db) {
  const { body } = await draftAdventure(db);
  return arrayOf(body.stages).map(stageSummary);
}

export async function saveStage(
  db: Db,
  id: string,
  input: { displayName: string; bossName: string; attack: number; defense: number; hp: number; interval: number },
): Promise<void> {
  const { releaseId, body } = await draftAdventure(db);
  const stages = arrayOf(body.stages);
  const index = stages.findIndex((stage) => stage.id === id);
  const current = index >= 0 ? stages[index] : { id, drops: [] };
  const next = {
    ...current,
    id,
    display_name: input.displayName,
    boss_name: input.bossName,
    attack: input.attack,
    defense: input.defense,
    hp: input.hp,
    interval: input.interval,
    drops: arrayOf(current?.drops),
  };
  if (index >= 0) {
    stages[index] = next;
  } else {
    stages.push(next);
  }
  body.stages = stages;
  await writeDocument(db, releaseId, ADVENTURE, body);
}

export async function saveDrop(
  db: Db,
  stageId: string,
  input: { itemSlug: string; chance: number; quantity: number },
): Promise<void> {
  assertDropChance(input.chance, input.quantity);
  const { releaseId, body } = await draftAdventure(db);
  const stages = arrayOf(body.stages);
  const index = stages.findIndex((stage) => stage.id === stageId);
  if (index < 0) {
    throw new Error("掉落的关卡不在草稿里");
  }
  const stage = stages[index] ?? { id: stageId };
  const drops = arrayOf(stage.drops);
  const dropIndex = drops.findIndex((drop) => drop.item_slug === input.itemSlug);
  const nextDrop = { item_slug: input.itemSlug, chance: input.chance, quantity: input.quantity };
  if (dropIndex >= 0) {
    drops[dropIndex] = nextDrop;
  } else {
    drops.push(nextDrop);
  }
  stages[index] = { ...stage, drops };
  body.stages = stages;
  await writeDocument(db, releaseId, ADVENTURE, body);
}


export async function importContentBodies(
  db: Db,
  input: { idle: JsonRecord; adventure: JsonRecord; longterm: JsonRecord },
): Promise<void> {
  const releaseId = await ensureDraft(db);
  const cap = numberOf(input.idle.offline_cap_seconds, 28800);
  await db.update(contentReleases).set({ offlineCapSeconds: cap }).where(eq(contentReleases.id, releaseId));
  await writeDocument(db, releaseId, ADVENTURE, input.adventure);
  await writeDocument(db, releaseId, LONGTERM, input.longterm);
}

export async function buildPublishedContent(db: Db) {
  const [published] = await db
    .select()
    .from(contentReleases)
    .where(eq(contentReleases.status, "published"))
    .limit(1);
  if (!published) {
    return null;
  }
  const realmRows = await db.select().from(realms).where(eq(realms.releaseId, published.id));
  const adventure = (await readDocument(db, published.id, ADVENTURE)) ?? {};
  const longterm = (await readDocument(db, published.id, LONGTERM)) ?? {};
  const bases = recordOf(adventure.realm_bases);
  for (const realm of realmRows) {
    const previous = recordOf(bases[realm.slug]);
    bases[realm.slug] = {
      ...previous,
      attack: realm.attack,
      defense: realm.defense,
      hp: realm.hp,
    };
  }
  adventure.realm_bases = bases;
  const idleRealms = [...realmRows]
    .sort((left, right) => left.sortOrder - right.sortOrder)
    .map((realm) => ({
      id: realm.slug,
      display_name: realm.displayName,
      order: realm.sortOrder,
      gain_per_second: realm.gainPerSecond,
      breakthrough_cost: realm.breakthroughCost,
      next_id: realm.nextSlug ?? "",
    }));
  return {
    offlineCapSeconds: published.offlineCapSeconds,
    idle: {
      schema_version: 1,
      offline_cap_seconds: published.offlineCapSeconds,
      realms: idleRealms,
    },
    adventure,
    longterm,
  };
}

function numberOf(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function arrayOf(value: unknown): JsonRecord[] {
  return Array.isArray(value) ? value.filter((item): item is JsonRecord => !!item && typeof item === "object") : [];
}

function recordOf(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as JsonRecord) : {};
}

export function stageRecords(body: JsonRecord | null) {
  return arrayOf(body?.stages).map((stage) => {
    const monster = arrayOf(stage.monsters)[0] ?? {};
    return {
      slug: String(stage.id ?? ""),
      displayName: String(stage.display_name ?? ""),
      bossName: String(stage.boss_name ?? monster.display_name ?? ""),
      attack: numberOf(stage.attack, numberOf(monster.attack, 0)),
      defense: numberOf(stage.defense, numberOf(monster.defense, 0)),
      hp: numberOf(stage.hp, numberOf(monster.hp, 0)),
      interval: numberOf(stage.interval, numberOf(monster.interval, 1)),
      drops: arrayOf(stage.drops).map((drop) => ({
        itemSlug: String(drop.item_slug ?? ""),
        chance: numberOf(drop.chance, 0),
        quantity: numberOf(drop.quantity, 1),
      })),
    };
  });
}

function stageSummary(stage: JsonRecord) {
  const [record] = stageRecords({ stages: [stage] });
  return record ?? { slug: "", displayName: "", bossName: "", attack: 0, defense: 0, hp: 0, interval: 1, drops: [] };
}

