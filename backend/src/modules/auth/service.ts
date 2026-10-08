import { createHash, randomBytes } from "node:crypto";
import argon2 from "argon2";
import { eq } from "drizzle-orm";
import { withTransaction } from "../../db/tx.js";
import { admins, playerStates, players, sessions } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import { writeOperation, type Db } from "../operations/record.js";
import { initializeProgress } from "../loop/actions.js";
import { parseCredentials } from "./credentials.js";

const PLAYER_SESSION_MS = 30 * 24 * 60 * 60 * 1000;
const ADMIN_SESSION_MS = 12 * 60 * 60 * 1000;
const SEEN_INTERVAL_MS = 60 * 60 * 1000;
const ADMIN_ROLES = ["owner", "designer", "viewer"] as const;

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
  const ttl = actorType === "admin" ? ADMIN_SESSION_MS : PLAYER_SESSION_MS;
  await db.insert(sessions).values({
    tokenHash: hashToken(token),
    actorType,
    actorId,
    expiresAt: new Date(now.getTime() + ttl),
    lastSeenAt: now,
  });
  return token;
}

function isUniqueViolation(error: unknown): boolean {
  if (!error || typeof error !== "object") {
    return false;
  }
  if ("code" in error && error.code === "23505") {
    return true;
  }
  return "cause" in error && isUniqueViolation(error.cause);
}

export async function registerPlayer(
  db: Db,
  input: { username: string; password: string; now: Date },
): Promise<{ playerId: string; token: string }> {
  const credentials = parseCredentials(input.username, input.password);
  const passwordHash = await argon2.hash(input.password);
  try {
    return await withTransaction(db, async (tx) => {
      const [player] = await tx
        .insert(players)
        .values({
          username: credentials.username,
          usernameLower: credentials.usernameLower,
          passwordHash,
          lastLoginAt: input.now,
        })
        .returning({ id: players.id });
      if (!player) {
        throw new Error("player insert failed");
      }
      await tx.insert(playerStates).values({
        playerId: player.id,
        cultivation: 0,
        realmSlug: "mortal",
        lastSettledAt: input.now,
      });
      await initializeProgress(tx, player.id, input.now);
      const token = await issueSession(tx, "player", player.id, input.now);
      await writeOperation(tx, {
        at: input.now,
        actorType: "player",
        actorId: player.id,
        actorName: credentials.username,
        action: "login",
        result: "success",
        summary: { playerId: player.id },
      });
      return { playerId: player.id, token };
    });
  } catch (error) {
    if (isUniqueViolation(error)) {
      throw new AppError("USERNAME_TAKEN");
    }
    throw error;
  }
}

export async function loginPlayer(
  db: Db,
  input: { username: string; password: string; now: Date },
): Promise<{ ok: true; playerId: string; token: string } | { ok: false; reason: "unknown" | "bad_password" }> {
  const usernameLower = input.username.trim().toLowerCase();
  const [player] = await db.select().from(players).where(eq(players.usernameLower, usernameLower)).limit(1);
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
    actorName: player.username,
    action: "login",
    result: "success",
    summary: { playerId: player.id },
  });
  await db.update(players).set({ lastLoginAt: input.now }).where(eq(players.id, player.id));
  return { ok: true, playerId: player.id, token };
}

export async function createAdmin(
  db: Db,
  input: { username: string; password: string; role?: string },
): Promise<void> {
  const credentials = parseCredentials(input.username, input.password);
  const role = input.role ?? "owner";
  if (!ADMIN_ROLES.includes(role as (typeof ADMIN_ROLES)[number])) {
    throw new AppError("INVALID_INPUT", "管理员角色不正确");
  }
  const passwordHash = await argon2.hash(input.password);
  await db.insert(admins).values({ username: credentials.username, passwordHash, role });
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
): Promise<{ actorType: "player" | "admin"; actorId: string; actorName: string; role?: string } | null> {
  const tokenHash = hashToken(token);
  const [session] = await db.select().from(sessions).where(eq(sessions.tokenHash, tokenHash)).limit(1);
  if (!session || session.revokedAt || session.expiresAt.getTime() <= now.getTime()) {
    return null;
  }
  if (!session.lastSeenAt || now.getTime() - session.lastSeenAt.getTime() >= SEEN_INTERVAL_MS) {
    await db.update(sessions).set({ lastSeenAt: now }).where(eq(sessions.id, session.id));
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
  return { actorType: "admin", actorId: admin.id, actorName: admin.username, role: admin.role };
}

export async function revokeSession(db: Db, token: string, now: Date): Promise<void> {
  await db
    .update(sessions)
    .set({ revokedAt: now })
    .where(eq(sessions.tokenHash, hashToken(token)));
}
