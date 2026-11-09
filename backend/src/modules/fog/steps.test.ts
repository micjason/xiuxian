import { describe, it, expect } from "vitest";
import { eq, sql } from "drizzle-orm";
import { buildApp } from "../../app.js";
import { withDb } from "../../test/db.js";
import {
  contentRealms,
  contentGlobals,
  contentItems,
  playerFogRuns,
  playerStates,
} from "../../db/schema.js";
import { registerPlayer } from "../auth/service.js";
import { DEFAULT_FOG, isBlocked, cellKey } from "./config.js";
const now = new Date("2026-11-09T22:43:00+08:00");
async function seedWorld(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
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
  await db.insert(contentItems).values([
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
  ] as never);
}

async function fixture(db: Parameters<Parameters<typeof withDb>[0]>[0]) {
  await seedWorld(db);
  const player = await registerPlayer(db, {
    username: "fogstep",
    password: "correct-horse",
    now,
  });
  let clock = now;
  const app = await buildApp(db, () => clock);
  let pause: { entered: () => void; wait: Promise<void> } | undefined;
  app.addHook("preHandler", async (req) => {
    if (req.url.endsWith("/move") && pause) {
      const p = pause;
      pause = undefined;
      p.entered();
      await p.wait;
    }
  });
  const pauseMove = () => {
    let enter!: () => void;
    let release!: () => void;
    const entered = new Promise<void>((r) => {
      enter = r;
    });
    const wait = new Promise<void>((r) => {
      release = r;
    });
    pause = { entered: enter, wait };
    return { entered, release };
  };
  const login = await app.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: { username: "fogstep", password: "correct-horse" },
  });
  const headers = { authorization: `Bearer ${login.json().token as string}` };
  const get = async () =>
    (
      await app.inject({ method: "GET", url: "/api/v1/me/fog", headers })
    ).json();
  const state = await get();
  const body = (id: string, x = 3, y = 9) => ({
    protocol: "fog-step-v1",
    stepId: id,
    expectedRevision: state.fog.revision,
    expectedFrom: state.fog.pos,
    x,
    y,
  });
  const move = async (payload: ReturnType<typeof body>) =>
    app.inject({
      method: "POST",
      url: "/api/v1/me/fog/fog_wenxin_valley/move",
      headers: { ...headers, "idempotency-key": payload.stepId },
      payload,
    });
  const reconcile = async (payload: ReturnType<typeof body>) =>
    app.inject({
      method: "POST",
      url: "/api/v1/me/fog/fog_wenxin_valley/reconcile",
      headers,
      payload,
    });
  return {
    app,
    player,
    get,
    state,
    body,
    move,
    reconcile,
    headers,
    pauseMove,
    setNow: (d: Date) => {
      clock = d;
    },
  };
}
describe("fog-step-v1 HTTP terminal protocol", () => {
  it("advertises protocol and revision, leaving legacy move compatible", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        expect(f.state.fog.protocol).toBe("fog-step-v1");
        expect(f.state.fog.revision).toMatch(/^[a-f0-9]{64}$/);
        const r = await f.app.inject({
          method: "POST",
          url: "/api/v1/me/fog/fog_wenxin_valley/move",
          headers: { ...f.headers, "idempotency-key": "legacy-step-0001" },
          payload: { x: 3, y: 9 },
        });
        expect(r.statusCode).toBe(200);
        expect(r.json().fog.travelPoints).toBe(199);
      } finally {
        await f.app.close();
      }
    }));
  it("cancels an unexecuted step and refuses its late original POST", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        const b = f.body("cancel-step-0001");
        const cancelled = await f.reconcile(b);
        expect(cancelled.statusCode).toBe(200);
        expect(cancelled.json().step.status).toBe("cancelled");
        const late = await f.move(b);
        expect(late.json().step.status).toBe("cancelled");
        expect(late.json().fog.pos).toEqual({ x: 3, y: 10 });
        expect(late.json().fog.travelPoints).toBe(200);
      } finally {
        await f.app.close();
      }
    }));
  it("reconciles committed response loss without charging twice or returning old state", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        const b = f.body("commit-step-0001");
        expect((await f.move(b)).json().step.status).toBe("committed");
        const r = await f.reconcile(b);
        expect(r.json().step.status).toBe("committed");
        expect(r.json().fog.pos).toEqual({ x: 3, y: 9 });
        expect(r.json().fog.travelPoints).toBe(199);
        expect((await f.move(b)).json().fog.travelPoints).toBe(199);
        const current = await f.get();
        const newer = {
          ...f.body("commit-step-0002", 3, 8),
          expectedRevision: current.fog.revision,
          expectedFrom: current.fog.pos,
        };
        expect((await f.move(newer)).json().step.status).toBe("committed");
        expect((await f.move(b)).json().fog.pos).toEqual({ x: 3, y: 8 });
        const mismatch = await f.move({ ...b, x: 2, y: 10 });
        expect(mismatch.statusCode).toBe(400);
      } finally {
        await f.app.close();
      }
    }));
  it("serializes duplicate and stale different-key requests with an actual player-lock barrier", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        let release!: () => void;
        let acquired!: () => void;
        const locked = new Promise<void>((r) => {
          acquired = r;
        });
        const gate = new Promise<void>((r) => {
          release = r;
        });
        const holder = db.transaction(async (tx) => {
          await tx
            .select()
            .from(playerStates)
            .where(eq(playerStates.playerId, f.player.playerId))
            .for("update");
          acquired();
          await gate;
        });
        await locked;
        const a = f.body("parallel-step-001");
        const pending = [
          f.move(a),
          f.move(a),
          f.move(f.body("parallel-step-002", 2, 10)),
        ];
        release();
        await holder;
        const results = await Promise.all(pending);
        expect(results.map((r) => r.statusCode)).toEqual([200, 200, 200]);
        const statuses = results.map((r) => r.json().step.status);
        expect(statuses[0]).toBe(statuses[1]);
        expect([statuses[0], statuses[2]].sort()).toEqual([
          "committed",
          "rejected",
        ]);
        const state = await f.get();
        expect(state.fog.travelPoints).toBe(199);
      } finally {
        await f.app.close();
      }
    }));
  it("rejects unknown, object traversal, zero budget and stale revisions with no charge", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        expect(
          (await f.move(f.body("unknown-step-001", 3, 8))).json().step.status,
        ).toBe("rejected");
        await db
          .update(playerFogRuns)
          .set({
            posC: 3,
            posR: 9,
            revealed: ["3,9", "4,9"],
            travelPoints: 200,
          })
          .where(eq(playerFogRuns.playerId, f.player.playerId));
        let state = await f.get();
        let b = {
          ...f.body("object-step-0001", 4, 9),
          expectedRevision: state.fog.revision,
          expectedFrom: state.fog.pos,
        };
        expect((await f.move(b)).json().step.status).toBe("rejected");
        await db
          .update(playerFogRuns)
          .set({ travelPoints: 0 })
          .where(eq(playerFogRuns.playerId, f.player.playerId));
        state = await f.get();
        b = {
          ...f.body("empty-step-00001", 3, 10),
          expectedRevision: state.fog.revision,
          expectedFrom: state.fog.pos,
        };
        expect((await f.move(b)).json().step.status).toBe("rejected");
        expect((await f.get()).fog.travelPoints).toBe(0);
      } finally {
        await f.app.close();
      }
    }));
  it("barriers a delayed original POST: plain GET is not terminal, reconcile cancels before new move", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        const b = f.body("delayed-step-001");
        const gate = f.pauseMove();
        const original = f.move(b);
        await gate.entered;
        const old = await f.get();
        expect(old.fog.pos).toEqual({ x: 3, y: 10 });
        expect((await f.reconcile(b)).json().step.status).toBe("cancelled");
        const successor = await f.move(f.body("successor-step-1", 2, 10));
        expect(successor.json().step.status).toBe("committed");
        gate.release();
        expect((await original).json().step.status).toBe("cancelled");
        const state = await f.get();
        expect(state.fog.pos).toEqual({ x: 2, y: 10 });
        expect(state.fog.travelPoints).toBe(199);
      } finally {
        await f.app.close();
      }
    }));
  it("GET cannot refresh stale-day budget while another transaction holds the player lock", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      let release!: () => void;
      try {
        await db
          .update(playerFogRuns)
          .set({ travelDay: "2026-11-08", travelPoints: 0 })
          .where(eq(playerFogRuns.playerId, f.player.playerId));
        let acquired!: () => void;
        const locked = new Promise<void>((r) => {
          acquired = r;
        });
        const gate = new Promise<void>((r) => {
          release = r;
        });
        const holder = db.transaction(async (tx) => {
          await tx
            .select()
            .from(playerStates)
            .where(eq(playerStates.playerId, f.player.playerId))
            .for("update");
          acquired();
          await gate;
        });
        await locked;
        const pending = f.get();
        const until = Date.now() + 3000;
        let blocked = false;
        while (Date.now() < until) {
          const rows = await db.execute(
            sql`select pid from pg_stat_activity where datname=current_database() and cardinality(pg_blocking_pids(pid))>0`,
          );
          if (rows.length) {
            blocked = true;
            break;
          }
          await new Promise<void>((r) => setImmediate(r));
        }
        expect(blocked).toBe(true);
        release();
        await holder;
        const fresh = await pending;
        expect(fresh.fog.travelPoints).toBe(200);
        const b = {
          ...f.body("after-day-step-1"),
          expectedRevision: fresh.fog.revision,
          expectedFrom: fresh.fog.pos,
        };
        expect((await f.move(b)).json().fog.travelPoints).toBe(199);
        expect((await f.get()).fog.travelPoints).toBe(199);
      } finally {
        release?.();
        await f.app.close();
      }
    }));
  it("uses configured step cost rather than guessing one and rejects invalid protocol", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        const fog = structuredClone(DEFAULT_FOG);
        fog.travelCostPerStep = 2;
        await db
          .update(contentGlobals)
          .set({ fog })
          .where(eq(contentGlobals.id, 1));
        await db
          .update(playerFogRuns)
          .set({ travelPoints: 1 })
          .where(eq(playerFogRuns.playerId, f.player.playerId));
        const current = await f.get();
        const b = {
          ...f.body("cost-two-step-01"),
          expectedRevision: current.fog.revision,
        };
        const rejected = await f.move(b);
        expect(rejected.json().step.status).toBe("rejected");
        expect(rejected.json().fog.travelPoints).toBe(1);
        expect((await f.move({ ...b, protocol: "unknown" })).statusCode).toBe(
          400,
        );
      } finally {
        await f.app.close();
      }
    }));
  it("preserves explicit prefull guard movement to 79/79, then requires battle confirmation", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        const map = DEFAULT_FOG.maps[0]!;
        const all: string[] = [];
        for (let y = 0; y < map.rows; y++)
          for (let x = 0; x < map.cols; x++)
            if (!isBlocked(map, x, y) && cellKey(x, y) !== "4,0")
              all.push(cellKey(x, y));
        await db
          .update(playerFogRuns)
          .set({ posC: 4, posR: 2, revealed: all })
          .where(eq(playerFogRuns.playerId, f.player.playerId));
        const before = await f.get();
        expect(before.fog.exploreRevealed).toBe(78);
        const step = {
          ...f.body("guard-prefull-01", 4, 1),
          expectedRevision: before.fog.revision,
          expectedFrom: before.fog.pos,
        };
        const result = (await f.move(step)).json();
        expect(result.step.status).toBe("committed");
        expect(result.fog.exploreRevealed).toBe(79);
        expect(result.fog.exploreFull).toBe(true);
        const next = {
          ...f.body("guard-full-step1", 4, 0),
          expectedRevision: result.fog.revision,
          expectedFrom: result.fog.pos,
        };
        expect((await f.move(next)).json().step.status).toBe("committed");
        const state = await f.get();
        const enterFull = {
          ...f.body("guard-full-step2", 4, 1),
          expectedRevision: state.fog.revision,
          expectedFrom: state.fog.pos,
        };
        expect((await f.move(enterFull)).json().step.status).toBe("rejected");
      } finally {
        await f.app.close();
      }
    }));
  it("serializes two first GETs without duplicate run creation", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        await db
          .delete(playerFogRuns)
          .where(eq(playerFogRuns.playerId, f.player.playerId));
        const states = await Promise.all([f.get(), f.get()]);
        for (const state of states) expect(state.fog.travelPoints).toBe(200);
        expect(
          (
            await db
              .select()
              .from(playerFogRuns)
              .where(eq(playerFogRuns.playerId, f.player.playerId))
          ).length,
        ).toBe(1);
      } finally {
        await f.app.close();
      }
    }));
  it("legacy budget upgrade and explicit chest interaction retain each other's progress", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        await db
          .update(playerFogRuns)
          .set({
            posC: 3,
            posR: 9,
            revealed: ["3,9", "4,9"],
            objects: {},
            travelPoints: 17,
          })
          .where(eq(playerFogRuns.playerId, f.player.playerId));
        let release!: () => void;
        let acquired!: () => void;
        const locked = new Promise<void>((r) => {
          acquired = r;
        });
        const gate = new Promise<void>((r) => {
          release = r;
        });
        const holder = db.transaction(async (tx) => {
          await tx
            .select()
            .from(playerStates)
            .where(eq(playerStates.playerId, f.player.playerId))
            .for("update");
          acquired();
          await gate;
        });
        await locked;
        const reading = f.get();
        const opening = f.app.inject({
          method: "POST",
          url: "/api/v1/me/fog/fog_wenxin_valley/interact",
          headers: { ...f.headers, "idempotency-key": "budget-open-once" },
          payload: { objectId: "c_near" },
        });
        release();
        await holder;
        await reading;
        expect((await opening).statusCode).toBe(200);
        const state = await f.get();
        expect(state.fog.travelPoints).toBe(197);
        expect(
          state.fog.objects.find((o: { id: string }) => o.id === "c_near")
            .opened,
        ).toBe(true);
        const [row] = await db
          .select()
          .from(playerFogRuns)
          .where(eq(playerFogRuns.playerId, f.player.playerId));
        expect(
          (row!.objects as Record<string, { opened: boolean }>)
            .__travel_budget_v2?.opened,
        ).toBe(true);
      } finally {
        await f.app.close();
      }
    }));
});
