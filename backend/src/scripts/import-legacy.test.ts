import path from "node:path";
import { describe, expect, it } from "vitest";
import { withDb } from "../test/db.js";
import { loadDraftSnapshot } from "../modules/content/snapshot.js";
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
    });
  });
});
