import path from "node:path";
import { loadConfig } from "./config.js";
import { getDb } from "./db/client.js";
import { buildApp } from "./app.js";
import { writeCrash } from "./modules/operations/record.js";

const config = loadConfig();

const crashLog = path.join(process.cwd(), "var", "crash.log");

process.on("uncaughtException", (error) => {
  writeCrash(error, crashLog);
  process.exit(1);
});

const db = getDb();
const app = await buildApp(db);
const port = config.PORT;
await app.listen({ port, host: "0.0.0.0" });
