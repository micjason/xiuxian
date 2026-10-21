import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { equipmentGrants, playerItems, players } from "../../db/schema.js";
import { insertEquipment, withDb } from "../../test/db.js";
import { contentItems } from "../../db/schema.js";
import { AppError } from "../../shared/errors.js";
import { grantEquipment, GRANT_SOURCES, type GrantEquipmentInput } from "./grant.js";

type Db = Parameters<Parameters<typeof withDb>[0]>[0];

async function setup(db: Db) {
  const [player] = await db.insert(players).values({ username: "g1", usernameLower: "g1", passwordHash: "x" }).returning();
  const gear = await insertEquipment(db, { displayName: "青云剑", attack: 18 });
  await db.insert(contentItems).values({ slug: "enh_stone_low", displayName: "突破石·下品", kind: "material", stackable: true });
  return { playerId: player!.id, itemId: gear.id };
}

const code = async (promise: Promise<unknown>) => {
  try {
    await promise;
  } catch (error) {
    return error instanceof AppError ? error.code : String(error);
  }
  return "OK";
};

describe("grantEquipment (ADMIN_SPEC §14)", () => {
  it("creates one non-stacked instance per count with the given source and writes one grant log row", async () => {
    await withDb(async (db) => {
      const { playerId, itemId } = await setup(db);
      const rows = await db.transaction((tx) =>
        grantEquipment(tx, { playerId, itemId, count: 3, source: "admin_grant", sourceRef: "B-1", requestId: "r-1", operator: "owner", reason: "补偿 · 服务器故障", note: "工单 42" }),
      );
      expect(rows).toHaveLength(3);
      expect(new Set(rows.map((row) => row.id)).size).toBe(3);
      for (const row of rows) {
        expect(row).toMatchObject({ playerId, itemSlug: itemId, isStack: false, quantity: 1, source: "admin_grant", equippedSlot: null, enhanceLevel: 0 });
      }
      const log = await db.select().from(equipmentGrants);
      expect(log).toHaveLength(1);
      expect(log[0]).toMatchObject({ requestId: "r-1", playerId, itemSlug: itemId, count: 3, source: "admin_grant", sourceRef: "B-1", operator: "owner", reason: "补偿 · 服务器故障", note: "工单 42" });
      expect(log[0]!.instanceIds).toEqual(rows.map((row) => row.id));
    });
  });

  it("is idempotent on requestId: a repeat returns the same instances and grants nothing new; a different grant under the same requestId is rejected", async () => {
    await withDb(async (db) => {
      const { playerId, itemId } = await setup(db);
      const input: GrantEquipmentInput = { playerId, itemId, count: 2, source: "boss_first", sourceRef: "lianqi_3", requestId: "boss_first:p:lianqi_3" };
      const first = await db.transaction((tx) => grantEquipment(tx, input));
      const again = await db.transaction((tx) => grantEquipment(tx, input));
      expect(again.map((row) => row.id)).toEqual(first.map((row) => row.id));
      expect(await db.select().from(playerItems).where(eq(playerItems.playerId, playerId))).toHaveLength(2);
      expect(await db.select().from(equipmentGrants)).toHaveLength(1);

      expect(await code(db.transaction((tx) => grantEquipment(tx, { ...input, count: 3 })))).toBe("GRANT_REQUEST_CONFLICT");
      expect(await code(db.transaction((tx) => grantEquipment(tx, { ...input, source: "boss_repeat" })))).toBe("GRANT_REQUEST_CONFLICT");

      // 发出去的装备后来被分解了：重复请求仍然不补发，只返回还在的
      await db.delete(playerItems).where(eq(playerItems.id, first[0]!.id));
      const later = await db.transaction((tx) => grantEquipment(tx, input));
      expect(later.map((row) => row.id)).toEqual([first[1]!.id]);
      expect(await db.select().from(playerItems)).toHaveLength(1);
    });
  });

  it("concurrent calls with the same requestId grant only once", async () => {
    await withDb(async (db) => {
      const { playerId, itemId } = await setup(db);
      const input: GrantEquipmentInput = { playerId, itemId, count: 1, source: "stage_drop", requestId: "race-1" };
      const results = await Promise.all(Array.from({ length: 5 }, () => db.transaction((tx) => grantEquipment(tx, input))));
      const ids = new Set(results.flat().map((row) => row.id));
      expect(ids.size).toBe(1);
      expect(await db.select().from(playerItems)).toHaveLength(1);
    });
  });

  it("ignores bag capacity (overflow allowed) and never auto-decomposes", async () => {
    await withDb(async (db) => {
      const { playerId, itemId } = await setup(db);
      await db.transaction((tx) => grantEquipment(tx, { playerId, itemId, count: 25, source: "mail", requestId: "big" }));
      expect(await db.select().from(playerItems).where(eq(playerItems.playerId, playerId))).toHaveLength(25);
    });
  });

  it("rolls back with the caller's transaction (no items, no log, requestId reusable)", async () => {
    await withDb(async (db) => {
      const { playerId, itemId } = await setup(db);
      await expect(
        db.transaction(async (tx) => {
          await grantEquipment(tx, { playerId, itemId, count: 2, source: "event", requestId: "rb" });
          throw new Error("caller failed");
        }),
      ).rejects.toThrow("caller failed");
      expect(await db.select().from(playerItems)).toHaveLength(0);
      expect(await db.select().from(equipmentGrants)).toHaveLength(0);
      expect(await db.transaction((tx) => grantEquipment(tx, { playerId, itemId, count: 2, source: "event", requestId: "rb" }))).toHaveLength(2);
    });
  });

  it("validates input without breaking the caller's transaction", async () => {
    await withDb(async (db) => {
      const { playerId, itemId } = await setup(db);
      const base: GrantEquipmentInput = { playerId, itemId, count: 1, source: "admin_grant", requestId: "v" };
      const cases: [Partial<GrantEquipmentInput>, string][] = [
        [{ requestId: "  " }, "INVALID_INPUT"],
        [{ count: 0 }, "INVALID_INPUT"],
        [{ count: 1.5 }, "INVALID_INPUT"],
        [{ count: 101 }, "INVALID_INPUT"],
        [{ source: "shop" as never }, "INVALID_INPUT"],
        [{ playerId: "not-a-uuid" }, "INVALID_INPUT"],
        [{ playerId: "00000000-0000-4000-8000-000000000000" }, "NOT_FOUND"],
        [{ itemId: "gear_nope" }, "NOT_FOUND"],
        [{ itemId: "enh_stone_low" }, "NOT_EQUIPMENT"],
      ];
      for (const [patch, want] of cases) {
        // 同一个事务里先校验失败、再正常发放：校验失败不能把事务弄坏
        const result = await db.transaction(async (tx) => {
          const got = await code(grantEquipment(tx, { ...base, ...patch }));
          const rows = await grantEquipment(tx, { ...base, requestId: `ok-${want}-${JSON.stringify(patch)}` });
          return { got, rows };
        });
        expect(result.got, JSON.stringify(patch)).toBe(want);
        expect(result.rows).toHaveLength(1);
      }
      expect(await db.select().from(equipmentGrants).where(eq(equipmentGrants.requestId, "v"))).toHaveLength(0);
    });
  });

  it("source enum matches ADMIN_SPEC §14 and the migration's CHECK constraint; 0027 runs after 0026", () => {
    expect([...GRANT_SOURCES].sort()).toEqual(["admin_grant", "boss_first", "boss_repeat", "event", "mail", "stage_drop"]);
    const sqlText = readFileSync(new URL("../../../drizzle/0027_equipment_grants.sql", import.meta.url), "utf8");
    for (const source of GRANT_SOURCES) {
      expect(sqlText).toContain(`'${source}'`);
    }
    const journal = JSON.parse(readFileSync(new URL("../../../drizzle/meta/_journal.json", import.meta.url), "utf8")) as { entries: { idx: number; tag: string; when: number }[] };
    const entry = journal.entries.find((row) => row.tag === "0027_equipment_grants")!;
    expect(entry.idx).toBe(27);
    expect(entry.when).toBeGreaterThan(1793190000000);
    expect(entry.when).toBeLessThan(1795000000000);
    const later = journal.entries.filter((row) => row.idx > entry.idx);
    expect(later.every((row) => row.when > entry.when)).toBe(true);
  });

  it("the database rejects a source outside the enum and count < 1", async () => {
    await withDb(async (db) => {
      const { playerId, itemId } = await setup(db);
      await expect(db.insert(equipmentGrants).values({ requestId: "x1", playerId, itemSlug: itemId, count: 1, source: "shop" })).rejects.toThrow();
      await expect(db.insert(equipmentGrants).values({ requestId: "x2", playerId, itemSlug: itemId, count: 0, source: "mail" })).rejects.toThrow();
    });
  });
});
