import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Tx } from "../../db/tx.js";
import type { ContentSnapshot } from "../content/validate.js";
const stage = vi.hoisted(() => vi.fn());
const fog = vi.hoisted(() => vi.fn());
vi.mock("../loop/actions.js", () => ({ challengeStage: stage, withIdempotency: vi.fn() }));
vi.mock("../fog/actions.js", () => ({ battleFog: fog }));
import { startCombat, finishCombat, recoverCombat } from "./sessions.js";
const battle = { win: true, reason: "win", durationSeconds: 20, log: [{ t: 1, side: "player", kind: "attack", damage: 10, targetHpAfter: 0 }] };
const playback = { player: { hp: 100 }, monster: { hp: 10 }, timeLimitSeconds: 45, canSkip: false, speeds: [1,2,3] };
const world = { version: 0, globals: { startingRealmSlug: "r" } } as ContentSnapshot & { version: number };
const now = new Date("2026-11-08T04:00:00Z");
function fakeTx() {
  let stored: { response: Record<string, unknown> } | undefined;
  const tx = {
    select: (fields?: Record<string, unknown>) => {
      let pending = false;
      const chain = { from: () => chain, where: () => chain, for: async () => [], orderBy: () => { pending = true; return chain; }, limit: async () => fields ? [] : stored && (!pending || !stored.response.acknowledged) ? [structuredClone(stored)] : [] };
      return chain;
    },
    insert: () => ({ values: async (row: { response: Record<string, unknown> }) => { stored = structuredClone(row); } }),
    update: () => ({ set: (patch: { response: Record<string, unknown> }) => ({ where: async () => { if (stored) stored.response = structuredClone(patch.response); } }) }),
  };
  return tx as unknown as Tx;
}
beforeEach(() => {
  stage.mockReset(); fog.mockReset();
  stage.mockImplementation(async (_tx, _world, _player, _slug, _now, _rng, options) => ({ battle: options.resolvedBattle ?? structuredClone(battle), playback, drops: options.preview || options.resolvedBattle?.win === false ? [] : [{ itemSlug: "reward", quantity: 1 }] }));
  fog.mockImplementation(async (_tx, _world, _player, _map, _input, _now, options) => ({ ...structuredClone(options.resolvedBattle ?? battle), playback, fog: { pos: { x: 3, y: 9 }, revealed: ["3,9"] }, gained: options.preview || options.resolvedBattle?.win === false ? [] : [{ itemSlug: "herb", quantity: 1 }] }));
});
describe("durable shared battle session orchestration (in-memory journal double)", () => {
  it("returns the same pending timeline on repeated start without rolling another fight", async () => {
    const tx = fakeTx();
    const a = await startCombat(tx, world, "p", { source: "stage", stageSlug: "s" }, now, () => 0);
    const b = await startCombat(tx, world, "p", { source: "stage", stageSlug: "s" }, now, () => 0);
    expect(a.combatId).toBe(b.combatId);
    expect(stage).toHaveBeenCalledTimes(1);
    expect(a.result).toBeNull();
  });
  it("recovers precomputed outcome and grants once even after repeated reconnect", async () => {
    const tx = fakeTx();
    await startCombat(tx, world, "p", { source: "stage", stageSlug: "s" }, now, () => 0);
    const first = await recoverCombat(tx, "p", now, () => 0);
    const second = await recoverCombat(tx, "p", now, () => 0);
    expect(first?.result).toEqual(second?.result);
    expect(stage).toHaveBeenCalledTimes(2); // one preview, one grant; no second grant on reconnect
    expect(stage.mock.calls[1][6]).toMatchObject({ resolvedBattle: battle, resume: true });
  });
  it("retreat on fog is a failed no-loot result and carries the exact map origin", async () => {
    const tx = fakeTx();
    const start = await startCombat(tx, world, "p", { source: "fog", mapId: "map", objectId: "event" }, now, () => 0);
    const done = await finishCombat(tx, "p", start.combatId, "retreat", now, () => 0);
    expect(done.result).toMatchObject({ battle: { win: false, reason: "retreat" }, drops: [], fog: { pos: { x: 3, y: 9 }, revealed: ["3,9"] } });
    expect(fog).toHaveBeenCalledTimes(2);
    expect(stage).not.toHaveBeenCalled();
  });
});
