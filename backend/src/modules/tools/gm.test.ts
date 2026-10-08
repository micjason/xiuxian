import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { buildApp } from "../../app.js";
import { withDb } from "../../test/db.js";

describe("gm routes", () => {
  it("is not registered when GM tools are off", async () => {
    await withDb(async (db) => {
      const previous = process.env.ENABLE_GM_TOOLS;
      process.env.ENABLE_GM_TOOLS = "false";
      const app = await buildApp(db);
      const missing = await app.inject({ method: "POST", url: "/admin/gm/players/1/reset" });
      expect(missing.statusCode).toBe(404);
      await app.close();
      process.env.ENABLE_GM_TOOLS = previous;
    });
  });

  it("is registered when GM tools are on", async () => {
    await withDb(async (db) => {
      const previous = process.env.ENABLE_GM_TOOLS;
      process.env.ENABLE_GM_TOOLS = "true";
      const app = Fastify();
      const { registerGmRoutes } = await import("./gm.js");
      await registerGmRoutes(app, { db, now: () => new Date() });
      const found = await app.inject({ method: "POST", url: "/admin/gm/players/1/reset" });
      expect(found.statusCode).toBe(200);
      await app.close();
      process.env.ENABLE_GM_TOOLS = previous;
    });
  });
});
