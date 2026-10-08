import path from "node:path";
import { loadConfig } from "../config.js";
import { getDb, getSql } from "../db/client.js";
import { importLegacyContent } from "./import-legacy.js";

loadConfig();
const db = getDb();
const root = path.resolve(process.cwd(), "../game/resources/config");
await importLegacyContent(db, path.join(root, "idle_rules.json"), path.join(root, "adventure.json"));
console.log("已把现有境界、物品和功法导入草稿。发布前请先补齐关卡和掉落表。");
await getSql().end();
