import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentGlobals, contentRealms } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { createOpsSkill, createOpsWeapon, createSkillCategory, createWeaponCategory, deleteOpsWeapon } from "./ops-content.js";
import { createTrialPuppet, listTrialPuppets, updateTrialPuppet } from "./puppets.js";
import { runTrial } from "./trial.js";

describe("trial puppets", () => {
  it("saves both kinds, fights several at once, and stops when gear is gone", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values([
        { slug: "1", displayName: "凡人", sortOrder: 1, nextRealmSlug: null, baseAttack: 10, baseHp: 100, baseInterval: 1.5 },
        { slug: "2", displayName: "练气", sortOrder: 2, nextRealmSlug: null, baseAttack: 10, baseHp: 50, baseInterval: 1.5 },
      ]);
      await db.insert(contentGlobals).values({
        id: 1,
        offlineCapSeconds: 28800,
        bagCapacity: 100,
        powerWeights: { attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 },
        combat: {
          minInterval: 0.7,
          playerDefenseFactor: 0.4,
          bossDefenseFactor: 0.5,
          challengeCooldownSeconds: 3,
          timeLimitSeconds: 60,
          playerDamageFloor: 1,
          bossDamageFloor: 0,
          speedBase: 100,
        },
      });
      const weaponCategory = await createWeaponCategory(db, { displayName: "剑" }, null);
      const sword = await createOpsWeapon(
        db,
        { displayName: "木剑", categoryId: weaponCategory.id, attack: 25, defense: 0, hp: 0, speed: 0 },
        null,
      );
      const skillCategory = await createSkillCategory(db, { displayName: "吐纳" }, null);
      const skill = await createOpsSkill(
        db,
        { displayName: "吐纳", categoryId: skillCategory.id, attack: 0, defense: 0, hp: 0, speed: 0, cultivateBonus: 0 },
        null,
      );
      const mortal = await createTrialPuppet(db, { displayName: "刚入门", kind: "configured", realmCode: 1, weaponIds: [], skillIds: [] }, null);
      const armed = await createTrialPuppet(
        db,
        { displayName: "练气带剑", kind: "configured", realmCode: 2, weaponIds: [sword.id], skillIds: [skill.id] },
        null,
      );
      const probe = await createTrialPuppet(
        db,
        { displayName: "手填门槛", kind: "manual", attack: 45, defense: 0, hp: 150, speed: 100, interval: 1.5 },
        null,
      );

      const listed = await listTrialPuppets(db);
      expect(listed.map((row) => row.displayName)).toEqual(["刚入门", "练气带剑", "手填门槛"]);
      expect(listed.find((row) => row.id === mortal.id)).toMatchObject({
        kindName: "按配置算",
        power: 14,
        attack: 10,
        hp: 100,
        problem: null,
      });
      expect(listed.find((row) => row.id === armed.id)).toMatchObject({ attack: 45, hp: 150, power: 51 });
      expect(listed.find((row) => row.id === probe.id)).toMatchObject({
        kindName: "手填属性",
        attack: 45,
        speed: 100,
        interval: 1.5,
        power: 201,
        problem: null,
      });

      await expect(
        updateTrialPuppet(db, probe.id, { displayName: "手填门槛", kind: "configured", realmCode: 1 }, null),
      ).rejects.toMatchObject({ message: "人偶类型不能改" });
      await expect(
        createTrialPuppet(db, { displayName: "手填门槛", kind: "manual", attack: 1, defense: 0, hp: 1, speed: 0, interval: 1.5 }, null),
      ).rejects.toMatchObject({ message: "名称不能重复" });
      await expect(
        createTrialPuppet(db, { displayName: "太快", kind: "manual", attack: 1, defense: 0, hp: 1, speed: 0, interval: 0.2 }, null),
      ).rejects.toMatchObject({ message: "出手间隔不能小于 0.7 秒" });

      const boss = { attack: 20, defense: 0, hp: 300, interval: 1.5 };
      const fought = await runTrial(db, { puppetIds: [mortal.id, armed.id, probe.id], boss });
      expect(fought.results.map((row) => [row.displayName, row.kindName, row.win, row.error])).toEqual([
        ["刚入门", "按配置算", false, null],
        ["练气带剑", "按配置算", true, null],
        ["手填门槛", "手填属性", true, null],
      ]);
      expect(fought.results[0]).toMatchObject({ playerKillSeconds: 45, bossKillSeconds: 7.5 });
      expect(fought.results[2]?.player?.interval).toBe(1.5);

      await deleteOpsWeapon(db, sword.id);
      const broken = await runTrial(db, { puppetIds: [mortal.id, armed.id], boss });
      expect(broken.results[0]?.win).toBe(false);
      expect(broken.results[1]).toMatchObject({ error: "有武器或功法已经删除，先改这个人偶", win: null });
      const afterDelete = await listTrialPuppets(db);
      expect(afterDelete.find((row) => row.id === armed.id)?.problem).toBe("有武器或功法已经删除，先改这个人偶");
      expect(afterDelete.find((row) => row.id === armed.id)?.power).toBeNull();

      await db.delete(contentRealms).where(eq(contentRealms.slug, "1"));
      const noRealm = await runTrial(db, { puppetIds: [mortal.id], boss });
      expect(noRealm.results[0]?.error).toBe("境界已经不存在");
    });
  });
});
