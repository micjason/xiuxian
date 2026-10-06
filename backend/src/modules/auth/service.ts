import { createHash, randomBytes } from "node:crypto";
import argon2 from "argon2";
import { eq } from "drizzle-orm";
import { admins, playerStates, players, sessions } from "../../db/schema.js";
import { writeOperation, type Db } from "../operations/record.js";

const SESSION_MS = 30 * 24 * 60 * 60 * 1000;

function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

async function issueSession(
  db: Db,
  actorType: "player" | "admin",
  actorId: string,
  now: Date,
): Promise<string> {
  const token = randomBytes(32).toString("base64url");
  await db.insert(sessions).values({
    tokenHash: hashToken(token),
    actorType,
    actorId,
    expiresAt: new Date(now.getTime() + SESSION_MS),
  });
  return token;
}

export async function registerPlayer(
  db: Db,
  input: { username: string; password: string; now: Date },
): Promise<{ playerId: string; token: string }> {
  const passwordHash = await argon2.hash(input.password);
  const [player] = await db
    .insert(players)
    .values({ username: input.username, passwordHash })
    .returning({ id: players.id });
  if (!player) {
    throw new Error("player insert failed");
  }
  await db.insert(playerStates).values({
    playerId: player.id,
    cultivation: 0,
    realmSlug: "mortal",
    lastSettledAt: input.now,
  });
  const token = await issueSession(db, "player", player.id, input.now);
  await writeOperation(db, {
    at: input.now,
    actorType: "player",
    actorId: player.id,
    actorName: input.username,
    action: "login",
    result: "success",
    summary: { playerId: player.id },
  });
  return { playerId: player.id, token };
}

export async function loginPlayer(
  db: Db,
  input: { username: string; password: string; now: Date },
): Promise<{ ok: true; playerId: string; token: string } | { ok: false; reason: "unknown" | "bad_password" }> {
  const [player] = await db.select().from(players).where(eq(players.username, input.username)).limit(1);
  if (!player) {
    await writeOperation(db, {
      at: input.now,
      actorType: "player",
      actorId: null,
      actorName: input.username,
      action: "login",
      result: "failure",
      reason: "unknown",
      summary: { username: input.username, reason: "unknown" },
    });
    return { ok: false, reason: "unknown" };
  }
  const matches = await argon2.verify(player.passwordHash, input.password);
  if (!matches) {
    await writeOperation(db, {
      at: input.now,
      actorType: "player",
      actorId: player.id,
      actorName: input.username,
      action: "login",
      result: "failure",
      reason: "bad_password",
      summary: { username: input.username, reason: "bad_password" },
    });
    return { ok: false, reason: "bad_password" };
  }
  const token = await issueSession(db, "player", player.id, input.now);
  await writeOperation(db, {
    at: input.now,
    actorType: "player",
    actorId: player.id,
    actorName: input.username,
    action: "login",
    result: "success",
    summary: { playerId: player.id },
  });
  return { ok: true, playerId: player.id, token };
}

export async function createAdmin(db: Db, input: { username: string; password: string }): Promise<void> {
  const passwordHash = await argon2.hash(input.password);
  await db.insert(admins).values({ username: input.username, passwordHash });
}

export async function loginAdmin(
  db: Db,
  input: { username: string; password: string; now: Date },
): Promise<{ ok: true; adminId: string; token: string } | { ok: false; reason: "unknown" | "bad_password" }> {
  const [admin] = await db.select().from(admins).where(eq(admins.username, input.username)).limit(1);
  if (!admin) {
    await writeOperation(db, {
      at: input.now,
      actorType: "admin",
      actorId: null,
      actorName: input.username,
      action: "login",
      result: "failure",
      reason: "unknown",
      summary: { username: input.username, reason: "unknown" },
    });
    return { ok: false, reason: "unknown" };
  }
  const matches = await argon2.verify(admin.passwordHash, input.password);
  if (!matches) {
    await writeOperation(db, {
      at: input.now,
      actorType: "admin",
      actorId: admin.id,
      actorName: input.username,
      action: "login",
      result: "failure",
      reason: "bad_password",
      summary: { username: input.username, reason: "bad_password" },
    });
    return { ok: false, reason: "bad_password" };
  }
  const token = await issueSession(db, "admin", admin.id, input.now);
  await writeOperation(db, {
    at: input.now,
    actorType: "admin",
    actorId: admin.id,
    actorName: input.username,
    action: "login",
    result: "success",
    summary: { adminId: admin.id },
  });
  return { ok: true, adminId: admin.id, token };
}

export async function readSession(
  db: Db,
  token: string,
  now: Date,
): Promise<{ actorType: "player" | "admin"; actorId: string; actorName: string } | null> {
  const tokenHash = hashToken(token);
  const [session] = await db.select().from(sessions).where(eq(sessions.tokenHash, tokenHash)).limit(1);
  if (!session || session.expiresAt.getTime() <= now.getTime()) {
    return null;
  }
  if (session.actorType === "player") {
    const [player] = await db.select().from(players).where(eq(players.id, session.actorId)).limit(1);
    if (!player) {
      return null;
    }
    return { actorType: "player", actorId: player.id, actorName: player.username };
  }
  const [admin] = await db.select().from(admins).where(eq(admins.id, session.actorId)).limit(1);
  if (!admin) {
    return null;
  }
  return { actorType: "admin", actorId: admin.id, actorName: admin.username };
}
