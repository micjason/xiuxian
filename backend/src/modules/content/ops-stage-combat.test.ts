import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentStages } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { createOpsStage, listOpsStages, updateOpsStage } from "./ops-content.js";
import { applyPrototypeV12 } from "./prototype-v12.js";

const monsters = [{ name: "青鬃狼", attack: 24, defense: 14, hp: 110, interval: 1.5, killCultivation: 3 }];
// 和配置概览默认值（5%、70/25/5/0）只差白：只存白和掉率
const drop = { chancePercent: 4, weights: { white: 60, green: 25, blue: 5, purple: 0 } };

describe("stage admin API: monsters, monster drop, boss first-clear and repeat rewards", () => {
  it("creates and edits a stage with monsters + 5% drop + reward lists, returns them in the list, and keeps what an edit does not mention", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const created = await createOpsStage(
        db,
        {
          displayName: "试炼场",
          realmCode: 3,
          monsters,
          monsterDrop: drop,
          bosses: [
            {
              name: "试炼熊",
              attack: 40,
              defense: 20,
              hp: 1600,
              interval: 1.5,
              firstClear: [{ kind: "cultivation", amount: 1500 }, { kind: "item", itemId: "enh_stone_low", quantity: 3 }],
              repeat: { gear: true, extras: [{ itemId: "enh_stone_low", chancePercent: 70, minQty: 1, maxQty: 2 }] },
            },
          ],
        },
        null,
      );
      const [row] = await db.select().from(contentStages).where(eq(contentStages.slug, created.id));
      expect(row?.monsters).toEqual(monsters);
      expect(row?.monsterDrop).toEqual({ chanceBp: 400, qualityWeights: { white: 60 } });
      expect(row?.bosses[0]?.firstClear).toEqual([{ kind: "cultivation", amount: 1500 }, { kind: "item", itemSlug: "enh_stone_low", quantity: 3 }]);
      expect(row?.bosses[0]?.repeat).toEqual({ gear: true, extras: [{ itemSlug: "enh_stone_low", chanceBp: 7000, minQty: 1, maxQty: 2 }] });
      const listed = (await listOpsStages(db)).find((item) => item.id === created.id)!;
      expect(listed.monsters).toEqual(monsters);
      expect(listed.monsterDrop).toEqual({ chancePercent: 4, weights: { white: 60, green: null, blue: null, purple: null } });
      expect(listed.dropCustomCount).toBe(2);
      expect(listed.dropDefaults).toMatchObject({ chancePercent: 5, weights: { white: 70, green: 25, blue: 5, purple: 0 }, orangeChancePercent: 2 });
      expect(listed.bosses[0]?.firstClear[1]).toMatchObject({ kind: "item", itemId: "enh_stone_low", displayName: "突破石·下品" });
      // 只改首领数值：奖励、怪物、掉落都保持
      await updateOpsStage(db, created.id, { displayName: "试炼场", realmCode: 3, bosses: [{ name: "试炼熊", attack: 41, defense: 20, hp: 1700, interval: 1.5 }] }, null);
      const [after] = await db.select().from(contentStages).where(eq(contentStages.slug, created.id));
      expect(after?.bosses[0]).toMatchObject({ attack: 41, hp: 1700 });
      expect(after?.bosses[0]?.firstClear).toHaveLength(2);
      expect(after?.bosses[0]?.repeat?.gear).toBe(true);
      expect(after?.monsters).toEqual(monsters);
      expect(after?.monsterDrop?.chanceBp).toBe(400);
      // 显式清空
      await updateOpsStage(db, created.id, { displayName: "试炼场", realmCode: 3, monsters: [], monsterDrop: null, bosses: [{ name: "试炼熊", attack: 41, defense: 20, hp: 1700, interval: 1.5, firstClear: [], repeat: null }] }, null);
      const [cleared] = await db.select().from(contentStages).where(eq(contentStages.slug, created.id));
      expect(cleared?.monsters).toEqual([]);
      expect(cleared?.monsterDrop).toBeNull();
      expect(cleared?.bosses[0]?.firstClear).toBeUndefined();
    });
  });

  it("keeps the legacy scheme reward of a boss when an edit does not mention it", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      await db.update(contentStages).set({ bosses: [{ name: "老首领", attack: 1, defense: 1, hp: 10, interval: 1, drops: [], reward: { major: "major1", stageIndex: 0, nextMajor: null } }] }).where(eq(contentStages.slug, "lianqi_3"));
      await updateOpsStage(db, "lianqi_3", { displayName: "黑风岭·三", realmCode: 3, bosses: [{ name: "老首领", attack: 2, defense: 1, hp: 10, interval: 1 }] }, null);
      const [row] = await db.select().from(contentStages).where(eq(contentStages.slug, "lianqi_3"));
      expect(row?.bosses[0]?.reward).toEqual({ major: "major1", stageIndex: 0, nextMajor: null });
    });
  });

  it("rejects bad numbers with a Chinese message", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const make = (extra: Record<string, unknown>) => createOpsStage(db, { displayName: "坏的", realmCode: 1, ...extra } as never, null);
      await expect(make({ monsters: [{ name: "x", attack: 1, defense: 1, hp: 0, interval: 1, killCultivation: 3 }] })).rejects.toThrow("怪物气血和出手间隔必须大于 0");
      await expect(make({ monsters: [{ name: "x", attack: 1, defense: 1, hp: 5, interval: 1, killCultivation: 1.5 }] })).rejects.toThrow("击杀修为要填整数");
      await expect(make({ monsterDrop: { chancePercent: 101, weights: { white: 1 } } })).rejects.toThrow("不能超过 100%");
      await expect(make({ monsterDrop: { chancePercent: 5, weights: { white: 0, green: 0, blue: 0, purple: 0 } } })).rejects.toThrow("品质权重至少有一档大于 0");
      await expect(make({ monsterDrop: { chancePercent: 5, weights: { orange: 1 } } })).rejects.toThrow("橙装只由首领掉");
      await expect(make({ bosses: [{ name: "b", attack: 1, defense: 1, hp: 5, interval: 1, firstClear: [{ kind: "item", itemId: "nope", quantity: 1 }] }] })).rejects.toThrow("不存在");
      await expect(make({ bosses: [{ name: "b", attack: 1, defense: 1, hp: 5, interval: 1, firstClear: [{ kind: "cultivation", amount: 0.5 }] }] })).rejects.toThrow("整数");
      await expect(make({ bosses: [{ name: "b", attack: 1, defense: 1, hp: 5, interval: 1, repeat: { gear: true, extras: [{ itemId: "enh_stone_low", chancePercent: 5, minQty: 3, maxQty: 1 }] } }] })).rejects.toThrow("数量区间");
    });
  });
});
