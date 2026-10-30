/**
 * 第四批迁移 0046：章节战斗背景列 + 第 1、2 关首领默认名字 + 统一首领立绘 boss_*。
 * 历史上还曾把「大招自动释放等待」从旧默认 2 改成 0；该配置项现已下线（无大招等待 UI），种子不再写入。
 * 只改还是默认值的（名字 = 0041 / 种子的「精英·<小怪>」，立绘 = 0041 / 0044 / 种子的旧编号），后台改过的不动。可以重复执行。
 */
import { readFileSync } from "node:fs";
import { eq, sql } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentChapters, contentGlobals, contentStages } from "./schema.js";
import { PROTOTYPE_BOSS_NAMES, applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { loadDraftSnapshot } from "../modules/content/snapshot.js";
import { validateContent } from "../modules/content/validate.js";
import { withDb } from "../test/db.js";

type TestDb = Parameters<Parameters<typeof withDb>[0]>[0];
const text = readFileSync(new URL("../../drizzle/0046_boss_names_art_battle_bg.sql", import.meta.url), "utf8");

async function migrate(db: TestDb) {
  for (const statement of text.split("--> statement-breakpoint").map((part) => part.replace(/^--.*$/gm, "").trim()).filter(Boolean)) {
    await db.execute(sql.raw(statement));
  }
}

const OLD_ART: Record<string, string> = {
  lianqi_1: "wolf", lianqi_2: "fox", lianqi_3: "bear", zhuji_1: "ghost", zhuji_2: "bone_golem", zhuji_3: "ghost_elder",
  jindan_1: "lava_lizard", jindan_2: "fire_crow", jindan_3: "fire_jiao",
};

/** 0045 之后线上的样子：精英叫「精英·<小怪>」，立绘是普通怪编号，章节没有战斗背景列。 */
async function before0046(db: TestDb) {
  await applyPrototypeV12(db);
  for (const stage of await db.select().from(contentStages)) {
    const [boss] = stage.bosses;
    const chief = stage.slug.endsWith("_3");
    const name = chief ? boss!.name : `精英·${stage.monsters[0]!.name}`;
    await db.update(contentStages).set({ bosses: [{ ...boss!, name, artKey: OLD_ART[stage.slug] ?? boss!.artKey } as never], bossName: name }).where(eq(contentStages.slug, stage.slug));
  }
  await db.execute(sql.raw(`ALTER TABLE "content_chapters" DROP COLUMN IF EXISTS "battle_bg_key"`));
}

describe("migration 0046 (第四批：首领名字 / 统一首领立绘 / 战斗背景)", () => {
  it("is in the journal right after 0045 and inside dev2's range", () => {
    const journal = JSON.parse(readFileSync(new URL("../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as { entries: { tag: string; when: number }[] };
    const row = journal.entries.find((entry) => entry.tag === "0046_boss_names_art_battle_bg");
    const prev = journal.entries.find((entry) => entry.tag === "0045_boss_single_rules");
    expect(row!.when).toBeGreaterThan(prev!.when);
    expect(row!.when).toBeLessThan(1796000000000);
  });

  it("renames / re-arts only the bosses that still have the old defaults; admin edits are kept; idempotent", async () => {
    await withDb(async (db) => {
      await before0046(db);
      // 后台改过：lianqi_2 的名字、zhuji_1 的立绘
      const edit = async (slug: string, patch: Record<string, unknown>) => {
        const [row] = await db.select().from(contentStages).where(eq(contentStages.slug, slug));
        await db.update(contentStages).set({ bosses: [{ ...row!.bosses[0]!, ...patch } as never] }).where(eq(contentStages.slug, slug));
      };
      await edit("lianqi_2", { name: "狐仙娘娘" });
      await edit("zhuji_1", { artKey: "bat" });
      await migrate(db);
      const once = await loadDraftSnapshot(db);
      await migrate(db);
      const twice = await loadDraftSnapshot(db);
      expect(twice.stages).toEqual(once.stages);
      const boss = (slug: string) => once.stages.find((row) => row.slug === slug)!.bosses![0]!;
      expect(boss("lianqi_1")).toMatchObject({ name: "青鬃狼王", artKey: "boss_wolf" });
      expect(boss("lianqi_2")).toMatchObject({ name: "狐仙娘娘", artKey: "boss_fox" }); // 名字改过：不动
      expect(boss("lianqi_3")).toMatchObject({ name: "黑风熊王", artKey: "boss_bear" });
      expect(boss("zhuji_1")).toMatchObject({ name: "游魂统领", artKey: "bat" }); // 立绘改过：不动
      expect(boss("zhuji_2")).toMatchObject({ name: "白骨傀将", artKey: "boss_bone_golem" });
      expect(boss("zhuji_3")).toMatchObject({ name: "噬魂老鬼", artKey: "boss_ghost_elder" });
      expect(boss("jindan_1")).toMatchObject({ name: "炎鳞蜥皇", artKey: "boss_lava_lizard" });
      expect(boss("jindan_2")).toMatchObject({ name: "焚天火鸦", artKey: "boss_fire_crow" });
      expect(boss("jindan_3")).toMatchObject({ name: "赤焰蛟", artKey: "boss_fire_jiao" });
      const [stage] = await db.select().from(contentStages).where(eq(contentStages.slug, "jindan_2"));
      expect(stage!.bossName).toBe("焚天火鸦");
      expect(once.chapters!.map((row) => [row.slug, row.battleBgKey])).toEqual([
        ["heifeng", "heifeng"], ["youming", "youming"], ["chiyan", "chiyan"],
        ["zixiao", "youming"], ["shenyou", "heifeng"], ["taixu", "youming"],
        ["hedao", "chiyan"], ["daluo", "heifeng"],
      ]);
      expect(validateContent(once).errors).toEqual([]);
    });
  });

  it("keeps an admin-chosen battle background and the new seed is already in the migrated shape", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      await db.update(contentChapters).set({ battleBgKey: "youming" }).where(eq(contentChapters.slug, "heifeng"));
      const before = await loadDraftSnapshot(db);
      await migrate(db);
      const after = await loadDraftSnapshot(db);
      expect(after.stages).toEqual(before.stages);
      expect(after.chapters).toEqual(before.chapters);
      expect(after.chapters!.find((row) => row.slug === "heifeng")!.battleBgKey).toBe("youming");
      for (const [slug, name] of Object.entries(PROTOTYPE_BOSS_NAMES)) {
        expect(after.stages.find((row) => row.slug === slug)!.bosses![0]!.name).toBe(name);
      }
    });
  });

  it("legacy ultAutoCastWindowSeconds: seed omits the retired field; migration still turns old default 2 into 0 and keeps other values", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      type CombatWait = { ultAutoCastWindowSeconds?: number } | null | undefined;
      const wait = async () => ((await db.select().from(contentGlobals))[0]!.combat as CombatWait)?.ultAutoCastWindowSeconds;
      // 产品锁死：无「大招等待」；当前种子 / 规则表不再写入该键。
      expect(await wait()).toBeUndefined();
      expect(JSON.stringify((await db.select().from(contentGlobals))[0]!.combat)).not.toContain("ultAutoCastWindowSeconds");

      const setWait = async (value: number) => {
        const [row] = await db.select().from(contentGlobals);
        await db.update(contentGlobals).set({
          combat: { ...(row!.combat as object), ultAutoCastWindowSeconds: value } as NonNullable<typeof row.combat>,
        });
      };
      // 0046 SQL 仍对历史数据生效：旧默认 2 → 0，其它取值保留。
      await setWait(2);
      await migrate(db);
      expect(await wait()).toBe(0);
      await migrate(db);
      expect(await wait()).toBe(0);
      await setWait(3.5);
      await migrate(db);
      expect(await wait()).toBe(3.5);
    });
  });
});
