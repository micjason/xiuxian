import { appendFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { and, asc, eq, gte, lte } from "drizzle-orm";
import type { PostgresJsDatabase } from "drizzle-orm/postgres-js";
import * as schema from "../../db/schema.js";
import { operationRecords } from "../../db/schema.js";

export type Db = PostgresJsDatabase<typeof schema>;

const SECRET_KEYS = new Set(["password", "token", "passwordHash"]);

export function stripSecrets(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(stripSecrets);
  }
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
      if (SECRET_KEYS.has(key)) {
        continue;
      }
      out[key] = stripSecrets(nested);
    }
    return out;
  }
  return value;
}

export type OperationAction = "login" | "settle" | "breakthrough" | "publish" | "repair";

export type OperationInput = {
  at: Date;
  actorType: "player" | "admin";
  actorId: string | null;
  actorName: string;
  action: OperationAction;
  result: "success" | "failure";
  reason?: string;
  contentReleaseId?: string;
  summary: Record<string, unknown>;
};

export async function writeOperation(tx: Db, input: OperationInput): Promise<void> {
  await tx.insert(operationRecords).values({
    at: input.at,
    actorType: input.actorType,
    actorId: input.actorId,
    actorName: input.actorName,
    action: input.action,
    result: input.result,
    reason: input.reason,
    contentReleaseId: input.contentReleaseId,
    summary: stripSecrets(input.summary) as Record<string, unknown>,
  });
}

export async function listOperations(
  db: Db,
  query: { name?: string; action?: OperationAction; from: Date; to: Date },
) {
  const filters = [gte(operationRecords.at, query.from), lte(operationRecords.at, query.to)];
  if (query.name) {
    filters.push(eq(operationRecords.actorName, query.name));
  }
  if (query.action) {
    filters.push(eq(operationRecords.action, query.action));
  }
  return db
    .select()
    .from(operationRecords)
    .where(and(...filters))
    .orderBy(asc(operationRecords.at));
}

export function writeCrash(error: unknown, filePath: string): void {
  mkdirSync(path.dirname(filePath), { recursive: true });
  appendFileSync(filePath, `${JSON.stringify(stripSecrets(error))}\n`);
}
