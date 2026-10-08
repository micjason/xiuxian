import path from "node:path";
import { getDb } from "./db/client.js";
import { buildApp } from "./app.js";
import { writeCrash } from "./modules/operations/record.js";

const crashLog = path.join(process.cwd(), "var", "crash.log");

process.on("uncaughtException", (error) => {
  writeCrash(error, crashLog);
  process.exit(1);
});

const db = getDb();
const app = await buildApp(db);
const port = Number(process.env.PORT ?? 8080);
await app.listen({ port, host: "0.0.0.0" });
