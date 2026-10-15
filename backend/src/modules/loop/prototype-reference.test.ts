import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { withDb } from "../../test/db.js";
import { waveCycle } from "../combat/wave.js";
import { applyPrototypeV12, PROTOTYPE_LAYERS } from "../content/prototype-v12.js";
import { loadCurrentWorld } from "../content/snapshot.js";
import { readGameRules } from "../content/rules.js";
import { combatStats } from "./actions.js";

type Sim = {
  referenceLoadouts: Record<string, [string, string, number][]>;
  tableClaims: { referenceStats: Record<string, { hp: number; attack: number; defense: number; speed: number; interval: number; power: number }> };
  stageClaims: Record<string, { avgKill: number; killSeconds: number }>;
  killsPerHourClaims: Record<string, number>;
};
const sim = JSON.parse(readFileSync(new URL("../../../../tools/sim/prototype-v1.2.config.json", import.meta.url), "utf8")) as Sim;
const majorIds = ["qi", "foundation", "core"];

describe("server pipeline vs the design table (reference configuration)", () => {
  it("combat stats of the reference gear through the real server code match table 2.1; wave pacing and kills/hour match table 2.2/2.5", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const world = (await loadCurrentWorld(db))!;
      const rules = readGameRules(world);
      const perMajor: Record<string, number[]> = { qi: [], foundation: [], core: [] };
      for (const [index, layer] of PROTOTYPE_LAYERS.entries()) {
        const major = majorIds[layer.major]!;
        const items = sim.referenceLoadouts[major]!.map(([slot, quality, level]) => ({ slug: `gear_major${layer.major * 3 + 1}_${slot}_${quality}`, enhanceLevel: level }));
        const stats = combatStats(world, layer.slug, items, []);
        const claim = sim.tableClaims.referenceStats[layer.slug]!;
        expect(Math.round(stats.hp), `${layer.slug} hp`).toBe(claim.hp);
        expect(Math.round(stats.attack), `${layer.slug} attack`).toBe(claim.attack);
        expect(Math.round(stats.defense), `${layer.slug} defense`).toBe(claim.defense);
        expect(stats.speed, `${layer.slug} speed`).toBeCloseTo(claim.speed, 0);
        expect(stats.interval, `${layer.slug} interval`).toBeCloseTo(claim.interval, 2);
        expect(Math.abs(stats.power - claim.power), `${layer.slug} power`).toBeLessThanOrEqual(Math.max(2, claim.power * 0.005));
        const stage = world.stages[index]!;
        const monster = stage.monsters![0]!;
        const cycle = waveCycle(
          { hp: stats.hp, attack: stats.attack, defense: stats.defense, interval: stats.interval },
          monster,
          { waveSize: rules.waveSize, transitionSeconds: rules.waveTransitionSeconds, reviveSeconds: rules.reviveSeconds, defenseConstant: rules.defenseConstant },
        );
        expect(cycle.deaths).toBe(0);
        expect(cycle.cycleSeconds / rules.waveSize, `${layer.slug} avg kill interval`).toBeCloseTo(sim.stageClaims[layer.slug]!.avgKill, 1);
        perMajor[major]!.push((3600 / cycle.cycleSeconds) * cycle.kills);
      }
      // 表 2.5：每小时前台击杀数（每个大境界取三层的平均）
      for (const major of majorIds) {
        const values = perMajor[major]!;
        const average = values.reduce((sum, value) => sum + value, 0) / values.length;
        expect(average, `${major} kills per hour`).toBeGreaterThan(sim.killsPerHourClaims[major]! * 0.95);
        expect(average, `${major} kills per hour`).toBeLessThan(sim.killsPerHourClaims[major]! * 1.05);
        // 4% 掉率 → 约每小时 30–35 件
        const gear = average * 0.04;
        expect(gear, `${major} gear per hour`).toBeGreaterThan(29);
        expect(gear, `${major} gear per hour`).toBeLessThan(36);
      }
    });
  });
});
