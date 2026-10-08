import { eq } from "drizzle-orm";
import { admins } from "../db/schema.js";
import { createAdmin } from "../modules/auth/service.js";
import type { Db } from "../modules/operations/record.js";

export async function testAdmin(db: Db, username = "publisher"): Promise<{ id: string; name: string }> {
  const [existing] = await db.select().from(admins).where(eq(admins.username, username)).limit(1);
  if (existing) {
    return { id: existing.id, name: existing.username };
  }
  await createAdmin(db, { username, password: "admin-secret" });
  const [created] = await db.select().from(admins).where(eq(admins.username, username)).limit(1);
  if (!created) {
    throw new Error("admin insert failed");
  }
  return { id: created.id, name: created.username };
}
