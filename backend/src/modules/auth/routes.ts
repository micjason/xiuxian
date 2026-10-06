import type { FastifyInstance } from "fastify";
import type { Db } from "../operations/record.js";
import { loginAdmin, loginPlayer, registerPlayer } from "./service.js";

type AuthBody = { username?: string; password?: string };

export async function registerAuthRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.post("/auth/register", async (request, reply) => {
    const body = request.body as AuthBody;
    if (!body.username || !body.password) {
      return reply.code(400).send({ reason: "invalid" });
    }
    return registerPlayer(deps.db, {
      username: body.username,
      password: body.password,
      now: deps.now(),
    });
  });

  app.post("/auth/login", async (request, reply) => {
    const body = request.body as AuthBody;
    if (!body.username || !body.password) {
      return reply.code(400).send({ reason: "invalid" });
    }
    const result = await loginPlayer(deps.db, {
      username: body.username,
      password: body.password,
      now: deps.now(),
    });
    if (!result.ok) {
      return reply.code(401).send(result);
    }
    return result;
  });

  app.post("/admin/auth/login", async (request, reply) => {
    const body = request.body as AuthBody;
    if (!body.username || !body.password) {
      return reply.code(400).send({ reason: "invalid" });
    }
    const result = await loginAdmin(deps.db, {
      username: body.username,
      password: body.password,
      now: deps.now(),
    });
    if (!result.ok) {
      return reply.code(401).send(result);
    }
    return result;
  });
}
