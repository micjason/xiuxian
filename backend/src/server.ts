import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { loadConfig } from "./config.js";
import { getDb } from "./db/client.js";
import { buildApp } from "./app.js";
import { startSessionCleanup } from "./modules/auth/sessions.js";
import { writeCrash } from "./modules/operations/record.js";

const config = loadConfig();

// 线上发布目录里有 RELEASE 文件（部署脚本写入的版本号），/healthz 会带上它，部署后可以确认跑的是新版本。
const releaseFile = path.join(process.cwd(), "RELEASE");
if (!process.env.APP_RELEASE && existsSync(releaseFile)) {
  process.env.APP_RELEASE = readFileSync(releaseFile, "utf8").trim();
}

const crashLog = path.join(process.cwd(), "var", "crash.log");

process.on("uncaughtException", (error) => {
  writeCrash(error, crashLog);
  process.exit(1);
});

process.on("unhandledRejection", (error) => {
  writeCrash(error instanceof Error ? error : new Error(String(error)), crashLog);
  process.exit(1);
});

const db = getDb();
const stopSessionCleanup = startSessionCleanup(db);
const app = await buildApp(db);
const port = config.PORT;
await app.listen({ port, host: config.HOST });

async function shutdown() {
  stopSessionCleanup();
  await app.close();
  const { getSql } = await import("./db/client.js");
  await getSql().end();
  process.exit(0);
}
process.on("SIGTERM", () => void shutdown());
process.on("SIGINT", () => void shutdown());
