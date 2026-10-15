// 把原型 v1.2 内容（境界/关卡/装备/功法/强化规则）写进当前 DATABASE_URL 指向的库并发布，本地联调用。
import { loadConfig } from "../config.js";
import { getDb, getSql } from "../db/client.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";

loadConfig();
await applyPrototypeV12(getDb());
console.log("prototype v1.2 content applied");
await getSql().end();
