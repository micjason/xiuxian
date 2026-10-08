import { describe, expect, it } from "vitest";
import { withDb } from "../../test/db.js";
import { updateDraftSettings } from "./pack.js";
import { diffDraft, publish, saveRealm } from "./service.js";

const now = new Date("2026-10-06T12:00:00.000Z");
const mortal = {
  slug: "mortal",
  displayName: "凡人",
  sortOrder: 0,
  gainPerSecond: 2,
  breakthroughCost: 360,
  nextSlug: "qi_early",
  attack: 10,
  defense: 6,
  hp: 50,
  speed: 0,
};

describe("diffDraft", { timeout: 20_000 }, () => {
  it("lists a name change and hides it after publish", async () => {
    await withDb(async (db) => {
      await saveRealm(db, "publisher", mortal);
      await saveRealm(db, "publisher", { ...mortal, slug: "qi_early", displayName: "炼气初期", sortOrder: 1, nextSlug: null });
      await publish(db, { id: "unused", name: "publisher" }, now);
      await saveRealm(db, "publisher", { ...mortal, displayName: "凡人改" });
      const pending = await diffDraft(db);
      expect(pending.changes).toEqual([
        { kind: "realm", slug: "mortal", field: "displayName", before: "凡人", after: "凡人改" },
      ]);
      await publish(db, { id: "unused", name: "publisher" }, now);
      const clean = await diffDraft(db);
      expect(clean.changes).toEqual([]);
    });
  });

  it("shows an offline cap change in hours worth of seconds", async () => {
    await withDb(async (db) => {
      await saveRealm(db, "publisher", mortal);
      await saveRealm(db, "publisher", { ...mortal, slug: "qi_early", displayName: "炼气初期", sortOrder: 1, nextSlug: null });
      await publish(db, { id: "unused", name: "publisher" }, now);
      await updateDraftSettings(db, { offlineCapSeconds: 4 * 3600 });
      const pending = await diffDraft(db);
      expect(pending.offlineCapSeconds).toBe(4 * 3600);
      expect(pending.changes).toEqual([
        expect.objectContaining({
          kind: "settings",
          field: "offlineCapSeconds",
          before: 28800,
          after: 4 * 3600,
        }),
      ]);
    });
  });
});
