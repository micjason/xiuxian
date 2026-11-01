/**
 * 洞府 v1：药园种植/领取、炼丹开始/领取、state.dongfu。
 * 时间按服务器 now 结算 growing→ready / crafting→ready；背包满领取 409 BAG_FULL（不暂存）。
 */
import { and, eq, isNull, sql } from "drizzle-orm";
import {
  playerDongfu,
  playerDongfuAlchemy,
  playerDongfuPlots,
  playerItems,
  playerStates,
} from "../../db/schema.js";
import type { Tx } from "../../db/tx.js";
import { AppError } from "../../shared/errors.js";
import type { ContentSnapshot } from "../content/validate.js";
import { applyActiveBuff } from "../loop/active-buffs.js";
import { addStack, stackCount, takeStack } from "../loop/bag.js";
import { readGameRules } from "../content/rules.js";
import { rewardDayKey } from "../progress/day.js";
import { recipeOf, requireDongfu, seedOf, type DongfuConfig, type DongfuRecipeConfig, type DongfuUpgradeTier } from "./config.js";
import {
  isSourceSinkConnected,
  normalizeRots,
  pickPuzzleForDay,
  puzzleById,
  puzzlePayload,
} from "./array-daily.js";
import { durationFactor, effectiveDurationMs, facilitySize, rescaleReadyAt, upgradeOffer } from "./pace.js";

type World = ContentSnapshot & { version: number };

export type DongfuPlotDto = {
  slot: number;
  seedSlug: string | null;
  herbSlug: string | null;
  plantedAt: string | null;
  matureAt: string | null;
  status: "empty" | "growing" | "ready";
};

export type DongfuAlchemyDto = {
  id: string;
  recipeSlug: string;
  startedAt: string;
  readyAt: string;
  status: "crafting" | "ready";
  outputItemSlug: string;
  outputQty: number;
};

export type DongfuUpgradeDto = {
  level: number;
  canUpgrade: boolean;
  reason: string;
  next: DongfuUpgradeTier | null;
};

export type DongfuRecipeClientDto = {
  recipeSlug: string;
  outputItemSlug?: string;
  outputQty?: number;
  craftSeconds?: number;
  spiritStones?: number;
  costs?: { itemSlug: string; count: number }[];
  effect?: DongfuRecipeConfig["effect"];
  discoverMode: "starter" | "hidden";
  locked?: boolean;
  usageTag?: string;
};

export type DongfuStateDto = {
  plotCount: number;
  alchemyQueueLength: number;
  plots: DongfuPlotDto[];
  alchemy: DongfuAlchemyDto[];
  claimable: { plots: number; alchemy: number };
  allocation: { garden: number; alchemy: number };
  servantTotal: number;
  gardenLevel: number;
  alchemyLevel: number;
  woodItemSlug: string;
  woodCount: number;
  /** 相对原时长的系数，1 = 不加速。 */
  timeScale: { garden: number; alchemy: number };
  upgrades: { garden: DongfuUpgradeDto; alchemy: DongfuUpgradeDto };
  /** 极简兑种表（来自配置；空则客户端只展示引导文案）。 */
  seedOffers: { seedSlug: string; spiritStones: number; quantity: number }[];
  /** 客户端可见丹方：starter 全量；hidden 未悟只回 locked 摘要。 */
  recipes: DongfuRecipeClientDto[];
  discoveredRecipeSlugs: string[];
  alchemyXp: number;
  trial: {
    slotCount: number;
    dailyLimit: number;
    usedToday: number;
    extraBought: number;
    extraMax: number;
    extraCostLingshi: number;
    left: number;
    dayKey: string;
  };
  servantAssignLingshi: number;
  /** 阵法每日小游戏。 */
  arrayDaily: {
    enabled: boolean;
    clearedToday: boolean;
    dayKey: string;
    arrayXp: number;
    puzzle?: {
      puzzleId: string;
      gridSize: number;
      source: { r: number; c: number; open: string };
      sink: { r: number; c: number; open: string };
      tiles: { r: number; c: number; shape: string; rot: number }[];
    };
  };
};

type DongfuProgress = typeof playerDongfu.$inferSelect;

function iso(value: Date | null | undefined): string | null {
  return value ? value.toISOString() : null;
}

function dongfuOf(world: World): DongfuConfig {
  return requireDongfu(world.globals.dongfu);
}

function plotStatus(row: { seedSlug: string | null; matureAt: Date | null }, now: Date): "empty" | "growing" | "ready" {
  if (!row.seedSlug || !row.matureAt) return "empty";
  return row.matureAt.getTime() <= now.getTime() ? "ready" : "growing";
}

function alchemyStatus(readyAt: Date, now: Date): "crafting" | "ready" {
  return readyAt.getTime() <= now.getTime() ? "ready" : "crafting";
}

function recipeOutput(config: DongfuConfig, recipeSlug: string): Pick<DongfuRecipeConfig, "outputItemSlug" | "outputQty"> {
  const recipe = recipeOf(config, recipeSlug);
  return { outputItemSlug: recipe.outputItemSlug, outputQty: recipe.outputQty };
}

