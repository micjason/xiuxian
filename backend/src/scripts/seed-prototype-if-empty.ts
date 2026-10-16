// 本地开发用：库里还没有发布过内容时，写入原型 v1.2 内容并发布第 1 版；已经发布过就什么都不做。
// 注意：seed-prototype.ts 会先清空再重写内容，安装脚本绝不能在已有数据的库上调用它。
// 加 SEED_FORCE=1 才会在已有内容的库上重写（只用于明确要重置内容的场合）。
import { loadConfig } from "../config.js";
import { getDb, getSql } from "../db/client.js";
import { contentCurrent } from "../db/schema.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { publishSnapshot } from "../modules/content/snapshot.js";

loadConfig();
const db = getDb();
const [current] = await db.select().from(contentCurrent).limit(1);
if (current && process.env.SEED_FORCE !== "1") {
  console.log(`content already published (version ${current.version}), skip seed`);
} else {
  await applyPrototypeV12(db);
  const published = await publishSnapshot(db, "原型 v1.2 初始内容（本地安装脚本）", null, new Date());
  console.log(`seeded prototype v1.2 and published version ${published.version}`);
}
await getSql().end();
