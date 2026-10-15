// 生成客户端演示模式（UiMock）和 GUT 测试用的原型数据集：真实服务器（原型 v1.2 内容）在每个境界的 /me/state（空装备）
// 和 /content/current。用法：cd backend && DATABASE_URL=... npx tsx src/scripts/gen-mock-dataset.ts
import { writeFileSync } from "node:fs";
import { eq } from "drizzle-orm";
import { buildApp } from "../app.js";
import { applyPrototypeV12 } from "../modules/content/prototype-v12.js";
import { playerStates } from "../db/schema.js";
import { withDb } from "../test/db.js";

const start = new Date("2026-10-08T03:00:00.000Z");
await withDb(async (db) => {
  await applyPrototypeV12(db);
  const app = await buildApp(db, () => start, { randomInt: () => 9999 });
  const registered = await app.inject({ method: "POST", url: "/api/v1/auth/register", payload: { username: "mockdata_a", password: "correct-horse" } });
  const body = registered.json() as { token: string; player?: { id: string }; playerId?: string };
  const headers = { authorization: `Bearer ${body.token}` };
  const first = (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json() as { playerId: string };
  const content = (await app.inject({ method: "GET", url: "/api/v1/content/current", headers })).json() as { realms: { slug: string }[] };
  const realms: Record<string, unknown> = {};
  for (const realm of content.realms) {
    await db.update(playerStates).set({ realmSlug: realm.slug }).where(eq(playerStates.playerId, first.playerId));
    const state = (await app.inject({ method: "GET", url: "/api/v1/me/state", headers })).json() as Record<string, unknown>;
    for (const key of ["playerId", "contentVersion", "stages", "lastSettle", "offlineReport", "items", "skills", "wave"]) {
      delete state[key];
    }
    realms[realm.slug] = state;
  }
  writeFileSync(new URL("../../../game/resources/mock/prototype_dataset.json", import.meta.url), JSON.stringify({ content, realms }));
  console.log("wrote prototype_dataset.json", Object.keys(realms).length, "realms");
  await app.close();
});