async function ensureProgress(tx: Tx, config: DongfuConfig, playerId: string, now: Date): Promise<DongfuProgress> {
  const [existing] = await tx.select().from(playerDongfu).where(eq(playerDongfu.playerId, playerId)).limit(1);
  if (existing?.woodGranted && existing.seedsGranted) return existing;
  if (!existing) {
    await tx
      .insert(playerDongfu)
      .values({
        playerId,
        servantTotal: config.startingServants,
        gardenAllocation: 0,
        alchemyAllocation: 0,
        gardenLevel: 1,
        alchemyLevel: 1,
        woodGranted: false,
        seedsGranted: false,
      })
      .onConflictDoNothing();
  }
  const [row] = await tx.select().from(playerDongfu).where(eq(playerDongfu.playerId, playerId)).limit(1);
  if (!row) throw new AppError("NOT_FOUND");
  let next = row;
  if (!next.woodGranted) {
    if (config.startingWood > 0) {
      await addStack(tx, playerId, config.woodItemSlug, config.startingWood, "dongfu_starter", now);
    }
    await tx.update(playerDongfu).set({ woodGranted: true }).where(eq(playerDongfu.playerId, playerId));
    next = { ...next, woodGranted: true };
  }
  if (!next.seedsGranted) {
    for (const pack of config.startingSeeds) {
      if (pack.quantity > 0) {
        await addStack(tx, playerId, pack.itemSlug, pack.quantity, "dongfu_starter_seed", now);
      }
    }
    await tx.update(playerDongfu).set({ seedsGranted: true }).where(eq(playerDongfu.playerId, playerId));
    next = { ...next, seedsGranted: true };
  }
  return next;
}

function scalesOf(config: DongfuConfig, progress: DongfuProgress) {
  return {
    garden: durationFactor(progress.gardenAllocation, config.gardenReducePercent, config.minDurationPercent),
    alchemy: durationFactor(progress.alchemyAllocation, config.alchemyReducePercent, config.minDurationPercent),
  };
}

function sizesOf(config: DongfuConfig, progress: DongfuProgress) {
  return {
    plotCount: facilitySize(config.plotCount, progress.gardenLevel, config.gardenUpgrades, config.maxPlotCount),
    alchemyQueueLength: facilitySize(
      config.alchemyQueueLength,
      progress.alchemyLevel,
      config.alchemyUpgrades,
      config.maxAlchemyQueue,
    ),
  };
}

async function rescaleInProgress(tx: Tx, config: DongfuConfig, playerId: string, progress: DongfuProgress, now: Date) {
  const scale = scalesOf(config, progress);
  const plots = await tx.select().from(playerDongfuPlots).where(eq(playerDongfuPlots.playerId, playerId));
  for (const row of plots) {
    if (!row.seedSlug || !row.plantedAt || !row.matureAt || row.matureAt.getTime() <= now.getTime()) continue;
    const seed = config.seeds.find((item) => item.seedSlug === row.seedSlug);
    if (!seed) continue;
    const matureAt = rescaleReadyAt({
      now,
      startedAt: row.plantedAt,
      readyAt: row.matureAt,
      baseSeconds: seed.growSeconds,
      factor: scale.garden,
    });
    if (matureAt.getTime() === row.matureAt.getTime()) continue;
    await tx
      .update(playerDongfuPlots)
      .set({ matureAt })
      .where(and(eq(playerDongfuPlots.playerId, playerId), eq(playerDongfuPlots.slot, row.slot)));
  }
  const jobs = await tx
    .select()
    .from(playerDongfuAlchemy)
    .where(and(eq(playerDongfuAlchemy.playerId, playerId), isNull(playerDongfuAlchemy.claimedAt)));
  for (const job of jobs) {
    if (job.readyAt.getTime() <= now.getTime()) continue;
    const recipe = config.recipes.find((item) => item.recipeSlug === job.recipeSlug);
    if (!recipe) continue;
    const readyAt = rescaleReadyAt({
      now,
      startedAt: job.startedAt,
      readyAt: job.readyAt,
      baseSeconds: recipe.craftSeconds,
      factor: scale.alchemy,
    });
    if (readyAt.getTime() === job.readyAt.getTime()) continue;
    await tx.update(playerDongfuAlchemy).set({ readyAt }).where(eq(playerDongfuAlchemy.id, job.id));
  }
}


function discoveredSet(progress: DongfuProgress, config: DongfuConfig): Set<string> {
  const set = new Set<string>(Array.isArray(progress.discoveredRecipeSlugs) ? progress.discoveredRecipeSlugs : []);
  for (const recipe of config.recipes) {
    if ((recipe.discoverMode ?? "starter") === "starter") set.add(recipe.recipeSlug);
  }
  return set;
}

function shanghaiDayKey(now: Date): string {
  return rewardDayKey(now, 0);
}

function trialUsage(progress: DongfuProgress, dayKey: string): { dayKey: string; count: number; extraBought: number } {
  const raw = progress.trialUsedOnDay;
  if (raw && raw.dayKey === dayKey) {
    return { dayKey, count: Math.max(0, Math.floor(raw.count || 0)), extraBought: Math.max(0, Math.floor(raw.extraBought || 0)) };
  }
  return { dayKey, count: 0, extraBought: 0 };
}

