import { and, eq } from "drizzle-orm";
import { playerStates, repairApplications, repairPreviews } from "../../db/schema.js";
import { writeOperation, type Db } from "../operations/record.js";

type RepairPlan = (
  db: Db,
  player: { id: string; cultivation: number },
) => Promise<{ cultivation: number } | null>;

type PreviewEntry = {
  playerId: string;
  before: number;
  after: number;
  status: "pending" | "already";
};

const repairs = new Map<string, RepairPlan>();

export function registerRepair(repair: { name: string; plan: RepairPlan }): void {
  repairs.set(repair.name, repair.plan);
}

export async function previewRepair(db: Db, name: string) {
  const plan = repairs.get(name);
  if (!plan) {
    throw new Error("unknown repair");
  }
  const states = await db.select().from(playerStates);
  const entries: PreviewEntry[] = [];
  for (const state of states) {
    const [existing] = await db
      .select()
      .from(repairApplications)
      .where(and(eq(repairApplications.repairName, name), eq(repairApplications.playerId, state.playerId)))
      .limit(1);
    if (existing) {
      entries.push({
        playerId: state.playerId,
        before: state.cultivation,
        after: state.cultivation,
        status: "already",
      });
      continue;
    }
    const planned = await plan(db, { id: state.playerId, cultivation: state.cultivation });
    if (!planned) {
      continue;
    }
    entries.push({
      playerId: state.playerId,
      before: state.cultivation,
      after: planned.cultivation,
      status: "pending",
    });
  }
  const stateToken = entries.map((entry) => `${entry.playerId}:${entry.before}`).join("|");
  const [created] = await db
    .insert(repairPreviews)
    .values({ repairName: name, entries, stateToken })
    .returning({ id: repairPreviews.id });
  if (!created) {
    throw new Error("preview insert failed");
  }
  return { previewId: created.id, entries };
}

export async function applyRepair(
  db: Db,
  admin: { id: string; name: string },
  previewId: string,
  now: Date,
): Promise<{ applied: number }> {
  const [preview] = await db.select().from(repairPreviews).where(eq(repairPreviews.id, previewId)).limit(1);
  if (!preview) {
    throw new Error("preview missing");
  }
  const entries = preview.entries as PreviewEntry[];
  const pending: PreviewEntry[] = [];
  for (const entry of entries) {
    if (entry.status !== "pending") {
      continue;
    }
    const [existing] = await db
      .select()
      .from(repairApplications)
      .where(
        and(eq(repairApplications.repairName, preview.repairName), eq(repairApplications.playerId, entry.playerId)),
      )
      .limit(1);
    if (existing) {
      continue;
    }
    pending.push(entry);
  }
  for (const entry of pending) {
    const [state] = await db
      .select()
      .from(playerStates)
      .where(eq(playerStates.playerId, entry.playerId))
      .for("update")
      .limit(1);
    if (!state || state.cultivation !== entry.before) {
      throw new Error("stale preview");
    }
  }
  for (const entry of pending) {
    await db
      .update(playerStates)
      .set({ cultivation: entry.after })
      .where(eq(playerStates.playerId, entry.playerId));
    await db.insert(repairApplications).values({
      repairName: preview.repairName,
      playerId: entry.playerId,
      previewId,
      appliedAt: now,
    });
  }
  await writeOperation(db, {
    at: now,
    actorType: "admin",
    actorId: admin.id === "unused" ? null : admin.id,
    actorName: admin.name,
    action: "repair",
    result: "success",
    summary: { repairName: preview.repairName, applied: pending.length },
  });
  return { applied: pending.length };
}
