import { migrate } from "drizzle-orm/postgres-js/migrator";
import { getDb, getSql } from "./client.js";

const db = getDb();
await migrate(db, { migrationsFolder: "drizzle" });
await getSql().end();