function materialMultiset(rows: { itemSlug: string; count: number }[]): Map<string, number> {
  const map = new Map<string, number>();
  for (const row of rows) {
    const slug = row.itemSlug;
    const count = Math.max(0, Math.floor(row.count));
    if (!slug || count <= 0) continue;
    map.set(slug, (map.get(slug) ?? 0) + count);
  }
  return map;
}

function multisetEqual(a: Map<string, number>, b: Map<string, number>): boolean {
  if (a.size !== b.size) return false;
  for (const [k, v] of a) {
    if ((b.get(k) ?? 0) !== v) return false;
  }
  return true;
}

function correctCount(chosen: Map<string, number>, required: Map<string, number>): number {
  let n = 0;
  for (const [slug, need] of required) {
    n += Math.min(need, chosen.get(slug) ?? 0);
  }
  return n;
}

function recipesForClient(config: DongfuConfig, discovered: Set<string>): DongfuRecipeClientDto[] {
  const out: DongfuRecipeClientDto[] = [];
  for (const recipe of config.recipes) {
    const mode = recipe.discoverMode ?? "starter";
    if (mode === "hidden" && !discovered.has(recipe.recipeSlug)) {
      out.push({
        recipeSlug: recipe.recipeSlug,
        discoverMode: "hidden",
        locked: true,
        usageTag: recipe.usageTag,
      });
      continue;
    }
    out.push({
      recipeSlug: recipe.recipeSlug,
      outputItemSlug: recipe.outputItemSlug,
      outputQty: recipe.outputQty,
      craftSeconds: recipe.craftSeconds,
      spiritStones: recipe.spiritStones,
      costs: recipe.costs.map((c) => ({ ...c })),
      effect: recipe.effect,
      discoverMode: mode,
      usageTag: recipe.usageTag,
    });
  }
  return out;
}

function pickHint(config: DongfuConfig, tier: "fail" | "imperfect", now: Date): string {
  const keys: string[] = config.alchemyHintKeys.length > 0 ? [...config.alchemyHintKeys] : ["clash"];
  const pool: string[] =
    tier === "imperfect" ? [...keys.filter((k) => k === "near"), ...keys] : keys.filter((k) => k !== "near");
  const list = pool.length > 0 ? pool : keys;
  return list[now.getUTCSeconds() % list.length]!;
}

/** 组装 state.dongfu。首次会写入灵仆行并发放初始灵木；之后按 now 只读结算状态。 */
export async function readDongfuState(tx: Tx, world: World, playerId: string, now: Date): Promise<DongfuStateDto> {
  const config = dongfuOf(world);
  const progress = await ensureProgress(tx, config, playerId, now);
  const sizes = sizesOf(config, progress);
  const scale = scalesOf(config, progress);
  const plotRows = await tx.select().from(playerDongfuPlots).where(eq(playerDongfuPlots.playerId, playerId));
  const bySlot = new Map(plotRows.map((row) => [row.slot, row]));
  const plots: DongfuPlotDto[] = [];
  for (let slot = 0; slot < sizes.plotCount; slot += 1) {
    const row = bySlot.get(slot);
    if (!row || !row.seedSlug) {
      plots.push({ slot, seedSlug: null, herbSlug: null, plantedAt: null, matureAt: null, status: "empty" });
      continue;
    }
    const seed = config.seeds.find((s) => s.seedSlug === row.seedSlug);
    plots.push({
      slot,
      seedSlug: row.seedSlug,
      herbSlug: seed?.herbSlug ?? null,
      plantedAt: iso(row.plantedAt),
      matureAt: iso(row.matureAt),
      status: plotStatus(row, now),
    });
  }
  const jobs = await tx
    .select()
    .from(playerDongfuAlchemy)
    .where(and(eq(playerDongfuAlchemy.playerId, playerId), isNull(playerDongfuAlchemy.claimedAt)));
  const alchemy: DongfuAlchemyDto[] = jobs
    .sort((a, b) => a.startedAt.getTime() - b.startedAt.getTime())
    .map((job) => {
      const out = recipeOutput(config, job.recipeSlug);
      return {
        id: job.id,
        recipeSlug: job.recipeSlug,
        startedAt: job.startedAt.toISOString(),
        readyAt: job.readyAt.toISOString(),
        status: alchemyStatus(job.readyAt, now),
        outputItemSlug: out.outputItemSlug,
        outputQty: out.outputQty,
      };
    });
  const items = await loadBagItems(tx, playerId);
  const [player] = await tx
    .select({ spiritStones: playerStates.spiritStones })
    .from(playerStates)
    .where(eq(playerStates.playerId, playerId))
    .limit(1);
  const woodCount = stackCount(items, config.woodItemSlug);
  const spiritStones = player?.spiritStones ?? 0;
  const gardenOffer = upgradeOffer({
    level: progress.gardenLevel,
    tiers: config.gardenUpgrades,
    base: config.plotCount,
    max: config.maxPlotCount,
    woodHave: woodCount,
    spiritStones,
  });
  const alchemyOffer = upgradeOffer({
    level: progress.alchemyLevel,
    tiers: config.alchemyUpgrades,
    base: config.alchemyQueueLength,
    max: config.maxAlchemyQueue,
    woodHave: woodCount,
    spiritStones,
  });
  const discovered = discoveredSet(progress, config);
  const dayKey = shanghaiDayKey(now);
  const usage = trialUsage(progress, dayKey);
  const trialCap = config.alchemyTrialDailyLimit + usage.extraBought;
  const trialLeft = Math.max(0, trialCap - usage.count);
  return {
    plotCount: sizes.plotCount,
    alchemyQueueLength: sizes.alchemyQueueLength,
    plots,
    alchemy,
    claimable: {
      plots: plots.filter((p) => p.status === "ready").length,
      alchemy: alchemy.filter((j) => j.status === "ready").length,
    },
    allocation: { garden: progress.gardenAllocation, alchemy: progress.alchemyAllocation },
    servantTotal: progress.servantTotal,
    gardenLevel: progress.gardenLevel,
    alchemyLevel: progress.alchemyLevel,
    woodItemSlug: config.woodItemSlug,
    woodCount,
    timeScale: scale,
    upgrades: {
      garden: { level: progress.gardenLevel, ...gardenOffer },
      alchemy: { level: progress.alchemyLevel, ...alchemyOffer },
    },
    seedOffers: config.seedOffers.map((row) => ({ ...row })),
    recipes: recipesForClient(config, discovered),
    discoveredRecipeSlugs: [...discovered],
    alchemyXp: progress.alchemyXp ?? 0,
    trial: {
      slotCount: config.alchemyTrialSlotCount,
      dailyLimit: config.alchemyTrialDailyLimit,
      usedToday: usage.count,
      extraBought: usage.extraBought,
      extraMax: config.alchemyTrialExtraMax,
      extraCostLingshi: config.alchemyTrialExtraCostLingshi,
      left: trialLeft,
      dayKey,
    },
    servantAssignLingshi: config.servantAssignLingshi,
    arrayDaily: buildArrayDailyDto(config, progress, now),
  };
}

