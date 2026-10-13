import { hitDamage, simulateBattle } from "../combat/battle.js";
import { computePower, ratePower } from "../combat/stats.js";
import type { GameRules } from "./rules.js";

const STANDARD = { attack: 100, defense: 100, hp: 333, speed: 20 };
const PUPPETS = [
  { name: "均衡", attack: 100, defense: 100, hp: 333, speed: 20 },
  { name: "偏攻击", attack: 150, defense: 80, hp: 280, speed: 8 },
  { name: "偏速度", attack: 80, defense: 80, hp: 280, speed: 80 },
] as const;
const K_GRID = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3];
const DEFENSE_GRID = [0, 25, 50, 75, 100, 150, 200, 300];
const SPEED_GRID = [0, 10, 20, 40, 60, 80, 120];

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function intervalAt(speed: number, rules: GameRules): number {
  return computePower({
    attack: 0,
    defense: 0,
    hp: 0,
    speed,
    baseInterval: 1.5,
    minInterval: rules.minInterval,
    speedBase: rules.speedBase,
    weights: rules.powerWeights,
  }).interval;
}

function equalFight(defenseConstant: number, interval: number) {
  const side = { attack: STANDARD.attack, defense: STANDARD.defense, hp: STANDARD.hp, interval };
  return simulateBattle(side, side, { timeLimitSeconds: 180, defenseConstant });
}

function withValue(grid: number[], value: number): number[] {
  return [...new Set([...grid, round2(value)])].sort((left, right) => left - right);
}

function puppetPowers(weights: GameRules["powerWeights"], rules: GameRules) {
  const parts = [
    ["attack", "攻击"],
    ["defense", "防御"],
    ["hp", "气血"],
    ["speed", "速度"],
  ] as const;
  return PUPPETS.map((puppet) => ({
    name: puppet.name,
    attack: puppet.attack,
    defense: puppet.defense,
    hp: puppet.hp,
    speed: puppet.speed,
    interval: round2(intervalAt(puppet.speed, rules)),
    power: ratePower(puppet, weights),
    lines: parts.map(([key, label]) => ({
      key,
      label,
      stat: puppet[key],
      weight: weights[key],
      amount: round2(puppet[key] * weights[key]),
    })),
  }));
}

export function buildFormulaPreview(rules: GameRules) {
  const weights = rules.powerWeights;
  const interval = intervalAt(STANDARD.speed, rules);
  const fight = equalFight(rules.defenseConstant, interval);
  const doubledBase = intervalAt(STANDARD.speed, { ...rules, speedBase: rules.speedBase * 2 });
  const shares = (
    [
      ["attack", "攻击", STANDARD.attack * weights.attack],
      ["defense", "防御", STANDARD.defense * weights.defense],
      ["hp", "气血", STANDARD.hp * weights.hp],
      ["speed", "速度", STANDARD.speed * weights.speed],
    ] as const
  ).map(([key, label, amount]) => ({ key, label, amount: round2(amount), ratio: amount }));
  const shareTotal = shares.reduce((sum, row) => sum + row.ratio, 0);
  const doubledWeights = { ...weights, speed: weights.speed * 2 };
  return {
    defenseConstant: rules.defenseConstant,
    evenDamage: hitDamage(100, 100, rules.defenseConstant),
    doubledDamage: hitDamage(200, 200, rules.defenseConstant),
    fightSeconds: round2(fight.durationSeconds),
    damageCurve: DEFENSE_GRID.map((defense) => ({
      defense,
      damage: round2(hitDamage(100, defense, rules.defenseConstant)),
      raisedDamage: round2(hitDamage(100, defense, rules.defenseConstant * 1.5)),
    })),
    kCurve: withValue(K_GRID, rules.defenseConstant).map((k) => {
      const result = equalFight(k, interval);
      return { k, damage: round2(hitDamage(100, 100, k)), durationSeconds: round2(result.durationSeconds) };
    }),
    raisedK: {
      k: round2(rules.defenseConstant * 1.5),
      damage: round2(hitDamage(100, 100, rules.defenseConstant * 1.5)),
      durationSeconds: round2(equalFight(rules.defenseConstant * 1.5, interval).durationSeconds),
    },
    intervalAt20: round2(interval),
    raisedSpeedBase: { speedBase: round2(rules.speedBase * 2), intervalAt20: round2(doubledBase) },
    intervalCurve: SPEED_GRID.map((speed) => ({
      speed,
      interval: round2(intervalAt(speed, rules)),
      raisedInterval: round2(intervalAt(speed, { ...rules, speedBase: rules.speedBase * 2 })),
    })),
    minInterval: rules.minInterval,
    weights,
    standardPower: ratePower(STANDARD, weights),
    shares: shares.map((row) => ({ ...row, ratio: shareTotal === 0 ? 0 : row.ratio / shareTotal })),
    puppets: puppetPowers(weights, rules),
    speedWeightDoubled: {
      weight: round2(weights.speed * 2),
      puppets: puppetPowers(doubledWeights, rules),
    },
  };
}
