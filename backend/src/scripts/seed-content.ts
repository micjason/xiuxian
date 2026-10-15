import { eq } from "drizzle-orm";
import { loadConfig } from "../config.js";
import { getDb, getSql } from "../db/client.js";
import { contentRealms } from "../db/schema.js";

loadConfig();
const db = getDb();
const [existing] = await db.select().from(contentRealms).where(eq(contentRealms.sortOrder, 1)).limit(1);
if (!existing) {
  await db.insert(contentRealms).values({
    slug: "1",
    displayName: "凡人",
    sortOrder: 1,
    nextRealmSlug: null,
    tickSeconds: 1,
    gainPerTick: 0,
    breakthroughCost: 0,
  });
}
console.log("初始境界只有「凡人」。修炼秒数和获得修为都是 0，后台发布前玩家得不到修为。");
await getSql().end();