function buildArrayDailyDto(config: DongfuConfig, progress: DongfuProgress, now: Date) {
  const dayKey = shanghaiDayKey(now);
  const cfg = config.arrayDaily;
  const clearedToday = progress.lastClearDay === dayKey;
  const base = {
    enabled: cfg.enabled,
    clearedToday,
    dayKey,
    arrayXp: progress.arrayXp ?? 0,
  };
  if (!cfg.enabled || clearedToday) {
    return base;
  }
  const puzzle = pickPuzzleForDay(cfg.puzzles, dayKey);
  return { ...base, puzzle: puzzlePayload(puzzle, cfg.gridSize) };
}

async function loadBagItems(tx: Tx, playerId: string) {
  return tx.select().from(playerItems).where(eq(playerItems.playerId, playerId));
}

/**
 * 领取前检查：若目标堆叠还不存在，且行囊格子已满，则 409 BAG_FULL。
 * （已有堆叠可并入，不占新格。）
 */
async function assertCanAcceptStacks(tx: Tx, world: World, playerId: string, itemSlugs: string[]) {
  const items = await loadBagItems(tx, playerId);
  const [state] = await tx.select().from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
  if (!state) throw new AppError("NOT_FOUND");
  const capacity = readGameRules(world).bagCapacity + state.bagBonus;
  const used = items.filter((row) => !row.equippedSlot).length;
  const needNew = new Set<string>();
  for (const slug of itemSlugs) {
    if (stackCount(items, slug) <= 0) needNew.add(slug);
  }
  if (used + needNew.size > capacity) {
    throw new AppError("BAG_FULL", "行囊已满，请先分解或使用");
  }
}

export async function plantSeed(
  tx: Tx,
  world: World,
  playerId: string,
  input: { slot: number; seedSlug: string },
  now: Date,
) {
  const config = dongfuOf(world);
  const progress = await ensureProgress(tx, config, playerId, now);
  const plotCount = sizesOf(config, progress).plotCount;
  if (!Number.isInteger(input.slot) || input.slot < 0 || input.slot >= plotCount) {
    throw new AppError("INVALID_INPUT", `地块编号要在 0–${plotCount - 1}`);
  }
  const seed = seedOf(config, input.seedSlug);
  const items = await loadBagItems(tx, playerId);
  if (stackCount(items, seed.seedSlug) < 1) {
    throw new AppError("MATERIAL_SHORT", "种子不足");
  }
  const [existing] = await tx
    .select()
    .from(playerDongfuPlots)
    .where(and(eq(playerDongfuPlots.playerId, playerId), eq(playerDongfuPlots.slot, input.slot)))
    .limit(1);
  if (existing?.seedSlug) {
    throw new AppError("INVALID_INPUT", "这块地已经种了");
  }
  await takeStack(tx, items, seed.seedSlug, 1);
  const matureAt = new Date(
    now.getTime() + effectiveDurationMs(seed.growSeconds, scalesOf(config, progress).garden),
  );
  if (existing) {
    await tx
      .update(playerDongfuPlots)
      .set({ seedSlug: seed.seedSlug, plantedAt: now, matureAt })
      .where(and(eq(playerDongfuPlots.playerId, playerId), eq(playerDongfuPlots.slot, input.slot)));
  } else {
    await tx.insert(playerDongfuPlots).values({
      playerId,
      slot: input.slot,
      seedSlug: seed.seedSlug,
      plantedAt: now,
      matureAt,
    });
  }
  return { dongfu: await readDongfuState(tx, world, playerId, now) };
}

