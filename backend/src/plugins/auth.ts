import type { FastifyReply, FastifyRequest } from "fastify";
import { readSession } from "../modules/auth/service.js";
import type { Db } from "../modules/operations/record.js";
import { AppError } from "../shared/errors.js";

export type Actor = { actorType: "player" | "admin"; actorId: string; actorName: string; role?: string };

declare module "fastify" {
  interface FastifyRequest {
    actor: Actor | null;
  }
  interface FastifyInstance {
    requirePlayer: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
    requireAdmin: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

export function authPlugin(db: Db, now: () => Date) {
  return async function registerAuth(app: import("fastify").FastifyInstance) {
    app.decorateRequest("actor", null);
    app.decorate("requirePlayer", async (request: FastifyRequest, _reply: FastifyReply) => {
      const actor = await actorFrom(db, request, now());
      if (!actor || actor.actorType !== "player") {
        throw new AppError(actor ? "FORBIDDEN" : "UNAUTHORIZED");
      }
      request.actor = actor;
    });
    app.decorate("requireAdmin", async (request: FastifyRequest, _reply: FastifyReply) => {
      const actor = await actorFrom(db, request, now());
      if (!actor || actor.actorType !== "admin") {
        throw new AppError(actor ? "FORBIDDEN" : "UNAUTHORIZED");
      }
      request.actor = actor;
    });
    app.addHook("preHandler", async function (request, reply) {
      const path = request.url.split("?")[0] ?? "";
      if (path.endsWith("/auth/login") || path.endsWith("/auth/register") || path.endsWith("/auth/logout")) {
        return;
      }
      if (path.includes("/admin")) {
        await this.requireAdmin(request, reply);
      } else if (path === "/me" || path.startsWith("/me/")) {
        await this.requirePlayer(request, reply);
      }
    });
  };
}

async function actorFrom(db: Db, request: FastifyRequest, now: Date): Promise<Actor | null> {
  const header = request.headers.authorization ?? "";
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
  if (!token) {
    return null;
  }
  return readSession(db, token, now);
}
