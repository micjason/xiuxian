import { spawn } from "node:child_process";
import { Writable } from "node:stream";
import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { contentCurrent } from "./db/schema.js";
import { withDb } from "./test/db.js";
import { buildApp, logRedact } from "./app.js";

describe("request logging", () => {
  it("returns a request id and the published content version", async () => {
    await withDb(async (db) => {
      await db.insert(contentCurrent).values({ id: 1, version: 4 });
      const app = await buildApp(db);
      const health = await app.inject({ method: "GET", url: "/healthz" });
      expect(health.headers["x-request-id"]).toEqual(expect.any(String));
      expect(health.json()).toMatchObject({ ok: true, contentVersion: 4 });
      await app.close();
    });
  });

  it("redacts passwords, tokens, and authorization headers", async () => {
    const lines: string[] = [];
    const stream = new Writable({
      write(chunk, _encoding, callback) {
        lines.push(chunk.toString());
        callback();
      },
    });
    const app = Fastify({ logger: { level: "info", stream, redact: logRedact } });
    app.post("/echo", async (request) => {
      request.log.info(
        {
          req: { headers: { authorization: request.headers.authorization } },
          body: { password: "secret-pass", token: "sekret-token" },
        },
        "seen",
      );
      return { ok: true };
    });
    await app.inject({
      method: "POST",
      url: "/echo",
      headers: { authorization: "Bearer real-token" },
      payload: { password: "secret-pass" },
    });
    await app.close();
    const text = lines.join("");
    expect(text).not.toContain("secret-pass");
    expect(text).not.toContain("sekret-token");
    expect(text).not.toContain("real-token");
    expect(text).toContain("[Redacted]");
  });
});

describe("shutdown", () => {
  it("exits within five seconds after SIGTERM", async () => {
    const port = "18099";
    const child = spawn(process.execPath, ["--import", "tsx", "src/server.ts"], {
      cwd: process.cwd(),
      env: {
        ...process.env,
        NODE_ENV: "development",
        PORT: port,
        DATABASE_URL: "postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian_test",
        PUBLIC_BASE_URL: `http://127.0.0.1:${port}`,
        CORS_ORIGINS: "http://127.0.0.1:5173",
        ENABLE_GM_TOOLS: "false",
        LOG_LEVEL: "silent",
        APK_BASE_URL: `http://127.0.0.1:${port}`,
      },
      stdio: "ignore",
    });
    const started = Date.now();
    let up = false;
    while (Date.now() - started < 8000) {
      try {
        const response = await fetch(`http://127.0.0.1:${port}/healthz`);
        if (response.ok) {
          up = true;
          break;
        }
      } catch {
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
    }
    expect(up).toBe(true);
    const exited = new Promise<number>((resolve) => {
      child.once("exit", (code) => resolve(code ?? 1));
    });
    child.kill("SIGTERM");
    const code = await Promise.race([
      exited,
      new Promise<number>((resolve) => setTimeout(() => resolve(-1), 5000)),
    ]);
    if (code === -1) {
      child.kill("SIGKILL");
    }
    expect(code).toBe(0);
  }, 20_000);
});
