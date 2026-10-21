/**
 * 第三批迁移 0040–0043：从「第三批之前的线上样子」（3 个章末首领、其余关卡没有首领、没有章节 / 立绘 / 首领规则）
 * 迁到和 applyPrototypeV12 新种子一样的内容；老玩家按境界补解锁记录。每个迁移都要能重复执行。
 */
import { readFileSync } from "node:fs";
import { and, eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { contentChapters, contentGlobals, contentStages, playerStageProgress, playerStates, players } from "./schema.js";
import { DEFAULT_BOSS_RULES } from "../modules/content/boss-rules.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { loadDraftSnapshot } from "../modules/content/snapshot.js";
import { tuningOf } from "../modules/content/tuning.js";
import { validateContent } from "../modules/content/validate.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const TAGS = ["0040_chapters", "0041_boss_tier_art", "0042_boss_rules_defaults", "0043_unlock_backfill"];
const files = TAGS.map((tag) => readFileSync(new URL(`../../drizzle/${tag}.sql`, import.meta.url), "utf8"));
const start = new Date("2026-10-08T03:00:00.000Z");

async function runMigrations(db: TestDb) {
  for (const text of files) {
    for (const statement of text.split("--> statement-breakpoint").map((part) => part.replace(/^--.*$/gm, "").trim()).filter(Boolean)) {
      await db.execute(sql.raw(statement));
    }
  }
}

/** 回到第三批之前的线上样子（10-21 线上库：9 关，章末 3 关有首领，其余没有；后台保存过的关卡 sort_order 是 0）。 */
async function legacyWorld(db: TestDb) {
  await applyPrototypeV12(db);
  await db.update(contentStages).set({ chapterSlug: null });
  await db.delete(contentChapters);
  for (const stage of await db.select().from(contentStages)) {
    const monsters = (stage.monsters ?? []).map(({ artKey: _artKey, ...rest }) => rest);
    const chief = ["lianqi_3", "zhuji_3", "jindan_3"].includes(stage.slug);
    const bosses = chief ? (stage.bosses ?? []).map(({ artKey: _artKey, ...rest }) => rest) : [];
    await db
      .update(contentStages)
      .set({ monsters, bosses, ...(chief ? {} : { bossName: "", bossAttack: 0, bossDefense: 0, bossHp: 0, bossInterval: 0 }) })
      .where(eq(contentStages.slug, stage.slug));
  }
  const [globals] = await db.select().from(contentGlobals);
  const { bossRules: _bossRules, ...tuning } = (globals!.tuning ?? {}) as Record<string, unknown>;
  await db.update(contentGlobals).set({ tuning, combat: { ...globals!.combat!, bossDailyRewardCount: 4 } });
}

async function player(db: TestDb, app: Awaited<ReturnType<typeof buildApp>>, name: string, realmSlug: string) {
  await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: name, password: "correct-horse" } });
  const [row] = await db.select().from(players).where(eq(players.usernameLower, name));
  await db.update(playerStates).set({ realmSlug }).where(eq(playerStates.playerId, row!.id));
  return row!.id;
}

const progressOf = async (db: TestDb, playerId: string) =>
  (await db.select().from(playerStageProgress).where(eq(playerStageProgress.playerId, playerId))).map((row) => row.stageSlug).sort();

