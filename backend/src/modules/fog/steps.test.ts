import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
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
import { loadCurrentWorld } from "../content/snapshot.js";
import { moveFog } from "./actions.js";
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
  let lastMove: unknown;
  const observed: Array<{
    path: string;
    id: string;
    status: string;
    points: number;
  }> = [];
  app.addHook("preSerialization", async (req, _reply, payload) => {
    const p = payload as {
      step?: { id: string; status: string };
      fog?: { travelPoints: number };
    };
    if (p?.step && p.fog)
      observed.push({
        path: req.url,
        id: p.step.id,
        status: p.step.status,
        points: p.fog.travelPoints,
      });
    return payload;
  });
  let pause: { entered: () => void; wait: Promise<void> } | undefined;
  app.addHook("preHandler", async (req) => {
    if (req.url.endsWith("/move")) lastMove = req.body;
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
    lastMove: () => lastMove as ReturnType<typeof body>,
    observed,
    setNow: (d: Date) => {
      clock = d;
    },
  };
}
async function waitForBlocked(
  db: Parameters<Parameters<typeof withDb>[0]>[0],
  count: number,
) {
  const end = Date.now() + 5000;
  while (Date.now() < end) {
    const rows = await db.execute(
      sql`select pid from pg_stat_activity where datname=current_database() and cardinality(pg_blocking_pids(pid))>0`,
    );
    if (rows.length >= count) return true;
    await new Promise<void>((r) => setTimeout(r, 5));
  }
  return false;
}
function godotProcess(
  config: object,
  dir: string,
  phase: string,
  server: string,
) {
  const configPath = join(dir, phase + ".json");
  writeFileSync(configPath, JSON.stringify(config), { mode: 0o600 });
  const child = spawn(
    process.env.FOG_RESTART_GODOT!,
    [
      "--headless",
      "--path",
      fileURLToPath(new URL("../../../../game", import.meta.url)),
      "res://tests/helpers/fog_restart_process.tscn",
    ],
    {
      env: {
        ...process.env,
        HOME: join(dir, "home"),
        XIUXIAN_UI_MOCK: "0",
        XIUXIAN_UPDATE_CHECK: "0",
        XIUXIAN_API_BASE: server,
        FOG_RESTART_CONFIG: configPath,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  let output = "";
  child.stdout.on("data", (b) => {
    output += String(b);
    writeFileSync(join(dir, phase + "-process.log"), output);
  });
  child.stderr.on("data", (b) => {
    output += String(b);
    writeFileSync(join(dir, phase + "-process.log"), output);
  });
  const exited = new Promise<number | null>((r) => child.on("exit", r));
  return {
    child,
    exited,
    output: () => output,
    wait: async (marker: string) => {
      const end = Date.now() + 15000;
      while (Date.now() < end) {
        if (output.includes(marker)) return;
        if (
          child.exitCode !== null ||
          child.signalCode !== null ||
          output.includes("SCRIPT ERROR")
        )
          break;
        await new Promise<void>((r) => setTimeout(r, 10));
      }
      throw new Error("Godot marker missing: " + marker + "; " + output);
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
        const provenWaiting = await waitForBlocked(db, 3);
        release();
        await holder;
        expect(provenWaiting).toBe(true);
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
        const provenWaiting = await waitForBlocked(db, 2);
        release();
        await holder;
        expect(provenWaiting).toBe(true);
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
  it("rejects a malformed primitive move body without an internal server error", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      try {
        const result = await f.app.inject({
          method: "POST",
          url: "/api/v1/me/fog/fog_wenxin_valley/move",
          headers: {
            ...f.headers,
            "content-type": "application/json",
            "idempotency-key": "malformed-body01",
          },
          payload: JSON.stringify("bad"),
        });
        expect(result.statusCode).toBe(400);
        expect((await f.get()).fog.travelPoints).toBe(200);
      } finally {
        await f.app.close();
      }
    }));
  it("does not refund a new-day move when a previous-day GET was proven waiting on the player lock", async () =>
    withDb(async (db) => {
      const f = await fixture(db);
      let release!: () => void;
      try {
        let acquired!: () => void;
        const held = new Promise<void>((r) => (acquired = r)),
          gate = new Promise<void>((r) => (release = r));
        const holder = db.transaction(async (tx) => {
          await tx
            .select()
            .from(playerStates)
            .where(eq(playerStates.playerId, f.player.playerId))
            .for("update");
          acquired();
          await gate;
          const world = await loadCurrentWorld(tx);
          const moved = await moveFog(
            tx,
            world!,
            f.player.playerId,
            "fog_wenxin_valley",
            { x: 3, y: 9 },
            new Date("2026-11-10T00:00:01+08:00"),
          );
          expect(moved.fog.travelPoints).toBe(199);
        });
        await held;
        f.setNow(new Date("2026-11-09T23:59:59+08:00"));
        const stale = f.get();
        const blocked = await waitForBlocked(db, 1);
        release();
        await holder;
        expect(blocked).toBe(true);
        const old = await stale;
        expect(old.fog.travelDay).toBe("2026-11-10");
        expect(old.fog.travelPoints).toBe(199);
        f.setNow(new Date("2026-11-10T00:00:02+08:00"));
        const fresh = await f.get();
        expect(fresh.fog.travelDay).toBe("2026-11-10");
        expect(fresh.fog.travelPoints).toBe(199);
      } finally {
        release?.();
        await f.app.close();
      }
    }));

  it.skipIf(!process.env.FOG_RESTART_GODOT)(
    "actual killed Godot process recovers the old step before a delayed original POST is released",
    async () =>
      withDb(async (db) => {
        const f = await fixture(db);
        const gate = f.pauseMove();
        let first: ReturnType<typeof godotProcess> | undefined;
        let second: ReturnType<typeof godotProcess> | undefined;
        try {
          const server = await f.app.listen({ host: "127.0.0.1", port: 0 });
          const dir = mkdtempSync(
            "/workspace/.deploy/fog-autowalk/restart-process-",
          );
          const config = {
            token: f.headers.authorization.slice(7),
            playerId: f.player.playerId,
            go: join(dir, "go"),
            output: join(dir, "final.json"),
            target: { x: 2, y: 10 },
          };
          first = godotProcess(
            { ...config, phase: "issue" },
            dir,
            "issue",
            server,
          );
          await Promise.race([gate.entered, first.wait("UNREACHABLE")]);
          const old = f.lastMove();
          expect(old.stepId).toBeTruthy();
          first.child.kill("SIGKILL");
          await first.exited;
          second = godotProcess(
            { ...config, phase: "recover" },
            dir,
            "recover",
            server,
          );
          await second.wait("RECOVERY_READY");
          const ledger = await db.execute(
            sql`select response from idempotency_keys where player_id=${f.player.playerId} and key=${"fog-step:" + old.stepId}`,
          );
          expect(ledger).toHaveLength(1);
          expect((ledger[0]?.response as { status: string })?.status).toBe(
            "cancelled",
          );
          gate.release();
          const deadline = Date.now() + 5000;
          while (
            !f.observed.some(
              (o) => o.path.endsWith("/move") && o.id === old.stepId,
            ) &&
            Date.now() < deadline
          )
            await new Promise<void>((r) => setTimeout(r, 5));
          expect(
            f.observed.find(
              (o) => o.path.endsWith("/move") && o.id === old.stepId,
            )?.status,
          ).toBe("cancelled");
          const beforeNew = await f.get();
          expect(beforeNew.fog.travelPoints).toBe(200);
          expect(beforeNew.fog.pos).toEqual({ x: 3, y: 10 });
          writeFileSync(config.go, "go");
          expect(await second.exited).toBe(0);
          const result = JSON.parse(readFileSync(config.output, "utf8"));
          expect(result.fog.pos).toEqual({ x: 2, y: 10 });
          expect(result.fog.travelPoints).toBe(199);
          expect(f.lastMove().stepId).not.toBe(old.stepId);
          expect((await f.move(old)).json().step.status).toBe("cancelled");
          writeFileSync(
            join(dir, "redacted-evidence.json"),
            JSON.stringify(
              {
                oldStepId: old.stepId,
                beforeNew: beforeNew.fog,
                final: result.fog,
                observed: f.observed,
              },
              null,
              2,
            ),
          );
          writeFileSync(
            join(dir, "evidence.log"),
            first.output() + "\nSECOND_PROCESS\n" + second.output(),
          );
        } finally {
          gate.release();
          first?.child.kill("SIGKILL");
          second?.child.kill("SIGKILL");
          await f.app.close();
        }
      }),
    30000,
  );

  it.skipIf(!process.env.FOG_RESTART_GODOT)(
    "actual restarted process freezes without network then reconciles a committed lost response once",
    async () =>
      withDb(async (db) => {
        const f = await fixture(db);
        let restartedApp: Awaited<ReturnType<typeof buildApp>> | undefined;
        let first: ReturnType<typeof godotProcess> | undefined;
        let offline: ReturnType<typeof godotProcess> | undefined;
        let recovered: ReturnType<typeof godotProcess> | undefined;
        try {
          const server = await f.app.listen({ host: "127.0.0.1", port: 0 });
          const dir = mkdtempSync(
            "/workspace/.deploy/fog-autowalk/restart-committed-",
          );
          const config = {
            token: f.headers.authorization.slice(7),
            playerId: f.player.playerId,
            go: join(dir, "go"),
            output: join(dir, "final.json"),
            target: { x: 3, y: 10 },
            recoverOnly: true,
          };
          first = godotProcess(
            { ...config, phase: "lost" },
            dir,
            "lost",
            server,
          );
          await first.wait("COMMITTED_RESPONSE_DROPPED");
          first.child.kill("SIGKILL");
          await first.exited;
          const old = f.lastMove();
          expect(old.stepId).toBeTruthy();
          const journalPath = join(
            dir,
            "home/.local/share/xiuxian/fog_pending_v1.json",
          );
          const before = JSON.parse(
            JSON.parse(readFileSync(journalPath, "utf8")).payload,
          ).slots;
          expect(
            Object.values(before).map(
              (r: unknown) => (r as { pending: boolean }).pending,
            ),
          ).toEqual([true]);
          await f.app.close();
          offline = godotProcess(
            { ...config, phase: "recover" },
            dir,
            "offline",
            server,
          );
          await offline.wait("RECOVERY_FROZEN");
          expect(await offline.exited).toBe(2);
          const frozen = JSON.parse(
            JSON.parse(readFileSync(journalPath, "utf8")).payload,
          ).slots;
          expect(
            Object.values(frozen).map(
              (r: unknown) => (r as { pending: boolean }).pending,
            ),
          ).toEqual([true]);
          restartedApp = await buildApp(db, () => now);
          restartedApp.addHook(
            "preSerialization",
            async (req, _reply, payload) => {
              const p = payload as {
                step?: { id: string; status: string };
                fog?: { travelPoints: number };
              };
              if (p?.step && p.fog)
                f.observed.push({
                  path: req.url,
                  id: p.step.id,
                  status: p.step.status,
                  points: p.fog.travelPoints,
                });
              return payload;
            },
          );
          await restartedApp.listen({
            host: "127.0.0.1",
            port: Number(new URL(server).port),
          });
          const probe = await fetch(server + "/api/v1/me/fog", {
            headers: f.headers,
          });
          expect(probe.status).toBe(200);
          await probe.arrayBuffer();
          recovered = godotProcess(
            { ...config, phase: "recover", normalMain: true },
            dir,
            "online",
            server,
          );
          await recovered.wait("RECOVERY_READY");
          expect(await recovered.exited).toBe(0);
          const result = JSON.parse(readFileSync(config.output, "utf8"));
          expect(result.fog.travelPoints).toBe(199);
          expect(result.fog.pos).toEqual({ x: 3, y: 9 });
          const final = JSON.parse(
            JSON.parse(readFileSync(journalPath, "utf8")).payload,
          ).slots;
          for (const r of Object.values(final) as Array<{
            pending: boolean;
            body: { stepId: string };
            terminal: { fog: { travelPoints: number } };
          }>) {
            expect(r.pending).toBe(false);
            expect(r.body.stepId).toBe(old.stepId);
            expect(r.terminal.fog.travelPoints).toBe(199);
          }
          const ledger = await db.execute(
            sql`select response from idempotency_keys where player_id=${f.player.playerId} and key=${"fog-step:" + old.stepId}`,
          );
          expect(ledger).toHaveLength(1);
          expect((ledger[0]?.response as { status: string }).status).toBe(
            "committed",
          );
          expect(
            f.observed.filter((o) => o.path.endsWith("/move")),
          ).toHaveLength(1);
          expect(
            f.observed.filter((o) => o.path.endsWith("/reconcile")),
          ).toHaveLength(1);
          writeFileSync(
            join(dir, "redacted-evidence.json"),
            JSON.stringify(
              {
                oldStepId: old.stepId,
                offlineExit: 2,
                final: result.fog,
                observed: f.observed,
              },
              null,
              2,
            ),
          );
        } finally {
          first?.child.kill("SIGKILL");
          offline?.child.kill("SIGKILL");
          recovered?.child.kill("SIGKILL");
          await restartedApp?.close();
          await f.app.close();
        }
      }),
    40000,
  );
  it.skipIf(!process.env.FOG_RESTART_GODOT)(
    "actual restarted accounts verify the token owner instead of stale account metadata and retain A until returning to A",
    async () =>
      withDb(async (db) => {
        const f = await fixture(db);
        const gate = f.pauseMove();
        const children: Array<ReturnType<typeof godotProcess>> = [];
        try {
          const b = await registerPlayer(db, {
            username: "fogstep_b",
            password: "local-test-only",
            now,
          });
          const loginB = await f.app.inject({
            method: "POST",
            url: "/api/v1/auth/login",
            payload: { username: "fogstep_b", password: "local-test-only" },
          });
          const server = await f.app.listen({ host: "127.0.0.1", port: 0 });
          const dir = mkdtempSync(
            "/workspace/.deploy/fog-autowalk/restart-accounts-",
          );
          const config = {
            token: f.headers.authorization.slice(7),
            playerId: f.player.playerId,
            go: join(dir, "go"),
            output: join(dir, "final.json"),
            target: { x: 3, y: 10 },
            recoverOnly: true,
          };
          const first = godotProcess(
            { ...config, phase: "issue" },
            dir,
            "issue-a",
            server,
          );
          children.push(first);
          await Promise.race([gate.entered, first.wait("UNREACHABLE")]);
          const old = f.lastMove();
          first.child.kill("SIGKILL");
          await first.exited;
          const second = godotProcess(
            {
              ...config,
              phase: "recover",
              token: loginB.json().token,
              playerId: b.playerId,
              resumeToken: true,
              allowStaleAccountCache: true,
            },
            dir,
            "recover-b-stale-cache-a",
            server,
          );
          children.push(second);
          await second.wait("RECOVERY_READY");
          expect(await second.exited).toBe(0);
          const journalPath = join(
            dir,
            "home/.local/share/xiuxian/fog_pending_v1.json",
          );
          const slots = JSON.parse(
            JSON.parse(readFileSync(journalPath, "utf8")).payload,
          ).slots;
          for (const record of Object.values(slots) as Array<{
            pending: boolean;
            identity: { playerId: string };
          }>) {
            expect(record.pending).toBe(true);
            expect(record.identity.playerId).toBe(f.player.playerId);
          }
          expect(
            await db.execute(
              sql`select key from idempotency_keys where player_id=${b.playerId} and key=${"fog-step:" + old.stepId}`,
            ),
          ).toHaveLength(0);
          const third = godotProcess(
            { ...config, phase: "recover", resumeToken: true },
            dir,
            "return-a",
            server,
          );
          children.push(third);
          await third.wait("RECOVERY_READY");
          expect(await third.exited).toBe(0);
          gate.release();
          const end = Date.now() + 5000;
          while (
            !f.observed.some(
              (o) => o.path.endsWith("/move") && o.id === old.stepId,
            ) &&
            Date.now() < end
          )
            await new Promise<void>((r) => setTimeout(r, 5));
          expect(
            f.observed.find(
              (o) => o.path.endsWith("/move") && o.id === old.stepId,
            )?.status,
          ).toBe("cancelled");
          const state = await f.get();
          expect(state.fog.travelPoints).toBe(200);
          expect(state.fog.pos).toEqual({ x: 3, y: 10 });
          writeFileSync(
            join(dir, "redacted-evidence.json"),
            JSON.stringify(
              {
                verifiedSeparateAccounts: true,
                oldStepId: old.stepId,
                foreignTombstones: 0,
                final: state.fog,
                observed: f.observed,
              },
              null,
              2,
            ),
          );
        } finally {
          gate.release();
          for (const c of children) c.child.kill("SIGKILL");
          await f.app.close();
        }
      }),
    30000,
  );
});
