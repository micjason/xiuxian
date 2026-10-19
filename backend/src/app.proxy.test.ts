import { afterEach, describe, expect, it } from "vitest";
import { insertStartingRealm, withDb } from "./test/db.js";
import { buildApp } from "./app.js";

describe("TRUST_PROXY", { timeout: 30_000 }, () => {
  afterEach(() => {
    delete process.env.TRUST_PROXY;
  });

  async function seenIp(trust: string | undefined): Promise<string> {
    if (trust) process.env.TRUST_PROXY = trust;
    let ip = "";
    await withDb(async (db) => {
      await insertStartingRealm(db);
      const app = await buildApp(db);
      app.get("/_ip", async (request) => ({ ip: request.ip }));
      const res = await app.inject({
        method: "GET",
        url: "/_ip",
        remoteAddress: "127.0.0.1",
        headers: { "x-forwarded-for": "203.0.113.7" },
      });
      ip = res.json().ip as string;
      await app.close();
    });
    return ip;
  }

  it("ignores X-Forwarded-For by default", async () => {
    expect(await seenIp(undefined)).toBe("127.0.0.1");
  });

  it("uses the forwarded address when the proxy is trusted", async () => {
    expect(await seenIp("127.0.0.1")).toBe("203.0.113.7");
  });
});
