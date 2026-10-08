import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentReleases, items, skills } from "../../db/schema.js";
import { createAdmin, readSession, registerPlayer } from "../auth/service.js";
import { testAdmin } from "../../test/admin.js";
import { withDb } from "../../test/db.js";
import { ensureDraft, getPublishedRealm, publish, saveItem, saveRealm, saveSkill } from "./service.js";

const now = new Date("2026-10-06T09:00:00.000Z");

async function saveChain(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
  await saveRealm(db, "publisher", mortal);
  await saveRealm(db, "publisher", {
    ...mortal,
    slug: "qi_early",
    displayName: "炼气初期",
    sortOrder: 1,
    nextSlug: null,
  });
}

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

describe("content publish", () => {
  it("keeps the published name until publish", async () => {
    await withDb(async (db) => {
      await createAdmin(db, { username: "publisher", password: "admin-secret" });
      await saveChain(db);
      await publish(db, await testAdmin(db), now);
      await saveRealm(db, "publisher", { ...mortal, displayName: "凡人改" });
      expect((await getPublishedRealm(db, "mortal"))?.displayName).toBe("凡人");
      await publish(db, await testAdmin(db), now);
      const published = await getPublishedRealm(db, "mortal");
      expect(published?.displayName).toBe("凡人改");
      expect(published?.slug).toBe("mortal");
    });
  });

  it("rejects an empty name and leaves the published realm", async () => {
    await withDb(async (db) => {
      await saveChain(db);
      await publish(db, await testAdmin(db), now);
      await saveRealm(db, "publisher", { ...mortal, displayName: "" });
      await expect(publish(db, await testAdmin(db), now)).rejects.toThrow(/empty/);
      expect((await getPublishedRealm(db, "mortal"))?.displayName).toBe("凡人");
    });
  });

  it("copies a skill and an item into the published release", async () => {
    await withDb(async (db) => {
      await saveChain(db);
      await saveSkill(db, {
        slug: "heart_0",
        displayName: "吐纳",
        description: "基础心法",
        role: "heart",
        attack: 1,
        defense: 0,
        hp: 0,
        speed: 0,
        cultivateBonus: 0.1,
        minRealmOrder: 0,
      });
      await saveItem(db, {
        slug: "sword_0",
        displayName: "削木剑",
        description: "木剑",
        kind: "equipment",
        quality: "white",
        slot: "weapon",
        attack: 4,
        defense: 0,
        hp: 0,
        speed: 0,
      });
      await publish(db, await testAdmin(db), now);
      const [release] = await db
        .select()
        .from(contentReleases)
        .where(eq(contentReleases.status, "published"))
        .limit(1);
      const publishedSkills = await db.select().from(skills).where(eq(skills.releaseId, release!.id));
      const publishedItems = await db.select().from(items).where(eq(items.releaseId, release!.id));
      expect(publishedSkills.map((row) => row.slug)).toEqual(["heart_0"]);
      expect(publishedItems.map((row) => row.slug)).toEqual(["sword_0"]);
    });
  });

  it("rejects a player session on publish", async () => {
    await withDb(async (db) => {
      const player = await registerPlayer(db, { username: "walker", password: "correct-horse", now });
      const session = await readSession(db, player.token, now);
      expect(session?.actorType).toBe("player");
      await expect(
        publish(db, { id: player.playerId, name: "walker", actorType: "player" }, now),
      ).rejects.toThrow(/admin/);
      expect(await ensureDraft(db)).toBeTruthy();
    });
  });
});