export async function claimGarden(
  tx: Tx,
  world: World,
  playerId: string,
  input: { slot?: number },
  now: Date,
) {
  const config = dongfuOf(world);
  const rows = await tx.select().from(playerDongfuPlots).where(eq(playerDongfuPlots.playerId, playerId));
  const ready = rows.filter((row) => {
    if (!row.seedSlug || !row.matureAt) return false;
    if (plotStatus(row, now) !== "ready") return false;
    if (input.slot !== undefined && row.slot !== input.slot) return false;
    return true;
  });
  if (ready.length === 0) {
    throw new AppError("INVALID_INPUT", input.slot !== undefined ? "这块地还不能领取" : "没有可领取的草药");
  }
  const gained: { itemSlug: string; quantity: number }[] = [];
  for (const row of ready) {
    const seed = seedOf(config, row.seedSlug!);
    gained.push({ itemSlug: seed.herbSlug, quantity: 1 });
  }
  await assertCanAcceptStacks(
    tx,
    world,
    playerId,
    gained.map((g) => g.itemSlug),
  );
  for (const row of ready) {
    const seed = seedOf(config, row.seedSlug!);
    await addStack(tx, playerId, seed.herbSlug, 1, "dongfu_garden", now);
    await tx
      .delete(playerDongfuPlots)
      .where(and(eq(playerDongfuPlots.playerId, playerId), eq(playerDongfuPlots.slot, row.slot)));
  }
  return { dongfu: await readDongfuState(tx, world, playerId, now), gained };
}

export async function startAlchemy(
  tx: Tx,
  world: World,
  playerId: string,
  input: { recipeSlug: string },
  now: Date,
) {
  const config = dongfuOf(world);
  const progress = await ensureProgress(tx, config, playerId, now);
  const recipe = recipeOf(config, input.recipeSlug);
  const known = discoveredSet(progress, config);
  if (!known.has(recipe.recipeSlug)) {
    throw new AppError("FORBIDDEN", "尚未悟得该丹方");
  }
  const queueLength = sizesOf(config, progress).alchemyQueueLength;
  const open = await tx
    .select({ id: playerDongfuAlchemy.id })
    .from(playerDongfuAlchemy)
    .where(and(eq(playerDongfuAlchemy.playerId, playerId), isNull(playerDongfuAlchemy.claimedAt)));
  if (open.length >= queueLength) {
    throw new AppError("QUEUE_FULL");
  }
  const items = await loadBagItems(tx, playerId);
  for (const cost of recipe.costs) {
    if (stackCount(items, cost.itemSlug) < cost.count) {
      throw new AppError("MATERIAL_SHORT", `材料不足：${cost.itemSlug}`);
    }
  }
  const [state] = await tx.select().from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
  if (!state) throw new AppError("NOT_FOUND");
  if (recipe.spiritStones > 0 && state.spiritStones < recipe.spiritStones) {
    throw new AppError("MATERIAL_SHORT", "灵石不足");
  }
  for (const cost of recipe.costs) {
    await takeStack(tx, items, cost.itemSlug, cost.count);
  }
  if (recipe.spiritStones > 0) {
    await tx
      .update(playerStates)
      .set({ spiritStones: sql`${playerStates.spiritStones} - ${recipe.spiritStones}` })
      .where(eq(playerStates.playerId, playerId));
  }
  const readyAt = new Date(now.getTime() + effectiveDurationMs(recipe.craftSeconds, scalesOf(config, progress).alchemy));
  await tx.insert(playerDongfuAlchemy).values({
    playerId,
    recipeSlug: recipe.recipeSlug,
    startedAt: now,
    readyAt,
    claimedAt: null,
  });
  return { dongfu: await readDongfuState(tx, world, playerId, now) };
}

export async function claimAlchemy(
  tx: Tx,
  world: World,
  playerId: string,
  input: { jobId?: string },
  now: Date,
) {
  const config = dongfuOf(world);
  const jobs = await tx
    .select()
    .from(playerDongfuAlchemy)
    .where(and(eq(playerDongfuAlchemy.playerId, playerId), isNull(playerDongfuAlchemy.claimedAt)));
  const ready = jobs.filter((job) => {
    if (alchemyStatus(job.readyAt, now) !== "ready") return false;
    if (input.jobId !== undefined && job.id !== input.jobId) return false;
    return true;
  });
  if (ready.length === 0) {
    throw new AppError("INVALID_INPUT", input.jobId ? "这炉丹还不能领取" : "没有可领取的丹药");
  }
  const gained: { itemSlug: string; quantity: number }[] = [];
  for (const job of ready) {
    const recipe = recipeOf(config, job.recipeSlug);
    gained.push({ itemSlug: recipe.outputItemSlug, quantity: recipe.outputQty });
  }
  await assertCanAcceptStacks(
    tx,
    world,
    playerId,
    gained.map((g) => g.itemSlug),
  );
  for (const job of ready) {
    const recipe = recipeOf(config, job.recipeSlug);
    await addStack(tx, playerId, recipe.outputItemSlug, recipe.outputQty, "dongfu_alchemy", now);
    await tx.update(playerDongfuAlchemy).set({ claimedAt: now }).where(eq(playerDongfuAlchemy.id, job.id));
  }
  return { dongfu: await readDongfuState(tx, world, playerId, now), gained };
}

