import { ratePower } from "../combat/stats.js";

const STANDARD = { attack: 100, defense: 100, hp: 333, speed: 20 };
const LABELS = { attack: "攻击", defense: "防御", hp: "气血", speed: "速度" } as const;
const KEYS = ["attack", "defense", "hp", "speed"] as const;
const LEAN = 0.08;

export type StatKey = (typeof KEYS)[number];

export type StatBlock = Record<StatKey, number>;

export type PowerLine = { key: StatKey; label: string; stat: number; weight: number; amount: number };

export type PowerShare = { key: StatKey; label: string; ratio: number; standardRatio: number };

export type PowerDetail = {
  lines: PowerLine[];
  total: number;
  power: number;
  shares: PowerShare[];
};

export type BuildDescription = PowerDetail & {
  tendency: string;
  note: string;
};

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function describeBuild(stats: StatBlock, weights: StatBlock): BuildDescription {
  const lines = KEYS.map((key) => ({
    key,
    label: LABELS[key],
    stat: stats[key],
    weight: weights[key],
    amount: round2(stats[key] * weights[key]),
  }));
  const total = KEYS.reduce((sum, key) => sum + stats[key] * weights[key], 0);
  const standardTotal = KEYS.reduce((sum, key) => sum + STANDARD[key] * weights[key], 0);
  const shares = KEYS.map((key) => ({
    key,
    label: LABELS[key],
    ratio: total === 0 ? 0 : (stats[key] * weights[key]) / total,
    standardRatio: standardTotal === 0 ? 0 : (STANDARD[key] * weights[key]) / standardTotal,
  }));
  const leans = shares
    .filter((share) => share.ratio - share.standardRatio > LEAN)
    .sort((left, right) => right.ratio - right.standardRatio - (left.ratio - left.standardRatio));
  const tendency = total === 0 ? "算不出" : leans.length === 0 ? "均衡" : leans.map((share) => `偏${share.label}`).join("、");
  const compared = shares
    .map((share) => `${share.label}占 ${Math.round(share.ratio * 100)}%，标准角色占 ${Math.round(share.standardRatio * 100)}%`)
    .join("。");
  return {
    lines,
    total: round2(total),
    power: ratePower(stats, weights),
    shares,
    tendency,
    note: `${compared}。某一项比标准角色高出 8 个百分点以上，就记为偏好那一项。都没有，记为均衡。标准角色是攻击 100、防御 100、气血 333、速度 20。`,
  };
}

export function statsAtPower(target: number, shares: StatBlock, weights: StatBlock): StatBlock {
  const stats = Object.fromEntries(KEYS.map((key) => [key, round2((target * shares[key]) / weights[key])])) as StatBlock;
  for (let step = 0; step < 500 && ratePower(stats, weights) !== target; step += 1) {
    stats.attack = round2(stats.attack + (ratePower(stats, weights) < target ? 0.01 : -0.01));
  }
  if (ratePower(stats, weights) !== target) {
    throw new Error(`配不出战力 ${target}`);
  }
  return stats;
}
