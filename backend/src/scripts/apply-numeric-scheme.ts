import { eq } from "drizzle-orm";
import { loadConfig } from "../config.js";
import { getDb, getSql } from "../db/client.js";
import { contentDropEntries, contentDropTables, contentGlobals, contentItems, contentRealms, contentSkills, contentStages } from "../db/schema.js";
import { buildScheme } from "../modules/content/numeric-scheme.js";

const config = loadConfig();
const database = new URL(config.DATABASE_URL).pathname.replace(/^\//, "");
if (database !== "xiuxian_dev") {
  throw new Error("这个脚本只改开发库 xiuxian_dev");
}

const db = getDb();
const [globals] = await db.select().from(contentGlobals).limit(1);
if (!globals?.powerWeights || !globals.combat) {
  throw new Error("请先在后台填写：攻击权重、防御权重、气血权重、速度权重、防御常数 k、推荐战力倍数");
}

const scheme = buildScheme();
await db.delete(contentDropEntries);
await db.delete(contentStages);
await db.delete(contentDropTables);
await db.delete(contentItems);
await db.delete(contentSkills);
await db.delete(contentRealms);

await db.insert(contentRealms).values(scheme.realms);
await db.insert(contentSkills).values(scheme.skills.map((skill) => ({ ...skill, prerequisiteSkillSlugs: [] })));
await db.insert(contentItems).values(scheme.items);
await db.insert(contentDropTables).values(scheme.dropTables);
await db.insert(contentDropEntries).values(scheme.dropEntries);
await db.insert(contentStages).values(scheme.stages);
await db.update(contentGlobals).set({ startingRealmSlug: scheme.startingRealmSlug }).where(eq(contentGlobals.id, globals.id));

console.log(
  `已写入开发库草稿：${scheme.realms.length} 个境界，${scheme.items.length} 件物品，${scheme.skills.length} 门功法，${scheme.stages.length} 个关卡。没有发布。`,
);
await getSql().end();
