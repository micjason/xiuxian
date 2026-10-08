import path from "node:path";
import { loadConfig } from "./config.js";
import { getDb } from "./db/client.js";
import { buildApp } from "./app.js";
import { startSessionCleanup } from "./modules/auth/sessions.js";
import { writeCrash } from "./modules/operations/record.js";

const config = loadConfig();

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
await app.listen({ port, host: "0.0.0.0" });

async function shutdown() {
  stopSessionCleanup();
  await app.close();
  const { getSql } = await import("./db/client.js");
  await getSql().end();
  process.exit(0);
}
process.on("SIGTERM", () => void shutdown());
process.on("SIGINT", () => void shutdown());
