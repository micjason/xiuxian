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
  // DB_POOL_MAX：连接池上限（默认 10）。和别的服务共用一个 Postgres（max_connections 小）时调低。
  const max = Number(process.env.DB_POOL_MAX ?? "10");
  sql = postgres(url, { max: Number.isFinite(max) && max > 0 ? max : 10 });
  return drizzle(sql, { schema });
}