describe("migrations 0040–0043 (第三批：章节、每关首领、首领规则、解锁补齐)", () => {
  it("are in the journal, in order, after everything else (when ≥ 1795000000000)", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as { entries: { idx: number; tag: string; when: number }[] };
    const ours = TAGS.map((tag) => journal.entries.find((row) => row.tag === tag));
    expect(ours.every(Boolean)).toBe(true);
    const whens = ours.map((row) => row!.when);
    expect(whens.every((when) => when >= 1795000000000)).toBe(true);
    expect([...whens].sort((a, b) => a - b)).toEqual(whens);
    const others = journal.entries.filter((row) => !TAGS.includes(row.tag));
    expect(Math.max(...others.map((row) => row.when))).toBeLessThan(whens[0]!);
  });

  it("turn the legacy world into the new seed (chapters, art keys, elites, rules) and backfill unlocks by realm; running twice changes nothing", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const seed = await loadDraftSnapshot(db);
      await legacyWorld(db);
      const app = await buildApp(db, () => start, { randomInt: () => 0 });
      const fresh = await player(db, app, "m40_fresh", "lianqi_1");
      const mid = await player(db, app, "m40_mid", "zhuji_2");
      const top = await player(db, app, "m40_top", "jindan_3");
      // 中间那个玩家打过黑风熊王 3 次，今天领过 2 次每日奖励
      await db
        .insert(playerStageProgress)
        .values({ playerId: mid, stageSlug: "lianqi_3", unlockedAt: start, firstClearedAt: start, clearCount: 3, dailyRewardCount: 2, dailyRewardDay: "2026-10-08" });

      await db.update(contentStages).set({ sortOrder: 0 }).where(eq(contentStages.slug, "lianqi_2")); // 后台保存过的关卡（老 bug 把顺序清零）
      await runMigrations(db);
      const once = await loadDraftSnapshot(db);
      await runMigrations(db);
      const twice = await loadDraftSnapshot(db);
      const content = (world: typeof once) => ({ chapters: world.chapters, stages: [...world.stages].sort((a, b) => a.slug.localeCompare(b.slug)), tuning: world.globals.tuning });
      expect(content(twice)).toEqual(content(once));

      // 内容和新种子一致（首领、立绘、章节、档次）
      expect(once.chapters?.map((row) => [row.slug, row.displayName, row.sortOrder, row.bgKey, row.bossFx, row.chiefStageSlug])).toEqual(
        seed.chapters?.map((row) => [row.slug, row.displayName, row.sortOrder, row.bgKey, row.bossFx, row.chiefStageSlug]),
      );
      const shape = (world: typeof once) =>
        [...world.stages].sort((a, b) => a.slug.localeCompare(b.slug)).map((row) => ({
          slug: row.slug,
          chapterSlug: row.chapterSlug,
          tier: row.tier,
          monsters: row.monsters?.map((m) => m.artKey),
          boss: row.bosses?.map((b) => ({ name: b.name, attack: b.attack, defense: b.defense, hp: b.hp, interval: b.interval, artKey: b.artKey, firstClear: b.firstClear })),
        }));
      expect(shape(once)).toEqual(shape(seed));
      expect((await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_2")))[0]).toMatchObject({ sortOrder: 2, bossName: "精英·赤眼狐妖", bossHp: 625 });
      expect(validateContent(once).errors).toEqual([]);

      // 首领规则默认值；章末每日次数沿用原来的 4
      const [globals] = await db.select().from(contentGlobals);
      expect(tuningOf(globals!.tuning).bossRules).toEqual({ elite: DEFAULT_BOSS_RULES.elite, chief: { ...DEFAULT_BOSS_RULES.chief, dailyRewardLimit: 4 } });

      // 解锁补齐：所需境界 ≤ 当前境界的关卡都有一行；已有记录原样保留
      expect(await progressOf(db, fresh)).toEqual(["lianqi_1"]);
      expect(await progressOf(db, mid)).toEqual(["lianqi_1", "lianqi_2", "lianqi_3", "zhuji_1", "zhuji_2"]);
      expect(await progressOf(db, top)).toHaveLength(9);
      const [bear] = await db.select().from(playerStageProgress).where(and(eq(playerStageProgress.playerId, mid), eq(playerStageProgress.stageSlug, "lianqi_3")));
      expect(bear).toMatchObject({ clearCount: 3, dailyRewardCount: 2, dailyRewardDay: "2026-10-08", autoChallengeAt: null });
      expect(bear?.firstClearedAt?.getTime()).toBe(start.getTime());
      const [elite] = await db.select().from(playerStageProgress).where(and(eq(playerStageProgress.playerId, mid), eq(playerStageProgress.stageSlug, "zhuji_1")));
      expect(elite?.firstClearedAt).toBeNull(); // 新加的精英没打过，首通奖励还能拿
      await app.close();
    });
  });

  it("stage names that do not match a known chapter stay chapterless (publish validation reports them) and get no elite", async () => {
    await withDb(async (db) => {
      await legacyWorld(db);
      await db.update(contentStages).set({ displayName: "新地图·一" }).where(eq(contentStages.slug, "jindan_1"));
      await runMigrations(db);
      const [stage] = await db.select().from(contentStages).where(eq(contentStages.slug, "jindan_1"));
      expect(stage).toMatchObject({ chapterSlug: null, bosses: [] });
      const errors = validateContent(await loadDraftSnapshot(db)).errors;
      expect(errors.some((row) => row.slug === "jindan_1" && row.field === "chapterSlug")).toBe(true);
    });
  });
});
