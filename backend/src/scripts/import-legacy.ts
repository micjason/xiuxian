import { readFileSync } from "node:fs";
import { eq } from "drizzle-orm";
import { contentGlobals, contentItems, contentRealms, contentSkills } from "../db/schema.js";
import type { Db } from "../modules/operations/record.js";

type IdleRealm = {
  id: string;
  display_name: string;
  order: number;
  gain_per_second: number;
  breakthrough_cost: number;
  next_id: string;
};

type Adventure = {
  realm_bases?: Record<string, { attack?: number; defense?: number; hp?: number; interval?: number }>;
  items?: {
    id: string;
    display_name: string;
    description?: string;
    kind: string;
    quality?: string;
    slot?: string;
    attack?: number;
    defense?: number;
    hp?: number;
    speed?: number;
    skill_id?: string;
    stackable?: boolean;
  }[];
  skills?: {
    id: string;
    display_name: string;
    description?: string;
    role: string;
    rank?: string;
    attack?: number;
    defense?: number;
    hp?: number;
    speed?: number;
    cultivate_bonus?: number;
    min_realm_order?: number;
  }[];
};

function majorOf(slug: string): string {
  if (slug.startsWith("mortal")) return "凡人";
  if (slug.startsWith("qi_")) return "炼气";
  if (slug.startsWith("foundation")) return "筑基";
  if (slug.startsWith("gold")) return "金丹";
  if (slug.startsWith("nascent")) return "元婴";
  if (slug.startsWith("spirit")) return "化神";
  if (slug.startsWith("void")) return "炼虚";
  return "";
}

export async function importLegacyContent(db: Db, idlePath: string, adventurePath: string): Promise<void> {
  const idle = JSON.parse(readFileSync(idlePath, "utf8")) as { offline_cap_seconds?: number; realms: IdleRealm[] };
  const adventure = JSON.parse(readFileSync(adventurePath, "utf8")) as Adventure;
  const byOrder = new Map(idle.realms.map((realm) => [realm.order, realm]));
  await db.delete(contentSkills);
  await db.delete(contentItems);
  await db.delete(contentRealms);
  await db.delete(contentGlobals);
  await db.insert(contentGlobals).values({
    id: 1,
    startingRealmSlug: "mortal",
    offlineCapSeconds: idle.offline_cap_seconds ?? 28800,
  });
  for (const realm of idle.realms) {
    const next = realm.next_id ? byOrder.get(realm.order + 1) : undefined;
    const cross = next ? majorOf(realm.id) !== majorOf(next.id) : false;
    const base = adventure.realm_bases?.[realm.id] ?? {};
    await db.insert(contentRealms).values({
      slug: realm.id,
      displayName: realm.display_name,
      majorName: majorOf(realm.id),
      sortOrder: realm.order,
      nextRealmSlug: realm.next_id || null,
      tickSeconds: 1,
      gainPerTick: Math.round(realm.gain_per_second),
      baseAttack: base.attack ?? 0,
      baseDefense: base.defense ?? 0,
      baseHp: base.hp ?? 0,
      baseSpeed: 0,
      baseInterval: base.interval ?? 1.5,
      breakthroughCost: realm.breakthrough_cost,
      baseRateBp: realm.id === "mortal" ? 10000 : cross ? 6000 : 9000,
      minRateBp: 2000,
      maxRateBp: 10000,
    });
  }
  for (const item of adventure.items ?? []) {
    await db.insert(contentItems).values({
      slug: item.id,
      displayName: item.display_name,
      description: item.description ?? "",
      kind: item.kind,
      quality: item.quality ?? "white",
      slot: item.slot ?? null,
      attack: item.attack ?? 0,
      defense: item.defense ?? 0,
      hp: item.hp ?? 0,
      speed: item.speed ?? 0,
      skillSlug: item.skill_id ?? null,
      stackable: item.stackable ?? item.kind !== "equipment",
    });
  }
  for (const skill of adventure.skills ?? []) {
    await db.insert(contentSkills).values({
      slug: skill.id,
      displayName: skill.display_name,
      description: skill.description ?? "",
      role: skill.role,
      rank: skill.rank ?? "yellow",
      attack: skill.attack ?? 0,
      defense: skill.defense ?? 0,
      hp: skill.hp ?? 0,
      speed: skill.speed ?? 0,
      cultivateBonusBp: Math.round((skill.cultivate_bonus ?? 0) * 10000),
      requiredRealmOrder: skill.min_realm_order ?? 0,
    });
  }
  await db.select().from(contentRealms).where(eq(contentRealms.slug, "mortal"));
}
