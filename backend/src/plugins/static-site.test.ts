import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { registerStaticSite, resolveInside } from "./static-site.js";

function fixture() {
  const root = mkdtempSync(path.join(tmpdir(), "static-site-"));
  const admin = path.join(root, "admin");
  const download = path.join(root, "download");
  mkdirSync(path.join(admin, "assets"), { recursive: true });
  mkdirSync(download, { recursive: true });
  writeFileSync(path.join(admin, "index.html"), "<!doctype html><title>后台</title>");
  writeFileSync(path.join(admin, "assets", "app-abc.js"), "console.log(1)");
  writeFileSync(path.join(download, "latest.json"), JSON.stringify({ versionCode: 31 }));
  writeFileSync(path.join(download, "xiuxian-0.11.0-31.apk"), Buffer.from("PK-apk"));
  writeFileSync(path.join(root, "secret.txt"), "nope");
  return { root, admin, download };
}

async function appWith(env: NodeJS.ProcessEnv) {
  const app = Fastify();
  app.get("/api/v1/ping", async () => ({ ok: true }));
  await registerStaticSite(app, env);
  return app;
}

describe("static site (admin + /download)", () => {
  it("serves latest.json uncached and the apk with its content type", async () => {
    const f = fixture();
    const app = await appWith({ STATIC_ADMIN_DIR: f.admin, STATIC_DOWNLOAD_DIR: f.download });
    const json = await app.inject({ url: "/download/latest.json" });
    expect(json.statusCode).toBe(200);
    expect(json.headers["cache-control"]).toContain("no-store");
    expect(json.json()).toEqual({ versionCode: 31 });
    const apk = await app.inject({ url: "/download/xiuxian-0.11.0-31.apk" });
    expect(apk.statusCode).toBe(200);
    expect(apk.headers["content-type"]).toBe("application/vnd.android.package-archive");
    expect(apk.body).toBe("PK-apk");
    const head = await app.inject({ method: "HEAD", url: "/download/xiuxian-0.11.0-31.apk" });
    expect(head.statusCode).toBe(200);
    expect(head.headers["content-length"]).toBe("6");
    expect((await app.inject({ url: "/download/missing.apk" })).statusCode).toBe(404);
  });

  it("serves the admin SPA with index.html fallback, but never for API paths", async () => {
    const f = fixture();
    const app = await appWith({ STATIC_ADMIN_DIR: f.admin, STATIC_DOWNLOAD_DIR: f.download });
    const root = await app.inject({ url: "/" });
    expect(root.statusCode).toBe(200);
    expect(root.body).toContain("后台");
    expect((await app.inject({ url: "/config/items" })).body).toContain("后台");
    const asset = await app.inject({ url: "/assets/app-abc.js" });
    expect(asset.headers["content-type"]).toContain("javascript");
    expect(asset.headers["cache-control"]).toContain("immutable");
    expect((await app.inject({ url: "/assets/missing.js" })).statusCode).toBe(404);
    expect((await app.inject({ url: "/api/v1/nothing" })).statusCode).toBe(404);
    expect((await app.inject({ url: "/admin/nothing" })).statusCode).toBe(404);
    expect((await app.inject({ method: "POST", url: "/dashboard" })).statusCode).toBe(404);
    expect((await app.inject({ url: "/api/v1/ping" })).json()).toEqual({ ok: true });
  });

  it("refuses path traversal and dotfiles", async () => {
    const f = fixture();
    const app = await appWith({ STATIC_DOWNLOAD_DIR: f.download, STATIC_ADMIN_DIR: f.admin });
    for (const url of ["/download/../secret.txt", "/download/%2e%2e/secret.txt", "/download/..%2fsecret.txt", "/download/.hidden"]) {
      const res = await app.inject({ url });
      expect(res.body).not.toContain("nope");
      expect(res.statusCode).toBe(404);
    }
    expect(resolveInside(f.download, "/../secret.txt")).toBeNull();
    expect(resolveInside(f.download, "a/b.apk")).toBe(path.join(f.download, "a", "b.apk"));
  });

  it("registers nothing when not configured", async () => {
    const app = await appWith({});
    expect((await app.inject({ url: "/download/latest.json" })).statusCode).toBe(404);
    expect((await app.inject({ url: "/" })).statusCode).toBe(404);
  });
});
