import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z");

describe("GET /me/state: breakthrough.preview (what the breakthrough flow screen shows as 'after')", () => {
  it("previews the next realm with the same gear: stats, power, per-second cultivation, ultimate, new stages; null at the top", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const app = await buildApp(db, () => start, { randomInt: () => 9999 });
      const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "preview_a", password: "correct-horse" } });
      const headers = { authorization: `Bearer ${registered.json().token as string}` };
      const state = (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json();
      const preview = state.breakthrough.preview;
      expect(state.breakthrough.nextSlug).toBe("lianqi_2");
      expect(preview.realmName).toBe("炼气二层");
      expect(preview.power).toBeGreaterThan(state.power);
      expect(preview.attack).toBeGreaterThan(state.attack);
      expect(preview.gainPerTick).toBeGreaterThanOrEqual(1);
      expect(preview.ult).toMatchObject({ multBp: 40000 });
      expect(Array.isArray(preview.newStages)).toBe(true);
      await app.close();
    });
  });
});
