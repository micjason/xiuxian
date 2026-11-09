/** Local-only capture fixtures. Not imported by production server. */
import { writeFileSync } from "node:fs";
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { eq } from "drizzle-orm";
import { buildApp } from "../app.js";
import * as schema from "../db/schema.js";
import {
  contentRealms,
  contentGlobals,
  contentItems,
  playerFogRuns,
} from "../db/schema.js";
import { DEFAULT_FOG, isBlocked, cellKey } from "../modules/fog/config.js";
import { registerPlayer } from "../modules/auth/service.js";
import { loadCurrentWorld } from "../modules/content/snapshot.js";
import { readFogState } from "../modules/fog/actions.js";
import { withTransaction } from "../db/tx.js";
const url = process.env.DATABASE_URL ?? "";
if (
  process.env.FOG_AUTOWALK_LOCAL !== "1" ||
  url !== "postgres://box@127.0.0.1:55439/xiuxian_fog_autowalk_local"
)
  throw new Error("private capture database required");
const sql = postgres(url);
const db = drizzle(sql, { schema });
async function seedWorld(db: import("../modules/operations/record.js").Db) {
  await db.insert(contentRealms).values({
    slug: "1",
    displayName: "凡人",
    majorName: "炼气",
    majorKey: "qi",
    sortOrder: 0,
    nextRealmSlug: null,
    baseAttack: 20,
    baseDefense: 5,
    baseHp: 200,
    baseSpeed: 10,
    baseInterval: 1.2,
    gainPerTick: 1,
  });
  await db.insert(contentGlobals).values({
    id: 1,
    startingRealmSlug: "1",
    offlineCapSeconds: 3600,
    bagCapacity: 40,
    fog: DEFAULT_FOG,
    powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
    combat: {
      minInterval: 0.5,
      defenseConstant: 1,
      recommendedPowerMargin: 1.05,
      challengeCooldownSeconds: 0,
      timeLimitSeconds: 30,
      speedBase: 100,
    },
  });
  await db
    .insert(contentItems)
    .values([
      {
        slug: "herb_lingcao",
        displayName: "灵草",
        kind: "material",
        quality: "green",
        stackable: true,
      },
      {
        slug: "herb_qingxin",
        displayName: "清心草",
        kind: "material",
        quality: "blue",
        stackable: true,
      },
    ] as never)
    .onConflictDoNothing();
}

if (!(await db.select().from(contentGlobals).limit(1))[0]) await seedWorld(db);
if (
  !(
    await db
      .select()
      .from(schema.players)
      .where(eq(schema.players.username, "fogcapture"))
  )[0]
)
  await registerPlayer(db, {
    username: "fogcapture",
    password: "local-capture-only",
    now: new Date(),
  });
const [player] = await db
  .select()
  .from(schema.players)
  .where(eq(schema.players.username, "fogcapture"));
const app = await buildApp(db);
app.post("/__fog_fixture/:scenario", async (req) => {
  const world = (await loadCurrentWorld(db))!;
  await withTransaction(db, (tx) =>
    readFogState(tx, world, player!.id, undefined, new Date()),
  );
  const scenario = (req.params as { scenario: string }).scenario;
  const map = DEFAULT_FOG.maps[0]!;
  const all: string[] = [];
  for (let y = 0; y < map.rows; y++)
    for (let x = 0; x < map.cols; x++)
      if (!isBlocked(map, x, y)) all.push(cellKey(x, y));
  let revealed =
    scenario === "guard"
      ? all.filter((k) => k !== "4,0")
      : all.filter((k) => Number(k.split(",")[1]) >= 4);
  if (scenario === "spawn") revealed = ["3,10", "2,10", "4,10", "3,9", "3,11"];
  await db
    .update(playerFogRuns)
    .set({
      posC: scenario === "guard" ? 4 : 3,
      posR: scenario === "guard" ? 2 : 10,
      revealed,
      objects: { __travel_budget_v2: { opened: true } },
      travelPoints: 200,
    })
    .where(eq(playerFogRuns.playerId, player!.id));
  return withTransaction(db, (tx) =>
    readFogState(tx, world, player!.id, undefined, new Date()),
  );
});
const login = await app.inject({
  method: "POST",
  url: "/api/v1/auth/login",
  payload: { username: "fogcapture", password: "local-capture-only" },
});
writeFileSync(
  "/workspace/.deploy/fog-autowalk/capture-session",
  login.json().token as string,
  { mode: 0o600 },
);
await app.listen({ host: "127.0.0.1", port: 18083 });
console.log("Private fog capture API ready at 127.0.0.1:18083");