export async function allocateServants(
  tx: Tx,
  world: World,
  playerId: string,
  input: { garden: number; alchemy: number },
  now: Date,
) {
  const config = dongfuOf(world);
  const progress = await ensureProgress(tx, config, playerId, now);
  if (!Number.isInteger(input.garden) || !Number.isInteger(input.alchemy) || input.garden < 0 || input.alchemy < 0) {
    throw new AppError("INVALID_INPUT", "傀儡数量不正确");
  }
  if (input.garden + input.alchemy > progress.servantTotal) {
    throw new AppError("INVALID_INPUT", "傀儡不够分配");
  }
  const prevAssigned = progress.gardenAllocation + progress.alchemyAllocation;
  const nextAssigned = input.garden + input.alchemy;
  const added = Math.max(0, nextAssigned - prevAssigned);
  const cost = added * Math.max(0, Math.floor(config.servantAssignLingshi));
  if (cost > 0) {
    const [state] = await tx.select().from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
    if (!state) throw new AppError("NOT_FOUND");
    if (state.spiritStones < cost) {
      throw new AppError("MATERIAL_SHORT", `上工需灵石 ×${cost}`);
    }
    await tx
      .update(playerStates)
      .set({ spiritStones: sql`${playerStates.spiritStones} - ${cost}` })
      .where(eq(playerStates.playerId, playerId));
  }
  const next = { ...progress, gardenAllocation: input.garden, alchemyAllocation: input.alchemy };
  await tx
    .update(playerDongfu)
    .set({ gardenAllocation: input.garden, alchemyAllocation: input.alchemy })
    .where(eq(playerDongfu.playerId, playerId));
  await rescaleInProgress(tx, config, playerId, next, now);
  return { dongfu: await readDongfuState(tx, world, playerId, now), spentLingshi: cost };
}

export async function upgradeFacility(
  tx: Tx,
  world: World,
  playerId: string,
  facility: "garden" | "alchemy",
  now: Date,
) {
  const config = dongfuOf(world);
  const progress = await ensureProgress(tx, config, playerId, now);
  const level = facility === "garden" ? progress.gardenLevel : progress.alchemyLevel;
  const tiers = facility === "garden" ? config.gardenUpgrades : config.alchemyUpgrades;
  const base = facility === "garden" ? config.plotCount : config.alchemyQueueLength;
  const max = facility === "garden" ? config.maxPlotCount : config.maxAlchemyQueue;
  const items = await loadBagItems(tx, playerId);
  const [state] = await tx.select().from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
  if (!state) throw new AppError("NOT_FOUND");
  const offer = upgradeOffer({
    level,
    tiers,
    base,
    max,
    woodHave: stackCount(items, config.woodItemSlug),
    spiritStones: state.spiritStones,
  });
  if (!offer.canUpgrade || !offer.next) {
    throw new AppError(offer.reason === "灵木不足" || offer.reason === "灵石不足" ? "MATERIAL_SHORT" : "INVALID_INPUT", offer.reason);
  }
  if (offer.next.wood > 0) {
    await takeStack(tx, items, config.woodItemSlug, offer.next.wood);
  }
  if (offer.next.spiritStones > 0) {
    await tx
      .update(playerStates)
      .set({ spiritStones: sql`${playerStates.spiritStones} - ${offer.next.spiritStones}` })
      .where(eq(playerStates.playerId, playerId));
  }
  await tx
    .update(playerDongfu)
    .set(facility === "garden" ? { gardenLevel: level + 1 } : { alchemyLevel: level + 1 })
    .where(eq(playerDongfu.playerId, playerId));
  return { dongfu: await readDongfuState(tx, world, playerId, now) };
}


/** 极简灵石兑种：扣灵石 → 发种子。不做商店浏览/限购。 */
export async function buySeed(
  tx: Tx,
  world: World,
  playerId: string,
  input: { seedSlug: string },
  now: Date,
) {
  const config = dongfuOf(world);
  await ensureProgress(tx, config, playerId, now);
  const offer = config.seedOffers.find((row) => row.seedSlug === input.seedSlug);
  if (!offer) {
    throw new AppError("INVALID_INPUT", "该种子暂不支持灵石兑换");
  }
  // 必须是药园配置里的种子，避免兑到无关物品。
  seedOf(config, offer.seedSlug);
  const [player] = await tx
    .select({ spiritStones: playerStates.spiritStones })
    .from(playerStates)
    .where(eq(playerStates.playerId, playerId))
    .limit(1);
  if ((player?.spiritStones ?? 0) < offer.spiritStones) {
    throw new AppError("MATERIAL_SHORT", "灵石不足");
  }
  await tx
    .update(playerStates)
    .set({ spiritStones: sql`${playerStates.spiritStones} - ${offer.spiritStones}` })
    .where(eq(playerStates.playerId, playerId));
  await addStack(tx, playerId, offer.seedSlug, offer.quantity, "dongfu_seed_exchange", now);
  return { dongfu: await readDongfuState(tx, world, playerId, now) };
}

