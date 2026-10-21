import { STARTING_BREAK_MATERIALS, STARTING_ENHANCE_RULES } from "../modules/content/enhance.js";
import { readFileSync } from "node:fs";
import { eq } from "drizzle-orm";
import {
  contentDropEntries,
  contentDropTables,
  contentGlobals,
  contentItems,
  contentRealms,
  contentSkills,
  contentStages,
} from "../db/schema.js";
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
  stages?: {
    id: string;
    display_name: string;
    order: number;
    min_realm_order?: number;
    min_power?: number;
    next_id?: string;
    monsters?: {
      display_name: string;
      attack: number;
      defense: number;
      hp: number;
      interval: number;
      drops?: { item_id: string; chance: number; count: number }[];
    }[];
  }[];
  loot_chance_scale?: number;
};

const QUALITY_RANK = ["white", "blue", "purple", "gold", "red"];

function chanceBp(chance: number, scale: number): number {
  return Math.max(1, Math.round(chance * scale * 10000));
}

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
  const scale = adventure.loot_chance_scale ?? 1;
  const itemsBySlug = new Map((adventure.items ?? []).map((item) => [item.id, item]));
  await db.delete(contentDropEntries);
  await db.delete(contentStages);
  await db.delete(contentDropTables);
  await db.delete(contentSkills);
  await db.delete(contentItems);
  await db.delete(contentRealms);
  await db.delete(contentGlobals);
  await db.insert(contentGlobals).values({
    id: 1,
    startingRealmSlug: "mortal",
    offlineCapSeconds: idle.offline_cap_seconds,
    enhance: STARTING_ENHANCE_RULES,
  });
  for (const realm of idle.realms) {
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
      baseInterval: base.interval,
      breakthroughCost: realm.breakthrough_cost,
    });
  }
  for (const item of adventure.items ?? []) {
    await db.insert(contentItems).values({
      slug: item.id,
      displayName: item.display_name,
      description: item.description ?? "",
      kind: item.kind,
      quality: item.quality ?? "white",
      slot: item.slot || null,
      attack: item.attack ?? 0,
      defense: item.defense ?? 0,
      hp: item.hp ?? 0,
      speed: item.speed ?? 0,
      skillSlug: item.skill_id || null,
      stackable: item.stackable ?? item.kind !== "equipment",
    });
  }
  for (const material of STARTING_BREAK_MATERIALS) {
    // 强化规则里的起始突破节点要用这三种材料；旧数据里没有，所以一起建好。
    await db.insert(contentItems).values({
      slug: material.slug,
      displayName: material.displayName,
      description: material.description,
      kind: "material",
      quality: material.quality,
      stackable: true,
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
  for (const stage of adventure.stages ?? []) {
    const monsters = stage.monsters ?? [];
    const boss = monsters[monsters.length - 1];
    const idleMonsters = monsters.slice(0, -1);
    const tables = [
      { suffix: "boss", drops: boss?.drops ?? [] },
      {
        suffix: "idle",
        drops: idleMonsters.flatMap((monster) => monster.drops ?? []),
      },
    ];
    for (const table of tables) {
      const slug = `drop_${stage.id}_${table.suffix}`;
      await db.insert(contentDropTables).values({ slug, displayName: `${stage.display_name}${table.suffix === "boss" ? "首领" : "挂机"}` });
      const merged = new Map<string, { chanceBp: number; qty: number }>();
      for (const drop of table.drops) {
        const next = { chanceBp: chanceBp(drop.chance, scale), qty: Math.max(1, drop.count || 1) };
        const current = merged.get(drop.item_id);
        if (!current || next.chanceBp > current.chanceBp) {
          merged.set(drop.item_id, next);
        }
      }
      const entries = [...merged.entries()].filter(([itemSlug]) => itemsBySlug.has(itemSlug));
      if (entries.length > 0) {
        await db.insert(contentDropEntries).values(
          entries.map(([itemSlug, value]) => ({
            dropTableSlug: slug,
            itemSlug,
            chanceBp: value.chanceBp,
            minQty: value.qty,
            maxQty: value.qty,
          })),
        );
      }
    }
    const firstSlug = `drop_${stage.id}_first`;
    await db.insert(contentDropTables).values({ slug: firstSlug, displayName: `${stage.display_name}首通` });
    let bestEquip: { slug: string; rank: number } | null = null;
    let bookSlug: string | null = null;
    for (const drop of boss?.drops ?? []) {
      const item = itemsBySlug.get(drop.item_id);
      if (!item) {
        continue;
      }
      if (item.kind === "skill_book" && !bookSlug) {
        bookSlug = item.id;
      }
      if (item.kind === "equipment") {
        const rank = QUALITY_RANK.indexOf(item.quality ?? "white");
        if (!bestEquip || rank >= bestEquip.rank) {
          bestEquip = { slug: item.id, rank };
        }
      }
    }
    const firstEntries = [
      ...(bestEquip ? [{ itemSlug: bestEquip.slug, chanceBp: 10000, minQty: 1, maxQty: 1 }] : []),
      ...(bookSlug ? [{ itemSlug: bookSlug, chanceBp: 10000, minQty: 1, maxQty: 1 }] : []),
    ];
    if (firstEntries.length > 0) {
      await db.insert(contentDropEntries).values(firstEntries.map((entry) => ({ dropTableSlug: firstSlug, ...entry })));
    }
    if (!boss) {
      continue;
    }
    await db.insert(contentStages).values({
      slug: stage.id,
      displayName: stage.display_name,
      sortOrder: stage.order,
      nextStageSlug: stage.next_id || null,
      requiredRealmOrder: stage.min_realm_order ?? 0,
      recommendedPower: Math.round(stage.min_power ?? 0),
      bossName: boss.display_name,
      bossAttack: boss.attack,
      bossDefense: boss.defense,
      bossHp: boss.hp,
      bossInterval: boss.interval,
      bossDropTableSlug: `drop_${stage.id}_boss`,
      idleDropTableSlug: `drop_${stage.id}_idle`,
      firstClearDropTableSlug: firstSlug,
    });
  }
  await db.select().from(contentRealms).where(eq(contentRealms.slug, "mortal"));
}
