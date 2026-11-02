/**
 * 洞府傀儡产线：肉底座 + 木/草/石；仓满不进账；肉空其它停产；离线按 settledAt 结算。
 * 公式写死在此；后台只改 config.puppet 数字。
 */
import type { DongfuPuppetConfig, DongfuPuppetLineId } from "./config.js";

export const PUPPET_LINES: DongfuPuppetLineId[] = ["meat", "wood", "herb", "stone"];

export type PuppetLineState = {
  level: number;
  workers: number;
  stored: number;
};

export type PuppetProgressState = {
  settledAt: string;
  lines: Record<DongfuPuppetLineId, PuppetLineState>;
};

export type PuppetLineDto = {
  id: DongfuPuppetLineId;
  level: number;
  workers: number;
  stored: number;
  storageCap: number;
  prodPerWorker: number;
  eatMeatPerWorker: number;
  netPerHour: number;
  stoppedReason: "" | "meat_empty" | "storage_full";
  upgradeCost: number;
  canUpgrade: boolean;
};

export type PuppetDto = {
  total: number;
  maxCount: number;
  idle: number;
  hireCostMeat: number;
  canHire: boolean;
  meatStarved: boolean;
  lines: PuppetLineDto[];
  settledAt: string;
};

function lineCfg(config: DongfuPuppetConfig, id: DongfuPuppetLineId) {
  return config.lines[id];
}

export function storageCap(config: DongfuPuppetConfig, id: DongfuPuppetLineId, level: number): number {
  const base = lineCfg(config, id).storageBase;
  const lv = Math.max(1, Math.floor(level));
  return Math.max(1, Math.floor(base * Math.pow(config.storageUpgradeMult, lv - 1)));
}

export function upgradeCostOf(config: DongfuPuppetConfig, id: DongfuPuppetLineId, level: number): number {
  const cfg = lineCfg(config, id);
  const recommended = id === "meat" ? 6 : 2;
  return Math.max(1, Math.ceil(recommended * cfg.prodPerWorker * config.upgradeCostHoursOfProd));
}

export function defaultPuppetProgress(config: DongfuPuppetConfig, now: Date): PuppetProgressState {
  const assign = config.defaultAssign;
  return {
    settledAt: now.toISOString(),
    lines: {
      meat: { level: 1, workers: assign.meat, stored: Math.min(config.lines.meat.storageBase, 80) },
      wood: { level: 1, workers: assign.wood, stored: 0 },
      herb: { level: 1, workers: assign.herb, stored: 0 },
      stone: { level: 1, workers: assign.stone, stored: 0 },
    },
  };
}

export function normalizePuppetProgress(
  raw: unknown,
  config: DongfuPuppetConfig,
  servantTotal: number,
  now: Date,
): PuppetProgressState {
  if (!raw || typeof raw !== "object") {
    const fresh = defaultPuppetProgress(config, now);
    // 按开局傀儡数裁剪默认派工
    let used = PUPPET_LINES.reduce((n, id) => n + fresh.lines[id].workers, 0);
    if (used > servantTotal) {
      for (const id of [...PUPPET_LINES].reverse()) {
        while (used > servantTotal && fresh.lines[id].workers > 0) {
          fresh.lines[id].workers -= 1;
          used -= 1;
        }
      }
    }
    return fresh;
  }
  const input = raw as Record<string, unknown>;
  const linesRaw = (input.lines && typeof input.lines === "object" ? input.lines : {}) as Record<string, unknown>;
  const lines = {} as Record<DongfuPuppetLineId, PuppetLineState>;
  for (const id of PUPPET_LINES) {
    const row = (linesRaw[id] && typeof linesRaw[id] === "object" ? linesRaw[id] : {}) as Record<string, unknown>;
    lines[id] = {
      level: Math.max(1, Math.floor(Number(row.level) || 1)),
      workers: Math.max(0, Math.floor(Number(row.workers) || 0)),
      stored: Math.max(0, Number(row.stored) || 0),
    };
  }
  const settledAt =
    typeof input.settledAt === "string" && input.settledAt ? input.settledAt : now.toISOString();
  return { settledAt, lines };
}

