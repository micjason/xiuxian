import type { FastifyInstance } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { loginAdmin, loginPlayer, registerPlayer, revokeSession } from "./service.js";

type AuthBody = { username?: string; password?: string };

const playerAuthLimit = {
  config: { rateLimit: { max: 10, timeWindow: "1 minute" } },
};

const adminAuthLimit = {
  config: { rateLimit: { max: 5, timeWindow: "1 minute" } },
};

function credentials(body: unknown): { username: string; password: string } {
  const value = body as AuthBody;
  if (!value || typeof value.username !== "string" || typeof value.password !== "string") {
    throw new AppError("INVALID_INPUT");
  }
  return { username: value.username, password: value.password };
}

function bearer(header: string | undefined): string {
  if (!header?.startsWith("Bearer ")) {
    throw new AppError("UNAUTHORIZED");
  }
  return header.slice("Bearer ".length);
}

export async function registerAuthRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.post("/auth/register", playerAuthLimit, async (request) => {
    const body = credentials(request.body);
    return registerPlayer(deps.db, { ...body, now: deps.now() });
  });

  app.post("/auth/login", playerAuthLimit, async (request) => {
    const body = credentials(request.body);
    const result = await loginPlayer(deps.db, { ...body, now: deps.now() });
    if (!result.ok) {
      throw new AppError("INVALID_CREDENTIALS");
    }
    return { playerId: result.playerId, token: result.token };
  });

  app.post("/auth/logout", async (request) => {
    await revokeSession(deps.db, bearer(request.headers.authorization), deps.now());
    return { ok: true };
  });

  app.post("/admin/auth/login", adminAuthLimit, async (request) => {
    const body = credentials(request.body);
    const result = await loginAdmin(deps.db, { ...body, now: deps.now() });
    if (!result.ok) {
      throw new AppError("INVALID_CREDENTIALS");
    }
    return { adminId: result.adminId, token: result.token };
  });

  app.post("/admin/auth/logout", async (request) => {
    await revokeSession(deps.db, bearer(request.headers.authorization), deps.now());
    return { ok: true };
  });
}
