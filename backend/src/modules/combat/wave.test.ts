import { describe, expect, it } from "vitest";
import { advanceWaves, waveCycle } from "./wave.js";
import { rewardDayKey } from "../progress/day.js";

const cfg = { waveSize: 3, transitionSeconds: 2, reviveSeconds: 3, defenseConstant: 1 };
// table v1.2 6.1 / 2.2: 炼气一层 reference gear vs 青鬃狼
const player = { hp: 373, attack: 55, defense: 53, interval: 1.21 };
const wolf = { hp: 110, attack: 24, defense: 14, interval: 1.5 };

describe("waveCycle", () => {
  it("matches the design table for 炼气一层 (cycle 12.9 s ≈ 4.31 s per kill, 3 kills, no deaths)", () => {
    const cycle = waveCycle(player, wolf, cfg);
    expect(cycle.kills).toBe(3);
    expect(cycle.deaths).toBe(0);
    expect(cycle.cycleSeconds / 3).toBeCloseTo(4.31, 1);
    expect(cycle.events.map((event) => event.kind)).toEqual(["kill", "kill", "kill"]);
    // 每只单独计时，第一只约 3.6 秒
    expect(cycle.events[0]!.t).toBeCloseTo(3.63, 1);
    expect(cycle.minHpPct).toBeGreaterThan(80);
    expect(cycle.minHpPct).toBeLessThan(95);
  });

  it("is deterministic and carries HP between monsters but refills on the transition", () => {
    const first = waveCycle(player, wolf, cfg);
    expect(waveCycle(player, wolf, cfg)).toEqual(first);
    const longer = waveCycle(player, wolf, { ...cfg, transitionSeconds: 10 });
    expect(longer.cycleSeconds - first.cycleSeconds).toBeCloseTo(8, 9);
    expect(longer.kills).toBe(first.kills);
  });

  it("a monster the player cannot beat gives deaths + revive time and zero kills", () => {
    const brute = { hp: 100000, attack: 400, defense: 10, interval: 1 };
    const cycle = waveCycle(player, brute, cfg);
    expect(cycle.kills).toBe(0);
    expect(cycle.deaths).toBe(3);
    expect(cycle.events.every((event) => event.kind === "death")).toBe(true);
    // 每只死亡后复活 3 秒
    expect(cycle.cycleSeconds).toBeGreaterThan(3 * 3 + 2);
  });
});

describe("advanceWaves", () => {
  const cycle = waveCycle(player, wolf, cfg);

  it("counts nothing before the first kill and keeps the partial progress", () => {
    const a = advanceWaves(0, 3, cycle);
    expect(a.kills).toBe(0);
    expect(a.progress).toBeCloseTo(3, 9);
    const b = advanceWaves(a.progress, 1, cycle);
    expect(b.kills).toBe(1); // 3.63 秒处第 1 只被击杀
  });

  it("splitting the elapsed time into 3 s polls gives the same kills as one big step (no lost kills)", () => {
    const total = 15 * 60;
    const whole = advanceWaves(0, total, cycle);
    let progress = 0;
    let kills = 0;
    let deaths = 0;
    for (let at = 0; at < total; at += 3) {
      const step = advanceWaves(progress, 3, cycle);
      progress = step.progress;
      kills += step.kills;
      deaths += step.deaths;
    }
    expect(kills).toBe(whole.kills);
    expect(deaths).toBe(whole.deaths);
    expect(whole.progress).toBeCloseTo(progress, 6);
    // 与设计表一致：约每小时 800+ 只（4.31 秒/只）
    expect((whole.kills / total) * 3600).toBeGreaterThan(780);
    expect((whole.kills / total) * 3600).toBeLessThan(860);
  });

  it("any split of the same total time gives the same kills, deaths and death streak (also with deaths in the cycle)", () => {
    const mixed = waveCycle({ hp: 240, attack: 40, defense: 20, interval: 1.2 }, { hp: 150, attack: 60, defense: 10, interval: 1 }, cfg);
    expect(mixed.kills).toBeGreaterThan(0);
    expect(mixed.deaths).toBeGreaterThan(0);
    let state = 7;
    const rand = () => {
      state = (state * 48271) % 2147483647;
      return state / 2147483647;
    };
    for (const wave of [cycle, mixed]) {
      for (let trial = 0; trial < 30; trial += 1) {
        const pieces = Array.from({ length: 1 + Math.floor(rand() * 12) }, () => rand() * wave.cycleSeconds * 2.5);
        const total = pieces.reduce((sum, piece) => sum + piece, 0);
        const whole = advanceWaves(0, total, wave, 0);
        let progress = 0;
        let row = 0;
        let kills = 0;
        let deaths = 0;
        for (const piece of pieces) {
          const step = advanceWaves(progress, piece, wave, row);
          progress = step.progress;
          row = step.deathsInRow;
          kills += step.kills;
          deaths += step.deaths;
        }
        expect([kills, deaths, row]).toEqual([whole.kills, whole.deaths, whole.deathsInRow]);
        expect(progress).toBeCloseTo(whole.progress, 6);
      }
    }
  });

  it("tracks consecutive deaths and resets on a kill", () => {
    const brute = { hp: 100000, attack: 400, defense: 10, interval: 1 };
    const bad = waveCycle(player, brute, cfg);
    const run = advanceWaves(0, bad.cycleSeconds * 2, bad, 1);
    expect(run.deaths).toBe(6);
    expect(run.deathsInRow).toBe(7);
    const good = advanceWaves(0, cycle.cycleSeconds, cycle, 5);
    expect(good.kills).toBe(3);
    expect(good.deathsInRow).toBe(0);
  });

  it("ignores zero or negative elapsed and degenerate cycles", () => {
    expect(advanceWaves(1.5, 0, cycle)).toEqual({ kills: 0, deaths: 0, progress: 1.5, deathsInRow: 0 });
    expect(advanceWaves(1.5, 10, { ...cycle, cycleSeconds: 0 }).kills).toBe(0);
  });
});

describe("rewardDayKey (Beijing time, day starts at dayStartHour)", () => {
  it("04:59 still belongs to the previous day, 05:00 starts the new one", () => {
    expect(rewardDayKey(new Date("2026-10-15T20:59:59Z"), 5)).toBe("2026-10-15"); // 北京 10-16 04:59:59
    expect(rewardDayKey(new Date("2026-10-15T21:00:00Z"), 5)).toBe("2026-10-16"); // 北京 10-16 05:00
    expect(rewardDayKey(new Date("2026-10-16T15:59:59Z"), 5)).toBe("2026-10-16"); // 北京 10-16 23:59:59
    expect(rewardDayKey(new Date("2026-10-16T16:00:00Z"), 0)).toBe("2026-10-17");
  });
});
