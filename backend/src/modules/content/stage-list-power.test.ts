import { describe, expect, it } from "vitest";
import { contentGlobals, contentRealms } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { createOpsStage, listOpsStages, updateOpsStage } from "./ops-content.js";

describe("stage list recommended power", () => {
  it("shows the hand-filled power first, then the computed reference or the reason it cannot be computed", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({ slug: "2", displayName: "练气", sortOrder: 2, nextRealmSlug: null, baseInterval: 1.5 });
      const armed = await createOpsStage(
        db,
        { displayName: "后山", realmCode: 2, bosses: [{ name: "木傀", attack: 100, defense: 100, hp: 333, interval: 1.25, drops: [] }] },
        null,
      );
      const empty = await createOpsStage(db, { displayName: "山门", realmCode: 2, bosses: [] }, null);

      const before = await listOpsStages(db);
      expect(before.find((row) => row.id === armed.id)).toMatchObject({ recommendedPower: null, effectivePower: null, autoPower: null });
      expect(before.find((row) => row.id === armed.id)?.powerProblem?.startsWith("请先在后台填写：")).toBe(true);

      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "2",
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
        combat: {
          minInterval: 0.5,
          challengeCooldownSeconds: 0,
          timeLimitSeconds: 20,
          defenseConstant: 1,
          speedBase: 100,
          recommendedPowerMargin: 1.05,
        },
      });
      const after = await listOpsStages(db);
      expect(after.find((row) => row.id === armed.id)).toMatchObject({ recommendedPower: null, effectivePower: 1048, autoPower: 1048, powerProblem: null });
      expect(after.find((row) => row.id === empty.id)).toMatchObject({ recommendedPower: null, effectivePower: null, autoPower: null, powerProblem: null });

      // 手填的推荐战力优先，自动值只当参考
      await updateOpsStage(
        db,
        armed.id,
        { displayName: "后山", realmCode: 2, recommendedPower: 900, bosses: [{ name: "木傀", attack: 100, defense: 100, hp: 333, interval: 1.25, drops: [] }] },
        null,
      );
      const manual = await listOpsStages(db);
      expect(manual.find((row) => row.id === armed.id)).toMatchObject({ recommendedPower: 900, effectivePower: 900, autoPower: 1048 });
      // 不传这个字段的保存不会把手填值清掉
      await updateOpsStage(db, armed.id, { displayName: "后山", realmCode: 2, bosses: [{ name: "木傀", attack: 100, defense: 100, hp: 333, interval: 1.25, drops: [] }] }, null);
      expect((await listOpsStages(db)).find((row) => row.id === armed.id)).toMatchObject({ recommendedPower: 900 });
      await expect(
        updateOpsStage(db, armed.id, { displayName: "后山", realmCode: 2, recommendedPower: -5, bosses: [] }, null),
      ).rejects.toThrow();
      // 传 null = 恢复自动
      await updateOpsStage(db, armed.id, { displayName: "后山", realmCode: 2, recommendedPower: null, bosses: [{ name: "木傀", attack: 100, defense: 100, hp: 333, interval: 1.25, drops: [] }] }, null);
      expect((await listOpsStages(db)).find((row) => row.id === armed.id)).toMatchObject({ recommendedPower: null, effectivePower: 1048 });
    });
  });
});
