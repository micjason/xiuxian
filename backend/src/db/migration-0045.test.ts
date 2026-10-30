/**
 * 第四批迁移 0045：两档首领规则 → 一套；单关覆盖换算；补重复奖励；全局每日次数 / 挂机波数两列。可以重复执行。
 */
import { readFileSync } from "node:fs";
import { and, eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentGlobals, contentStages, playerStageProgress, playerStates, players } from "./schema.js";
import { DEFAULT_BOSS_RULES } from "../modules/content/boss-rules.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { loadDraftSnapshot } from "../modules/content/snapshot.js";
import { tuningOf } from "../modules/content/tuning.js";
import { validateContent } from "../modules/content/validate.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0045_boss_single_rules.sql", import.meta.url), "utf8");
const start = new Date("2026-10-08T03:00:00.000Z");

async function migrate(db: TestDb) {
  for (const statement of text.split("--> statement-breakpoint").map((part) => part.replace(/^--.*$/gm, "").trim()).filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

/** 第三批线上的样子：两档规则（章末每日 4 次、品质改过），精英没有重复奖励，有几关单独改过规则。 */
async function batch3World(db: TestDb) {
  await applyPrototypeV12(db);
  const legacy = {
    elite: { statMode: "auto", statMul: { hp: 5, attack: 1.3, defense: 1.2 }, allowRepeat: true, repeatRewards: false, dailyRewardLimit: 0, gearQualityPct: { white: 0, green: 70, blue: 25, purple: 5, orange: 0 }, autoChallenge: true, autoChallengePowerPct: 100, autoChallengeRetrySeconds: 60, unlockNeedsBossWin: true, unlockNeedsRealm: true },
    chief: { statMode: "manual", statMul: { hp: 8.5, attack: 1.15, defense: 1.2 }, allowRepeat: true, repeatRewards: true, dailyRewardLimit: 4, gearQualityPct: { white: 0, green: 45, blue: 35, purple: 15, orange: 5 }, autoChallenge: false, autoChallengePowerPct: 100, autoChallengeRetrySeconds: 60, unlockNeedsBossWin: true, unlockNeedsRealm: true },
  };
  const [globals] = await db.select().from(contentGlobals);
  await db.update(contentGlobals).set({ tuning: { ...(globals!.tuning as object), bossRules: legacy } as never });
  for (const stage of await db.select().from(contentStages)) {
    const [boss] = stage.bosses;
    const { rules: _rules, ...rest } = boss!;
    const chief = stage.slug.endsWith("_3");
    let next: Record<string, unknown> = chief ? rest : (({ repeat: _repeat, ...noRepeat }) => noRepeat)(rest);
    if (stage.slug === "lianqi_1") next = { ...next, rules: { autoChallenge: false, dailyRewardLimit: 2 } };
    if (stage.slug === "lianqi_2") next = { ...next, rules: { dailyRewardLimit: 3 } };
    if (stage.slug === "zhuji_3") next = { ...next, rules: { gearQualityPct: { green: 40, orange: 10 }, dailyRewardLimit: 1 } };
    await db.update(contentStages).set({ bosses: [next as never] }).where(eq(contentStages.slug, stage.slug));
  }
}

describe("migration 0045 (第四批：一套首领规则)", () => {
  it("is in the journal right after 0044 (when 1795000500000, before the lead dev's 0050+ range)", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as { entries: { idx: number; tag: string; when: number }[] };
    const row = journal.entries.find((entry) => entry.tag === "0045_boss_single_rules");
    const prev = journal.entries.find((entry) => entry.tag === "0044_elite_art_backfill");
    expect(row?.when).toBe(1795000500000);
    expect(row!.when).toBeGreaterThan(prev!.when);
    expect(row!.when).toBeLessThan(1796000000000);
  });

  it("turns the two columns into one set, maps per-stage overrides, adds repeat rewards to elites, keeps first clears as beaten; running twice changes nothing", async () => {
    await withDb(async (db) => {
      await batch3World(db);
      // 列还没有时（线上 0044 的样子）先删掉，迁移会加回来
      await db.execute(sql.raw(`ALTER TABLE "player_states" DROP COLUMN IF EXISTS "boss_daily_count"; ALTER TABLE "player_states" DROP COLUMN IF EXISTS "boss_daily_day"; ALTER TABLE "player_stage_progress" DROP COLUMN IF EXISTS "idle_waves"`));
      await migrate(db);
      const app = await buildApp(db, () => start, { randomInt: () => 0 });
      const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "m45", password: "correct-horse" } });
      const [player] = await db.select().from(players).where(eq(players.usernameLower, "m45"));
      // 打过精英、打过章末首领（以前的首通记录）
      for (const stageSlug of ["lianqi_1", "lianqi_3"]) {
        const row = { firstClearedAt: start, clearCount: 2, dailyRewardCount: 1, dailyRewardDay: "2026-10-08" };
        await db.insert(playerStageProgress).values({ playerId: player!.id, stageSlug, unlockedAt: start, ...row }).onConflictDoUpdate({ target: [playerStageProgress.playerId, playerStageProgress.stageSlug], set: row });
      }
      const once = await loadDraftSnapshot(db);
      await migrate(db);
      const twice = await loadDraftSnapshot(db);
      const content = (world: typeof once) => ({ stages: [...world.stages].sort((a, b) => a.slug.localeCompare(b.slug)), tuning: world.globals.tuning });
      expect(content(twice)).toEqual(content(once));

      const [globals] = await db.select().from(contentGlobals);
      expect((globals!.tuning as Record<string, unknown>).bossRules).toEqual({ ...DEFAULT_BOSS_RULES, statMul: { hp: 5, attack: 1.3, defense: 1.2 }, repeatGearQualityPct: { white: 0, green: 45, blue: 35, purple: 15, orange: 5 }, dailyChallengeTotal: 4 });
      expect(tuningOf(globals!.tuning).bossRules.dailyChallengeTotal).toBe(4);

      const override = (slug: string) => once.stages.find((row) => row.slug === slug)!.bosses![0]!.ruleOverride ?? null;
      expect(override("lianqi_1")).toEqual({ autoChallenge: false }); // 每关每日次数去掉
      expect(override("lianqi_2")).toBeNull();
      expect(override("lianqi_3")).toEqual({ statMode: "manual" }); // 章末：手填数值
      expect(override("zhuji_3")).toEqual({ statMode: "manual", repeatGearQualityPct: { white: 0, green: 40, blue: 35, purple: 15, orange: 10 } });
      // 章末首领的手填数值原样
      expect(once.stages.find((row) => row.slug === "lianqi_3")!.bosses![0]).toMatchObject({ name: "黑风熊王", hp: 1640, attack: 42, statsAuto: false });
      // 原精英补上重复奖励；章末原样
      expect(once.stages.find((row) => row.slug === "lianqi_2")!.bosses![0]!.repeat).toEqual({ gear: true, extras: [{ itemSlug: "enh_stone_low", chanceBp: 7000, minQty: 1, maxQty: 1 }] });
      expect(once.stages.find((row) => row.slug === "zhuji_3")!.bosses![0]!.repeat?.extras).toHaveLength(2);
      expect(validateContent(once).errors).toEqual([]);

      // 新列：默认 0；以前的首通照算已击败（下一关解锁）
      const [state] = await db.select().from(playerStates).where(eq(playerStates.playerId, player!.id));
      expect(state).toMatchObject({ bossDailyCount: 0, bossDailyDay: null });
      const rows = await db.select().from(playerStageProgress).where(and(eq(playerStageProgress.playerId, player!.id), eq(playerStageProgress.stageSlug, "lianqi_3")));
      expect(rows[0]).toMatchObject({ idleWaves: 0, clearCount: 2 });
      await db.update(playerStates).set({ realmSlug: "zhuji_1" }).where(eq(playerStates.playerId, player!.id));
      const headers = { authorization: `Bearer ${registered.json().token as string}` };
      const access = (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json().stageAccess;
      expect(access.find((row: { slug: string }) => row.slug === "lianqi_3")).toMatchObject({ cleared: true });
      expect(access.find((row: { slug: string }) => row.slug === "zhuji_1")).toMatchObject({ unlocked: true, playable: true });
      await app.close();
    });
  });

  it("the new seed already matches what 0045 produces (nothing to change on a fresh install)", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const before = await loadDraftSnapshot(db);
      await migrate(db);
      const after = await loadDraftSnapshot(db);
      expect(after.stages).toEqual(before.stages);
    });
  });
});
