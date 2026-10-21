import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { announcements, contentGlobals, contentRealms } from "../db/schema.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-21T03:00:00.000Z");

describe("announcements reach the game via GET /me/state", () => {
  it("enabled announcements come with the heartbeat until the player dismisses them; disabled ones and income popups never do", async () => {
    await withDb(async (db) => {
      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "qi_early",
        offlineCapSeconds: 28800,
        bagCapacity: 20,
        powerWeights: { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 },
        combat: { minInterval: 0.7, defenseConstant: 1, recommendedPowerMargin: 1.05, challengeCooldownSeconds: 0, timeLimitSeconds: 45, speedBase: 100 },
      });
      await db.insert(contentRealms).values({ slug: "qi_early", displayName: "炼气一层", sortOrder: 1, nextRealmSlug: null, tickSeconds: 1, gainPerTick: 1, breakthroughCost: 9999, baseAttack: 10, baseDefense: 10, baseHp: 33, baseInterval: 1.5 });
      const [shown] = await db.insert(announcements).values({ title: "开服公告", body: "欢迎来到修仙世界", enabled: true, enabledAt: start }).returning();
      await db.insert(announcements).values({ title: "草稿", body: "还没发", enabled: false });
      let clock = start;
      const app = await buildApp(db, () => clock, { randomInt: () => 0 });
      const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "notice_user", password: "correct-horse" } });
      const headers = { authorization: `Bearer ${registered.json().token as string}` };

      // 离线 2 小时：以前会多出一个 60 秒收益弹窗，现在只有公告（离线收益走 offlineReport）
      clock = new Date(start.getTime() + 2 * 3600 * 1000);
      const first = (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json();
      expect(first.notices).toEqual([
        { id: shown!.id, type: "announcement", priority: 2, template: "acknowledge", triggeredAt: start.toISOString(), payload: { title: "开服公告", body: "欢迎来到修仙世界" } },
      ]);

      const dismissed = await app.inject({ method: "POST", url: `/api/v1/me/notices/${shown!.id}/dismiss`, headers });
      expect(dismissed.statusCode).toBeLessThan(300);
      clock = new Date(clock.getTime() + 3000);
      const second = (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json();
      expect(second.notices).toEqual([]);
      await app.close();
    });
  });
});
