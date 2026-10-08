import rateLimit from "@fastify/rate-limit";
import multipart from "@fastify/multipart";
import { sql } from "drizzle-orm";
import Fastify, { type FastifyInstance } from "fastify";
import { authPlugin } from "./plugins/auth.js";
import { AppError } from "./shared/errors.js";
import { registerAuthRoutes } from "./modules/auth/routes.js";
import { registerContentRoutes } from "./modules/content/routes.js";
import { registerDraftRoutes } from "./modules/content/draft-routes.js";
import { registerNoticeRoutes } from "./modules/notices/routes.js";
import { registerOperationRoutes } from "./modules/operations/routes.js";
import type { Db } from "./modules/operations/record.js";
import { registerPlayerRoutes } from "./modules/player/routes.js";
import { registerReleaseRoutes } from "./modules/releases/routes.js";
import { registerRepairRoutes } from "./modules/repairs/routes.js";
import { registerGmRoutes } from "./modules/tools/gm.js";

export async function buildApp(db: Db, now: () => Date = () => new Date()): Promise<FastifyInstance> {
  const app = Fastify();
  app.setErrorHandler((error: unknown, _request, reply) => {
    if (error instanceof AppError) {
      return reply.code(error.status).send(error.body());
    }
    const statusCode =
      error && typeof error === "object" && "statusCode" in error && typeof error.statusCode === "number"
        ? error.statusCode
        : 500;
    const message = error instanceof Error ? error.message : "请求参数不正确";
    if (statusCode === 400) {
      return reply.code(400).send(new AppError("INVALID_INPUT", message).body());
    }
    if (statusCode === 429) {
      return reply.code(429).send(new AppError("RATE_LIMITED").body());
    }
    app.log.error(error);
    return reply.code(500).send(new AppError("INTERNAL").body());
  });
  app.get("/healthz", async () => {
    await db.execute(sql`select 1`);
    return { ok: true, version: process.env.npm_package_version ?? "dev", contentVersion: null };
  });
  await app.register(rateLimit, {
    global: false,
    errorResponseBuilder: () => new AppError("RATE_LIMITED"),
  });
  await app.register(multipart, { limits: { fileSize: 200 * 1024 * 1024 } });
  const deps = { db, now };
  await authPlugin(db, now)(app);
  await registerAuthRoutes(app, deps);
  await registerPlayerRoutes(app, deps);
  await registerContentRoutes(app, deps);
  await registerDraftRoutes(app, deps);
  await registerNoticeRoutes(app, deps);
  await registerOperationRoutes(app, deps);
  await registerRepairRoutes(app, deps);
  await registerReleaseRoutes(app, deps);
  if (process.env.ENABLE_GM_TOOLS === "true") {
    await registerGmRoutes(app, deps);
  }
  await app.register(async (scope) => {
    await authPlugin(db, now)(scope);
    await registerAuthRoutes(scope, deps);
    await registerPlayerRoutes(scope, deps);
    await registerContentRoutes(scope, deps);
    await registerDraftRoutes(scope, deps);
    await registerNoticeRoutes(scope, deps);
    await registerOperationRoutes(scope, deps);
    await registerRepairRoutes(scope, deps);
    await registerReleaseRoutes(scope, deps);
  }, { prefix: "/api/v1" });
  app.addHook("onSend", async (request, reply) => {
    if (!request.url.startsWith("/api/v1")) {
      reply.header("deprecation", "true");
    }
  });
  return app;
}
