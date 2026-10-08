import { readFile } from "node:fs/promises";
import path from "node:path";
import { getDb, getSql } from "../db/client.js";
import { importContentBodies } from "../modules/content/pack.js";
import { saveItem, saveRealm, saveSkill } from "../modules/content/service.js";

const configDir = process.env.GAME_CONFIG_DIR ?? path.resolve(process.cwd(), "../game/resources/config");

const idle = JSON.parse(await readFile(path.join(configDir, "idle_rules.json"), "utf8")) as {
  offline_cap_seconds: number;
  realms: Array<{
    id: string;
    display_name: string;
    order: number;
    gain_per_second: number;
    breakthrough_cost: number;
    next_id?: string;
  }>;
};
const adventure = JSON.parse(await readFile(path.join(configDir, "adventure.json"), "utf8")) as {
  items: Array<Record<string, unknown>>;
  skills: Array<Record<string, unknown>>;
  realm_bases?: Record<string, { attack?: number; defense?: number; hp?: number }>;
};
const longterm = JSON.parse(await readFile(path.join(configDir, "longterm.json"), "utf8"));

const db = getDb();
await importContentBodies(db, { idle, adventure, longterm });
const bases = adventure.realm_bases ?? {};
for (const realm of idle.realms) {
  const base = bases[realm.id] ?? {};
  await saveRealm(db, "import", {
    slug: realm.id,
    displayName: realm.display_name,
    sortOrder: realm.order,
    gainPerSecond: realm.gain_per_second,
    breakthroughCost: realm.breakthrough_cost,
    nextSlug: realm.next_id ?? null,
    attack: base.attack ?? 0,
    defense: base.defense ?? 0,
    hp: base.hp ?? 0,
    speed: 0,
  });
}
for (const item of adventure.items) {
  await saveItem(db, {
    slug: String(item.id ?? ""),
    displayName: String(item.display_name ?? ""),
    description: String(item.description ?? ""),
    kind: String(item.kind ?? "material"),
    quality: String(item.quality ?? "white"),
    slot: item.slot ? String(item.slot) : null,
    attack: Number(item.attack ?? 0),
    defense: Number(item.defense ?? 0),
    hp: Number(item.hp ?? 0),
    speed: Number(item.speed ?? 0),
  });
}
for (const skill of adventure.skills) {
  await saveSkill(db, {
    slug: String(skill.id ?? ""),
    displayName: String(skill.display_name ?? ""),
    description: String(skill.description ?? ""),
    role: String(skill.role ?? "heart"),
    attack: Number(skill.attack ?? 0),
    defense: Number(skill.defense ?? 0),
    hp: Number(skill.hp ?? 0),
    speed: Number(skill.speed ?? 0),
    cultivateBonus: Number(skill.cultivate_bonus ?? 0),
    minRealmOrder: Number(skill.min_realm_order ?? 0),
  });
}
await getSql().end();
console.log("imported draft content");
