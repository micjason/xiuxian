import path from "node:path";
import { describe, expect, it } from "vitest";
import { withDb } from "../test/db.js";
import { loadDraftSnapshot, publishSnapshot } from "../modules/content/snapshot.js";
import { validateContent } from "../modules/content/validate.js";
import { importLegacyContent } from "./import-legacy.js";

describe("importLegacyContent", () => {
  it("loads the mortal realm and the first sword from the game config", async () => {
    await withDb(async (db) => {
      const root = path.resolve(process.cwd(), "../game/resources/config");
      await importLegacyContent(db, path.join(root, "idle_rules.json"), path.join(root, "adventure.json"));
      const draft = await loadDraftSnapshot(db);
      expect(draft.realms.find((realm) => realm.slug === "mortal")?.gainPerTick).toBe(2);
      expect(draft.items.some((item) => item.slug === "sword_0")).toBe(true);
      expect(draft.globals.startingRealmSlug).toBe("mortal");
      expect(draft.stages.find((stage) => stage.slug === "grove")?.bossHp).toBeGreaterThan(0);
      expect(draft.dropTables.some((table) => table.slug === "drop_grove_boss")).toBe(true);
      expect(draft.dropTables.find((table) => table.slug === "drop_grove_first")?.entries.length).toBeGreaterThan(0);
      const checked = validateContent(draft);
      expect(checked.errors).toEqual([]);
      const published = await publishSnapshot(db, "种子", null, new Date("2026-10-08T00:00:00.000Z"));
      expect(published.version).toBe(1);
    });
  });
});
