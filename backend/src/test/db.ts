import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "../db/schema.js";
import type { Db } from "../modules/operations/record.js";

export async function withCleanDb(fn: (db: Db) => Promise<void>): Promise<void> {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error("DATABASE_URL is required");
  }
  const sql = postgres(url, { max: 10 });
  const db = drizzle(sql, { schema });
  await sql.unsafe(`DO $$ DECLARE r RECORD; BEGIN
    FOR r IN (
      SELECT tablename FROM pg_tables
      WHERE schemaname = 'public' AND tablename <> '__drizzle_migrations'
    ) LOOP
      EXECUTE 'TRUNCATE TABLE ' || quote_ident(r.tablename) || ' RESTART IDENTITY CASCADE';
    END LOOP;
  END $$;`);
  try {
    await fn(db);
  } finally {
    await sql.end();
  }
}

export const withDb = withCleanDb;
