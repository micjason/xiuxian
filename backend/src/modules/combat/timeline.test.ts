import { describe, it, expect } from "vitest";
import { simulateBattle, hitDamage, toCombatSkills } from "./battle.js";
const p = { attack: 10, defense: 0, hp: 10000, interval: 1 };
const b = { attack: 1, defense: 0, hp: 10000, interval: 1 };
const cfg = { timeLimitSeconds: 150, defenseConstant: 1 };
describe("authoritative complete timeline", () => {
  it("never casts a skill left in a closed running slot", () => {
    expect(toCombatSkills([{ skillSlug: "closed", runningSlot: "run_3" }], [{ slug: "closed", displayName: "closed", enabled: true }], 2)).toEqual([]);
  });
  it("never truncates middle events", () => {
    const result = simulateBattle(p, b, cfg);
    expect(result.log).toHaveLength(300);
    expect(result.log[200].t).toBe(101);
  });
  it("records guaranteed crit and dodge with authoritative HP snapshots", () => {
    const result = simulateBattle({ ...p, critChanceBp: 10000, critMultBp: 20000 }, { ...b, dodgeChanceBp: 0 }, { ...cfg, timeLimitSeconds: 1 });
    expect(result.log[0]).toMatchObject({ kind: "attack", critical: true, damage: 20, playerHpAfter: 10000, targetHpAfter: 9980 });
    const miss = simulateBattle(p, { ...b, dodgeChanceBp: 10000 }, { ...cfg, timeLimitSeconds: 1 });
    expect(miss.log[0]).toMatchObject({ dodged: true, damage: 0, targetHpAfter: 10000 });
  });
  it("applies and expires attack/defense/heal/shield states", () => {
    const result = simulateBattle({ ...p, hp: 100 }, { ...b, attack: 20, defense: 10 }, { ...cfg, timeLimitSeconds: 4 }, [{
      slug: "state", name: "护体", castMode: "auto", castEveryAttacks: 99, damageMultBp: 0,
      effects: [{ kind: "attack_up", valueBp: 10000, durationSeconds: 2 }, { kind: "defense_down", valueBp: 5000, durationSeconds: 2 }, { kind: "heal", valueBp: 5000 }, { kind: "shield", valueBp: 3000, durationSeconds: 2 }],
    }]);
    const skill = result.log.find(e => e.kind === "skill")!;
    expect(skill.statuses?.map(e => e.kind)).toEqual(expect.arrayContaining(["attack_up", "defense_down", "shield"]));
    expect(result.log.find(e => e.side === "boss")?.absorbed).toBe(20);
    expect(result.log.find(e => e.t === 2 && e.side === "player")?.damage).toBeCloseTo(hitDamage(20, 5, 1));
    expect(result.log.find(e => e.t === 3 && e.side === "player")?.damage).toBeCloseTo(hitDamage(10, 10, 1));
    expect(result.log.find(e => e.t === 3 && e.side === "player")?.statuses).toEqual([]);
  });
  it("heals after taking damage and keeps shield absorption out of health damage", () => {
    const result = simulateBattle({ ...p, hp: 100 }, { ...b, attack: 20, interval: 0.5 }, { ...cfg, timeLimitSeconds: 1 }, [{ slug: "heal", name: "疗伤", castMode: "auto", castEveryAttacks: 4, damageMultBp: 0, effects: [{ kind: "heal", valueBp: 3000 }] }]);
    expect(result.log.find(e => e.kind === "skill")).toMatchObject({ healed: 20, playerHpAfter: 100 });
  });
  it("rejects zero attack intervals rather than hanging the server", () => {
    expect(() => simulateBattle({ ...p, interval: 0 }, b, cfg)).toThrow("Invalid battle side");
  });
  it("casts full rage automatically and never accepts manual taps", () => {
    const result = simulateBattle(p, b, { ...cfg, timeLimitSeconds: 3, rage: { max: 100, onAttack: 50, onHit: 0, damageMultBp: 30000 } });
    expect(result.log.find(e => e.kind === "ult")).toMatchObject({ t: 2, damage: 30, rageAfter: 0 });
  });
  it("retains the existing every-N rotating-skill schedule", () => {
    const skills = [2, 3].map((every, i) => ({ slug: `s${i}`, name: `s${i}`, castMode: "auto" as const, castEveryAttacks: every, damageMultBp: 10000 }));
    const result = simulateBattle(p, b, { ...cfg, timeLimitSeconds: 5 }, skills);
    expect(result.log.filter(e => e.kind === "skill").map(e => [e.skillSlug, e.t])).toEqual([["s0",1],["s1",4],["s0",5]]);
  });
});

// Independent numeric premise of boss-time-limit e2e (no DB required).
describe("default rage time-limit boundary", () => {
  const player = { attack: 10, defense: 10, hp: 1000, interval: 1.5 };
  const boss = { attack: 1, defense: 0, hp: 200, interval: 5 };
  const run = (timeLimitSeconds: number) => simulateBattle(player, boss, {
    timeLimitSeconds, defenseConstant: 1,
    rage: { max: 100, onAttack: 20, onHit: 10, damageMultBp: 30000 },
  });
  it("wins at 21 with fourteen attacks and two rage strikes, not at 20", () => {
    expect(run(20)).toMatchObject({ win: false, reason: "timeout", durationSeconds: 20 });
    const battle = run(21);
    expect(battle).toMatchObject({ win: true, reason: "win", durationSeconds: 21 });
    expect(battle.log.filter(e => e.side === "player" && e.kind === "attack")).toHaveLength(14);
    expect(battle.log.filter(e => e.kind === "ult").map(e => [e.t, e.damage])).toEqual([[7.5, 30], [15, 30]]);
  });
});