/**
 * 使用丹药（由 loop/useItem 调用）。
 * - cultivationGain：立刻加修为
 * - buffStat/buffBp/durationSeconds：经 applyActiveBuff 写入 player_active_buffs（表以 0060 为准；战斗结算读取未过期行）
 */
export async function applyPillUse(
  tx: Tx,
  playerId: string,
  item: { id: string; itemSlug: string; quantity: number; isStack: boolean },
  effect: { cultivationGain?: number; buffStat?: string; buffBp?: number; durationSeconds?: number },
  now: Date,
) {
  if (item.isStack && item.quantity > 1) {
    await tx.update(playerItems).set({ quantity: item.quantity - 1 }).where(eq(playerItems.id, item.id));
  } else {
    await tx.delete(playerItems).where(eq(playerItems.id, item.id));
  }

  if (typeof effect.cultivationGain === "number" && effect.cultivationGain > 0) {
    await tx
      .update(playerStates)
      .set({ cultivation: sql`${playerStates.cultivation} + ${effect.cultivationGain}` })
      .where(eq(playerStates.playerId, playerId));
    return { itemSlug: item.itemSlug, cultivationGain: effect.cultivationGain };
  }

  if (effect.buffStat && typeof effect.buffBp === "number" && typeof effect.durationSeconds === "number") {
    const buff = await applyActiveBuff(tx, {
      playerId,
      buffStat: effect.buffStat,
      buffBp: effect.buffBp,
      durationSeconds: effect.durationSeconds,
      sourceItemSlug: item.itemSlug,
      now,
    });
    return {
      itemSlug: item.itemSlug,
      buffStat: buff.buffStat,
      buffBp: buff.buffBp,
      durationSeconds: effect.durationSeconds,
      expiresAt: buff.expiresAt,
    };
  }

  throw new AppError("INVALID_INPUT", "这颗丹药没有可用效果");
}


export async function trialAlchemy(
  tx: Tx,
  world: World,
  playerId: string,
  input: { materials: { itemSlug: string; count: number }[]; buyExtra?: boolean },
  now: Date,
) {
  const config = dongfuOf(world);
  const progress = await ensureProgress(tx, config, playerId, now);
  const materials = Array.isArray(input.materials) ? input.materials : [];
  const slotCount = config.alchemyTrialSlotCount;
  const chosen = materialMultiset(materials);
  const chosenTotal = [...chosen.values()].reduce((a, b) => a + b, 0);
  if (chosenTotal <= 0 || chosenTotal > slotCount) {
    throw new AppError("INVALID_INPUT", `试炼材料合计须为 1～${slotCount}`);
  }

  const dayKey = shanghaiDayKey(now);
  let usage = trialUsage(progress, dayKey);
  let spiritSpent = 0;
  const [state] = await tx.select().from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
  if (!state) throw new AppError("NOT_FOUND");

  const softCap = config.alchemyTrialDailyLimit + usage.extraBought;
  if (usage.count >= softCap) {
    if (!input.buyExtra) {
      throw new AppError("INVALID_INPUT", "今日试炼次数已用尽");
    }
    if (config.alchemyTrialExtraCostLingshi <= 0 || usage.extraBought >= config.alchemyTrialExtraMax) {
      throw new AppError("INVALID_INPUT", "今日不可再买超额试炼");
    }
    if (state.spiritStones < config.alchemyTrialExtraCostLingshi) {
      throw new AppError("MATERIAL_SHORT", "灵石不足");
    }
    spiritSpent += config.alchemyTrialExtraCostLingshi;
    usage = { ...usage, extraBought: usage.extraBought + 1 };
  }

  const items = await loadBagItems(tx, playerId);
  for (const [slug, count] of chosen) {
    if (stackCount(items, slug) < count) {
      throw new AppError("MATERIAL_SHORT", `材料不足：${slug}`);
    }
  }
  for (const [slug, count] of chosen) {
    await takeStack(tx, items, slug, count);
  }
  if (spiritSpent > 0) {
    await tx
      .update(playerStates)
      .set({ spiritStones: sql`${playerStates.spiritStones} - ${spiritSpent}` })
      .where(eq(playerStates.playerId, playerId));
  }

  const discovered = discoveredSet(progress, config);
  const hidden = config.recipes.filter((r) => (r.discoverMode ?? "starter") === "hidden");
  let best: { recipe: DongfuRecipeConfig; correct: number; perfect: boolean } | null = null;
  for (const recipe of hidden) {
    const need = materialMultiset(recipe.costs);
    const correct = correctCount(chosen, need);
    const perfect = multisetEqual(chosen, need);
    if (!best || correct > best.correct || (correct === best.correct && perfect && !best.perfect)) {
      best = { recipe, correct, perfect };
    }
  }

  let tier: "fail" | "imperfect" | "perfect" = "fail";
  let xp = config.alchemyTrialFailXp;
  let hintKey: string | undefined = pickHint(config, "fail", now);
  let unlockedRecipeSlug: string | undefined;
  const rewards: { itemSlug: string; quantity: number }[] = [];

  if (best && best.perfect) {
    tier = "perfect";
    xp = config.alchemyTrialPerfectXp;
    hintKey = undefined;
    const outSlug = best.recipe.outputItemSlug;
    const outQty = best.recipe.outputQty;
    await assertCanAcceptStacks(tx, world, playerId, [outSlug]);
    await addStack(tx, playerId, outSlug, outQty, "dongfu_alchemy_trial", now);
    rewards.push({ itemSlug: outSlug, quantity: outQty });
    if (!discovered.has(best.recipe.recipeSlug)) {
      unlockedRecipeSlug = best.recipe.recipeSlug;
      discovered.add(best.recipe.recipeSlug);
    }
  } else if (best && best.correct > 0) {
    tier = "imperfect";
    xp = config.alchemyTrialImperfectXp;
    hintKey = pickHint(config, "imperfect", now);
    const outSlug = best.recipe.imperfectOutputItemSlug || best.recipe.outputItemSlug;
    await assertCanAcceptStacks(tx, world, playerId, [outSlug]);
    await addStack(tx, playerId, outSlug, 1, "dongfu_alchemy_trial", now);
    rewards.push({ itemSlug: outSlug, quantity: 1 });
  }

  usage = { ...usage, count: usage.count + 1 };
  await tx
    .update(playerDongfu)
    .set({
      alchemyXp: (progress.alchemyXp ?? 0) + xp,
      trialUsedOnDay: usage,
      discoveredRecipeSlugs: [...discovered],
    })
    .where(eq(playerDongfu.playerId, playerId));

  const trialCap = config.alchemyTrialDailyLimit + usage.extraBought;
  return {
    tier,
    hintKey,
    unlockedRecipeSlug,
    rewards,
    alchemyXpDelta: xp,
    trialLeft: Math.max(0, trialCap - usage.count),
    dongfu: await readDongfuState(tx, world, playerId, now),
  };
}