/** 按小时结算；肉先产再被吃；肉空则非肉线本段产量为 0；仓满截断。 */
export function settlePuppetLines(
  state: PuppetProgressState,
  config: DongfuPuppetConfig,
  now: Date,
): PuppetProgressState {
  const prev = new Date(state.settledAt).getTime();
  const t = now.getTime();
  if (!Number.isFinite(prev) || t <= prev) {
    return { ...state, settledAt: now.toISOString(), lines: { ...state.lines } };
  }
  const hours = (t - prev) / 3_600_000;
  if (hours <= 0) {
    return { ...state, settledAt: now.toISOString(), lines: { ...state.lines } };
  }

  const next: Record<DongfuPuppetLineId, PuppetLineState> = {
    meat: { ...state.lines.meat },
    wood: { ...state.lines.wood },
    herb: { ...state.lines.herb },
    stone: { ...state.lines.stone },
  };

  // 肉产量
  const meatCap = storageCap(config, "meat", next.meat.level);
  const meatGain = next.meat.workers * config.lines.meat.prodPerWorker * hours;
  next.meat.stored = Math.min(meatCap, next.meat.stored + meatGain);

  // 吃肉需求（木草石）
  let meatNeed = 0;
  for (const id of ["wood", "herb", "stone"] as const) {
    meatNeed += next[id].workers * config.lines[id].eatMeatPerWorker * hours;
  }

  const meatAvailable = next.meat.stored;
  const meatFactor = meatNeed <= 0 ? 1 : Math.min(1, meatAvailable / meatNeed);
  next.meat.stored = Math.max(0, next.meat.stored - meatNeed * meatFactor);

  for (const id of ["wood", "herb", "stone"] as const) {
    const cap = storageCap(config, id, next[id].level);
    if (next[id].stored >= cap - 1e-9) {
      next[id].stored = cap;
      continue;
    }
    const gain = next[id].workers * config.lines[id].prodPerWorker * hours * meatFactor;
    next[id].stored = Math.min(cap, next[id].stored + gain);
  }

  return { settledAt: now.toISOString(), lines: next };
}

export function buildPuppetDto(
  state: PuppetProgressState,
  config: DongfuPuppetConfig,
  servantTotal: number,
): PuppetDto {
  const meatEmpty = state.lines.meat.stored <= 1e-6 && state.lines.meat.workers <= 0
    ? false
    : state.lines.meat.stored <= 1e-6;
  // 肉空判定：库存≈0 且有吃肉线在干活
  const eating =
    state.lines.wood.workers + state.lines.herb.workers + state.lines.stone.workers > 0;
  const meatStarved = state.lines.meat.stored <= 1e-6 && eating;

  const lines: PuppetLineDto[] = PUPPET_LINES.map((id) => {
    const row = state.lines[id];
    const cap = storageCap(config, id, row.level);
    const prod = config.lines[id].prodPerWorker;
    const eat = id === "meat" ? 0 : config.lines[id].eatMeatPerWorker;
    let net = row.workers * prod;
    if (id === "meat") {
      const consume =
        state.lines.wood.workers * config.lines.wood.eatMeatPerWorker +
        state.lines.herb.workers * config.lines.herb.eatMeatPerWorker +
        state.lines.stone.workers * config.lines.stone.eatMeatPerWorker;
      net = row.workers * prod - consume;
    } else if (meatStarved) {
      net = 0;
    }
    let stoppedReason: PuppetLineDto["stoppedReason"] = "";
    if (id !== "meat" && meatStarved && row.workers > 0) stoppedReason = "meat_empty";
    else if (row.stored >= cap - 1e-9) stoppedReason = "storage_full";
    const cost = upgradeCostOf(config, id, row.level);
    return {
      id,
      level: row.level,
      workers: row.workers,
      stored: Math.floor(row.stored * 100) / 100,
      storageCap: cap,
      prodPerWorker: prod,
      eatMeatPerWorker: eat,
      netPerHour: Math.round(net * 100) / 100,
      stoppedReason,
      upgradeCost: cost,
      canUpgrade: row.stored + 1e-9 >= cost,
    };
  });

  const used = PUPPET_LINES.reduce((n, id) => n + state.lines[id].workers, 0);
  const idle = Math.max(0, servantTotal - used);
  return {
    total: servantTotal,
    maxCount: config.maxCount,
    idle,
    hireCostMeat: config.hireCostMeat,
    canHire: servantTotal < config.maxCount && state.lines.meat.stored + 1e-9 >= config.hireCostMeat,
    meatStarved,
    lines,
    settledAt: state.settledAt,
  };
}
