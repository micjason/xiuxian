import Fastify, { type FastifyInstance } from "fastify";
import { registerAuthRoutes } from "./modules/auth/routes.js";
import { registerContentRoutes } from "./modules/content/routes.js";
import { registerOperationRoutes } from "./modules/operations/routes.js";
import type { Db } from "./modules/operations/record.js";
import { registerPlayerRoutes } from "./modules/player/routes.js";
import { registerRepairRoutes } from "./modules/repairs/routes.js";

export async function buildApp(db: Db, now: () => Date = () => new Date()): Promise<FastifyInstance> {
  const app = Fastify();
  const deps = { db, now };
  await registerAuthRoutes(app, deps);
  await registerPlayerRoutes(app, deps);
  await registerContentRoutes(app, deps);
  await registerOperationRoutes(app, deps);
  await registerRepairRoutes(app, deps);
  return app;
}
