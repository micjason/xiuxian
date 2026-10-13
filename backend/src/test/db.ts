import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "../db/schema.js";
import { contentGlobals, contentRealms } from "../db/schema.js";
import type { Db } from "../modules/operations/record.js";

export async function insertStartingRealm(db: Db) {
  await db.insert(contentRealms).values({
    slug: "mortal",
    displayName: "凡人",
    sortOrder: 1,
    nextRealmSlug: null,
    tickSeconds: 1,
    gainPerTick: 1,
    baseInterval: 1.5,
  });
  await db.insert(contentGlobals).values({
    id: 1,
    startingRealmSlug: "mortal",
    offlineCapSeconds: 36000,
    bagCapacity: 20,
    powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
    combat: {
      minInterval: 0.5,
      challengeCooldownSeconds: 0,
      timeLimitSeconds: 20,
      defenseConstant: 1,
      speedBase: 100,
      recommendedPowerMargin: 1.05,
    },
  });
}

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