/** 供 loop stateDto 挂载；配置缺失时抛错（不回退默认）。 */
export { requireDongfu };

/** 阵法日游收阵：服务器日界结算；连通则发奖，否则 NOT_CONNECTED / ALREADY_CLEARED。 */
export async function completeArrayDaily(
  tx: Tx,
  world: World,
  playerId: string,
  input: { puzzleId: string; dayKey?: string; rots: unknown },
  now: Date,
) {
  const config = dongfuOf(world);
  const arrayCfg = config.arrayDaily;
  if (!arrayCfg.enabled) {
    throw new AppError("DISABLED", "阵法结界未开");
  }
  const dayKey = shanghaiDayKey(now);
  if (input.dayKey !== undefined && input.dayKey !== null && input.dayKey !== "" && input.dayKey !== dayKey) {
    throw new AppError("INVALID_INPUT", "日界已切换，请重新打开洞府");
  }
  const progress = await ensureProgress(tx, config, playerId, now);
  if (progress.lastClearDay === dayKey) {
    throw new AppError("ALREADY_CLEARED", "今日灵脉已接引");
  }
  if (typeof input.puzzleId !== "string" || !input.puzzleId) {
    throw new AppError("INVALID_INPUT", "请选择阵图");
  }
  const expected = pickPuzzleForDay(arrayCfg.puzzles, dayKey);
  if (input.puzzleId !== expected.puzzleId) {
    // 允许提交当日关；未知 id 走 PUZZLE_UNKNOWN；错日关也当阵图有变
    puzzleById(arrayCfg, input.puzzleId);
    throw new AppError("PUZZLE_UNKNOWN", "阵图有变，请重新打开洞府");
  }
  const puzzle = expected;
  const rots = normalizeRots(puzzle, input.rots);
  if (!isSourceSinkConnected(puzzle, rots, arrayCfg.gridSize)) {
    throw new AppError("NOT_CONNECTED", "灵脉未通，再试试");
  }
  const gained: { itemSlug: string; qty: number }[] = [];
  if (arrayCfg.rewardShardQty > 0) {
    await assertCanAcceptStacks(tx, world, playerId, [arrayCfg.rewardShardItemSlug]);
    await addStack(tx, playerId, arrayCfg.rewardShardItemSlug, arrayCfg.rewardShardQty, "dongfu_array_daily", now);
    gained.push({ itemSlug: arrayCfg.rewardShardItemSlug, qty: arrayCfg.rewardShardQty });
  }
  const arrayXpGained = arrayCfg.rewardXp;
  await tx
    .update(playerDongfu)
    .set({
      lastClearDay: dayKey,
      lastPuzzleId: puzzle.puzzleId,
      arrayXp: (progress.arrayXp ?? 0) + arrayXpGained,
    })
    .where(eq(playerDongfu.playerId, playerId));
  return {
    dongfu: await readDongfuState(tx, world, playerId, now),
    gained,
    arrayXpGained,
  };
}
