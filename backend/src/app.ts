import multipart from "@fastify/multipart";
import Fastify, { type FastifyInstance } from "fastify";
import { registerAuthRoutes } from "./modules/auth/routes.js";
import { registerContentRoutes } from "./modules/content/routes.js";
import { registerNoticeRoutes } from "./modules/notices/routes.js";
import { registerOperationRoutes } from "./modules/operations/routes.js";
import type { Db } from "./modules/operations/record.js";
import { registerPlayerRoutes } from "./modules/player/routes.js";
import { registerReleaseRoutes } from "./modules/releases/routes.js";
import { registerRepairRoutes } from "./modules/repairs/routes.js";

export async function buildApp(db: Db, now: () => Date = () => new Date()): Promise<FastifyInstance> {
  const app = Fastify();
  await app.register(multipart, { limits: { fileSize: 200 * 1024 * 1024 } });
  const deps = { db, now };
  await registerAuthRoutes(app, deps);
  await registerPlayerRoutes(app, deps);
  await registerContentRoutes(app, deps);
  await registerNoticeRoutes(app, deps);
  await registerOperationRoutes(app, deps);
  await registerRepairRoutes(app, deps);
  await registerReleaseRoutes(app, deps);
  return app;
}
