import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentGlobals, playerOfflineReports, playerSkills, playerStates, players } from "../db/schema.js";
import { resetPlayer } from "../modules/player/service.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z");
type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];

async function boot(db: TestDb, name: string) {
  await applyPrototypeV12(db);
  let clock = start;
  const app = await buildApp(db, () => clock, { randomInt: () => 9999 });
  const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: name, password: "correct-horse" } });
  const headers = { authorization: `Bearer ${registered.json().token as string}` };
  const [player] = await db.select().from(players).where(eq(players.usernameLower, name));
  const at = async (seconds: number) => {
    clock = new Date(start.getTime() + seconds * 1000);
    return (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json();
  };
  const ack = (id: string, auth = headers) => app.inject({ method: "POST", url: `/api/v1/me/offline-reports/${id}/ack`, headers: auth });
  return { app, headers, playerId: player!.id, at, ack };
}

describe("offline popup: ≥ 5 min offline, 'read' acknowledgement, no claim step", () => {
  it("under 5 minutes: cultivation is credited but there is no popup record; exactly 5 minutes creates one", async () => {
    await withDb(async (db) => {
      const { app, at, playerId } = await boot(db, "off_a");
      const short = await at(299);
      expect(short.lastSettle).toMatchObject({ online: false, passiveGained: 299 });
      expect(short.offlineReport).toBeNull();
      expect(await db.select().from(playerOfflineReports)).toHaveLength(0);
      const long = await at(299 + 300);
      expect(long.offlineReport).toMatchObject({ seconds: 300, countedSeconds: 300, hitCap: false, gained: 300, baseGained: 300, bonusGained: 0, offlineCapSeconds: 28800, realmName: "炼气一层" });
      expect(long.cultivation).toBe(299 + 300);
      const [row] = await db.select().from(playerOfflineReports).where(eq(playerOfflineReports.playerId, playerId));
      expect(row).toMatchObject({ seconds: 300, gained: 300, acknowledgedAt: null, realmSlug: "lianqi_1" });
      expect(row!.startedAt.getTime()).toBe(start.getTime() + 299 * 1000);
      expect(row!.endedAt.getTime()).toBe(start.getTime() + 599 * 1000);
      await app.close();
    });
  });

  it("splits the gain into base + skill bonus and reports the cap (10 h away, 8 h counted, +15% skill)", async () => {
    await withDb(async (db) => {
      const { app, at, playerId } = await boot(db, "off_b");
      await db.insert(playerSkills).values({ playerId, skillSlug: "skill_qingyuan", learnedAt: start, level: 1, runningSlot: "heart" });
      const result = await at(10 * 3600);
      expect(result.offlineReport).toMatchObject({ seconds: 36000, countedSeconds: 28800, hitCap: true, gained: 33120, baseGained: 28800, bonusGained: 4320 });
      await app.close();
    });
  });

  it("the report stays on every poll until 'read'; reading does not change cultivation (no claim); repeated or foreign acks are harmless / rejected", async () => {
    await withDb(async (db) => {
      const { app, at, ack, headers } = await boot(db, "off_c");
      const away = await at(3600);
      const id = away.offlineReport.id as string;
      const again = await at(3600 + 3);
      expect(again.offlineReport.id).toBe(id);
      expect(again.lastSettle.online).toBe(true);
      const before = again.cultivation;
      const response = await ack(id);
      expect(response.statusCode).toBe(200);
      expect(response.json()).toMatchObject({ ok: true, id, acknowledged: true });
      const after = await at(3600 + 6);
      expect(after.offlineReport).toBeNull();
      expect(after.cultivation).toBe(before + 3 + after.lastSettle.killCultivation);
      expect((await ack(id)).statusCode).toBe(200); // 重复确认没问题
      expect((await ack("00000000-0000-4000-8000-000000000000")).statusCode).toBe(404);
      expect((await ack("not-a-uuid")).statusCode).toBe(404);
      // 别的玩家不能确认这条
      const other = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "off_c2", password: "correct-horse" } });
      const foreign = await ack(id, { authorization: `Bearer ${other.json().token as string}` });
      expect(foreign.statusCode).toBe(404);
      expect(headers.authorization).toBeTruthy();
      await app.close();
    });
  });

  it("a newer offline segment replaces the unread one in the popup and one ack clears both", async () => {
    await withDb(async (db) => {
      const { app, at, ack, playerId } = await boot(db, "off_d");
      const first = await at(1000);
      await at(1003);
      const second = await at(1003 + 2000);
      expect(second.offlineReport.id).not.toBe(first.offlineReport.id);
      expect(second.offlineReport.seconds).toBe(2000);
      await ack(second.offlineReport.id);
      const rows = await db.select().from(playerOfflineReports).where(eq(playerOfflineReports.playerId, playerId));
      expect(rows).toHaveLength(2);
      expect(rows.every((row) => row.acknowledgedAt !== null)).toBe(true);
      expect((await at(1003 + 2003)).offlineReport).toBeNull();
      await app.close();
    });
  });

  it("the minimum duration is an admin rule (offlinePopupMinSeconds)", async () => {
    await withDb(async (db) => {
      const { app, at } = await boot(db, "off_e");
      const [globals] = await db.select().from(contentGlobals);
      await db.update(contentGlobals).set({ combat: { ...globals!.combat!, offlinePopupMinSeconds: 60 } });
      expect((await at(59)).offlineReport).toBeNull();
      expect((await at(59 + 60)).offlineReport).toMatchObject({ seconds: 60 });
      await app.close();
    });
  });

  it("resetting a test account clears its offline records and wave state", async () => {
    await withDb(async (db) => {
      const { app, at, playerId } = await boot(db, "off_f");
      await at(400);
      await db.update(playerStates).set({ waveProgress: 3, waveDeathsInRow: 2 }).where(eq(playerStates.playerId, playerId));
      expect(await db.select().from(playerOfflineReports)).toHaveLength(1);
      await resetPlayer(db, "off_f", new Date(start.getTime() + 500_000));
      expect(await db.select().from(playerOfflineReports)).toHaveLength(0);
      const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, playerId));
      expect(state).toMatchObject({ waveProgress: 0, waveDeathsInRow: 0 });
      await app.close();
    });
  });
});
