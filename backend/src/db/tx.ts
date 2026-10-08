import type { Db } from "../modules/operations/record.js";

export type Tx = Parameters<Parameters<Db["transaction"]>[0]>[0];

export async function withTransaction<T>(db: Db, fn: (tx: Tx) => Promise<T>): Promise<T> {
  return db.transaction(async (tx) => fn(tx));
}
