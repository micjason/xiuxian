import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema.js";

let sql: ReturnType<typeof postgres> | undefined;

export function getSql() {
  if (!sql) {
    throw new Error("DATABASE_URL is required");
  }
  return sql;
}

export function getDb() {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error("DATABASE_URL is required");
  }
  sql = postgres(url);
  return drizzle(sql, { schema });
}
