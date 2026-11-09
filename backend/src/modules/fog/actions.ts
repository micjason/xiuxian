import { createHash } from "node:crypto";
import { requireNoCombat } from "../combat/journal-guard.js";
import {
  runtimeConfigOf,
  configuredSkills,
  combatTraits,
} from "../combat/runtime-config.js";
/**
 * 迷雾秘境 P0：问心谷。移动/揭雾/箱/怪/事件/异空间战。
 * 库表 pos_c=x、pos_r=y；DTO 对外 x/y。
 */
import { and, eq } from "drizzle-orm";
import {
  contentGlobals,
  contentItems,
  contentSkills,
  playerFogRuns,
  playerItems,
  playerSkills,
  playerStates,
} from "../../db/schema.js";
import type { Tx } from "../../db/tx.js";
import { AppError } from "../../shared/errors.js";
import type { ContentSnapshot } from "../content/validate.js";
import {
  simulateBattle,
  toCombatSkills,
  type BattleResult,
} from "../combat/battle.js";
import { shanghaiDayKey } from "../dongfu/array-daily.js";
import { addStack } from "../loop/bag.js";
import {
  battleConfigOf,
  combatStats,
  openSkillSlotsFor,
} from "../loop/actions.js";
import {
  cellKey,
  explorationOf,
  isFogExit,
  fogMapOf,
  isBlocked,
  livingMonsterAt,
  neighbors4,
  requireFog,
  revealAround,
  type FogConfig,
  type FogEventObject,
  type FogLoot,
  type FogMapConfig,
  type FogMonsterObject,
} from "./config.js";

type World = ContentSnapshot & { version: number };

export type FogObjectDto = {
  id: string;
  kind: "chest" | "monster" | "event" | "exit";
  passed?: boolean;
  x: number;
  y: number;
  name?: string;
  title?: string;
  opened?: boolean;
  defeated?: boolean;
  done?: boolean;
  options?: { id: string; label: string; effect: string }[];
};

export type FogStateDto = {
  protocol: "fog-step-v1";
  revision: string;
  mapId: string;
  displayName: string;
  rows: number;
  cols: number;
  pos: { x: number; y: number };
  revealed: string[];
  blocks: { x: number; y: number }[];
  objects: FogObjectDto[];
  travelPoints: number;
  travelPointsMax: number;
  travelDay: string;
  exploreRevealed: number;
  exploreTotal: number;
  exploreFull: boolean;
  /** 顶栏收集：箱 n/3、普通怪 n/2（出口不计入） */
  collect: {
    chestsOpened: number;
    chestsTotal: number;
    monstersDefeated: number;
    monstersTotal: number;
  };
};

type ObjectProgress = Record<
  string,
  { opened?: boolean; defeated?: boolean; done?: boolean }
>;

function fogOf(world: World): FogConfig {
  return requireFog(world.globals.fog);
}

function parseRevealed(raw: unknown): Set<string> {
  const set = new Set<string>();
  if (!Array.isArray(raw)) return set;
  for (const row of raw) {
    if (typeof row === "string" && row.includes(",")) set.add(row);
  }
  return set;
}

function parseObjects(raw: unknown): ObjectProgress {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const out: ObjectProgress = {};
  for (const [id, val] of Object.entries(raw as Record<string, unknown>)) {
    if (!val || typeof val !== "object") continue;
    const v = val as { opened?: unknown; defeated?: unknown; done?: unknown };
    out[id] = { opened: v.opened === true, defeated: v.defeated === true, done: v.done === true };
  }
  return out;
}

function collectOf(map: FogMapConfig, objects: ObjectProgress) {
  const chests = map.objects.filter((o) => o.kind === "chest");
  const monsters = map.objects.filter(
    (o) => o.kind === "monster" && !isFogExit(o),
  );
  return {
    chestsOpened: chests.filter((c) => objects[c.id]?.opened).length,
    chestsTotal: chests.length,
    monstersDefeated: monsters.filter((m) => objects[m.id]?.defeated).length,
    monstersTotal: monsters.length,
  };
}

async function refreshTravel(
  tx: Tx,
  playerId: string,
  mapId: string,
  config: FogConfig,
  now: Date,
): Promise<{
  posX: number;
  posY: number;
  revealed: Set<string>;
  objects: ObjectProgress;
  travelPoints: number;
  travelDay: string;
}> {
  const map = fogMapOf(config, mapId);
  const day = shanghaiDayKey(now);
  const [row] = await tx
    .select()
    .from(playerFogRuns)
    .where(
      and(eq(playerFogRuns.playerId, playerId), eq(playerFogRuns.mapId, mapId)),
    )
    .limit(1);

  if (!row) {
    const revealed = new Set<string>();
    revealAround(revealed, map, map.spawn.x, map.spawn.y, config.initialReveal);
    await tx.insert(playerFogRuns).values({
      playerId,
      mapId,
      posR: map.spawn.y,
      posC: map.spawn.x,
      revealed: [...revealed],
      objects: { __travel_budget_v2: { opened: true } },
      travelPoints: config.travelPointsMax,
      travelDay: day,
      updatedAt: now,
    });
    return {
      posX: map.spawn.x,
      posY: map.spawn.y,
      revealed,
      objects: { __travel_budget_v2: { opened: true } },
      travelPoints: config.travelPointsMax,
      travelDay: day,
    };
  }

  const objects = parseObjects(row.objects);
  let travelPoints = row.travelPoints;
  let travelDay = row.travelDay ?? day;
  // A caller may have sampled time before waiting on the player lock.
  // A stale request must never rewind the budget day and refund a newer move.
  if (travelDay < day) {
    travelPoints = config.travelPointsMax;
    travelDay = day;
    await tx
      .update(playerFogRuns)
      .set({ travelPoints, travelDay, updatedAt: now })
      .where(
        and(
          eq(playerFogRuns.playerId, playerId),
          eq(playerFogRuns.mapId, mapId),
        ),
      );
  }

  // One-time budget upgrade for pre-exit runs; retain spent points and progress.
  // Persist a reserved progress marker so reconnects never refill again.
  if (
    mapId === "fog_wenxin_valley" &&
    config.travelPointsMax >= 200 &&
    !objects.__travel_budget_v2?.opened
  ) {
    if (row.travelDay === day)
      travelPoints = Math.min(
        config.travelPointsMax,
        travelPoints + config.travelPointsMax - 20,
      );
    objects.__travel_budget_v2 = { opened: true };
    await tx
      .update(playerFogRuns)
      .set({ travelPoints, objects, updatedAt: now })
      .where(
        and(
          eq(playerFogRuns.playerId, playerId),
          eq(playerFogRuns.mapId, mapId),
        ),
      );
  }
  return {
    posX: row.posC,
    posY: row.posR,
    revealed: parseRevealed(row.revealed),
    objects,
    travelPoints,
    travelDay,
  };
}

function toDto(
  config: FogConfig,
  map: FogMapConfig,
  run: {
    posX: number;
    posY: number;
    revealed: Set<string>;
    objects: ObjectProgress;
    travelPoints: number;
    travelDay: string;
  },
): FogStateDto {
  const objects: FogObjectDto[] = map.objects.map((obj) => {
    const prog = run.objects[obj.id] ?? {};
    if (obj.kind === "chest") {
      return {
        id: obj.id,
        kind: "chest",
        x: obj.x,
        y: obj.y,
        opened: prog.opened === true,
      };
    }
    if (obj.kind === "monster") {
      return {
        id: obj.id,
        kind: isFogExit(obj) ? "exit" : "monster",
        x: obj.x,
        y: obj.y,
        name: obj.name,
        defeated: prog.defeated === true,
        ...(isFogExit(obj) ? { passed: prog.defeated === true } : {}),
      };
    }
    return {
      id: obj.id,
      kind: "event",
      x: obj.x,
      y: obj.y,
      title: obj.title,
      done: prog.done === true,
      options: obj.options.map((o) => ({
        id: o.id,
        label: o.label,
        effect: o.effect,
      })),
    };
  });
  const dto = {
    mapId: map.id,
    displayName: map.displayName,
    rows: map.rows,
    cols: map.cols,
    pos: { x: run.posX, y: run.posY },
    revealed: [...run.revealed].sort(),
    blocks: map.blocks.map((b) => ({ x: b.x, y: b.y })),
    objects,
    travelPoints: run.travelPoints,
    travelPointsMax: config.travelPointsMax,
    travelDay: run.travelDay,
    collect: collectOf(map, run.objects),
    ...explorationOf(map, run.revealed),
  };
  return {
    ...dto,
    protocol: "fog-step-v1",
    revision: createHash("sha256").update(JSON.stringify(dto)).digest("hex"),
  };
}

async function persistRun(
  tx: Tx,
  playerId: string,
  mapId: string,
  run: {
    posX: number;
    posY: number;
    revealed: Set<string>;
    objects: ObjectProgress;
    travelPoints: number;
    travelDay: string;
  },
  now: Date,
) {
  await tx
    .update(playerFogRuns)
    .set({
      posR: run.posY,
      posC: run.posX,
      revealed: [...run.revealed],
      objects: run.objects,
      travelPoints: run.travelPoints,
      travelDay: run.travelDay,
      updatedAt: now,
    })
    .where(and(eq(playerFogRuns.playerId, playerId), eq(playerFogRuns.mapId, mapId)));
}

async function grantSkillBook(tx: Tx, world: World, playerId: string, skillSlug: string, source: string, now: Date) {
  const skill =
    world.skills.find((s) => s.slug === skillSlug) ??
    (await tx.select().from(contentSkills).where(eq(contentSkills.slug, skillSlug)).limit(1))[0];
  if (!skill) return null;
  const displayName = `${skill.displayName ?? skill.slug}技能书`;
  let bookSlug =
    world.items.find((i) => i.kind === "skill_book" && i.skillSlug === skill.slug)?.slug ??
    (await tx.select().from(contentItems).where(eq(contentItems.skillSlug, skill.slug)).limit(1))[0]?.slug;
  if (!bookSlug) {
    bookSlug = `book_fog_${skill.slug}`;
    await tx
      .insert(contentItems)
      .values({
        slug: bookSlug,
        displayName,
        kind: "skill_book",
        skillSlug: skill.slug,
        stackable: false,
        description: `使用后学会技能「${skill.displayName ?? skill.slug}」`,
        updatedAt: now,
      })
      .onConflictDoNothing();
  }
  await tx.insert(playerItems).values({
    playerId,
    itemSlug: bookSlug,
    isStack: false,
    quantity: 1,
    source,
    acquiredAt: now,
  });
  return { itemSlug: bookSlug, quantity: 1, displayName };
}

async function grantLoot(
  tx: Tx,
  world: World,
  playerId: string,
  loot: FogLoot[],
  source: string,
  now: Date,
  opts?: { skillBookSkillSlug?: string; grantSkillBook?: boolean },
): Promise<{ itemSlug: string; quantity: number; displayName: string }[]> {
  const gained: { itemSlug: string; quantity: number; displayName: string }[] = [];
  for (const row of loot) {
    const def = world.items.find((i) => i.slug === row.itemSlug);
    await addStack(tx, playerId, row.itemSlug, row.quantity, source, now);
    gained.push({ itemSlug: row.itemSlug, quantity: row.quantity, displayName: def?.displayName ?? row.itemSlug });
  }
  const skillSlug = opts?.skillBookSkillSlug ?? (opts?.grantSkillBook ? "skill_tuna" : undefined);
  if (skillSlug) {
    const book = await grantSkillBook(tx, world, playerId, skillSlug, source, now);
    if (book) gained.push(book);
  }
  return gained;
}

async function playerFighter(tx: Tx, world: World, playerId: string) {
  const [state] = await tx.select().from(playerStates).where(eq(playerStates.playerId, playerId)).limit(1);
  if (!state) throw new AppError("NOT_FOUND", "角色不存在");
  const items = await tx.select().from(playerItems).where(eq(playerItems.playerId, playerId));
  const skills = await tx.select().from(playerSkills).where(eq(playerSkills.playerId, playerId));
  const equipped = items.filter((row) => row.equippedSlot).map((row) => ({ slug: row.itemSlug, enhanceLevel: row.enhanceLevel }));
  const running = skills.filter((row) => row.runningSlot).map((row) => ({ slug: row.skillSlug, level: row.level }));
  const stats = combatStats(world, state.realmSlug, equipped, running);
  const combatSkills = toCombatSkills(
    skills.map((s) => ({ skillSlug: s.skillSlug, runningSlot: s.runningSlot })),
    world.skills,
    openSkillSlotsFor(world, state.realmSlug),
  );
  return {
    side: { attack: stats.attack, defense: stats.defense, hp: stats.hp, interval: stats.interval },
    skills: combatSkills,
    power: stats.power,
  };
}

export async function readFogState(tx: Tx, world: World, playerId: string, mapId: string | undefined, now: Date) {
  // GET may initialize/refill/upgrade a run: serialize it with move/interact.
  await tx.select({ playerId: playerStates.playerId }).from(playerStates).where(eq(playerStates.playerId, playerId)).for("update");
  const config = fogOf(world);
  const id = mapId && mapId.length > 0 ? mapId : config.defaultMapId;
  let map: FogMapConfig;
  try {
    map = fogMapOf(config, id);
  } catch {
    throw new AppError("NOT_FOUND", "秘境不存在");
  }
  const run = await refreshTravel(tx, playerId, id, config, now);
  return { fog: toDto(config, map, run) };
}

export async function moveFog(
  tx: Tx,
  world: World,
  playerId: string,
  mapId: string,
  input: { x: number; y: number },
  now: Date,
) {
  await tx.select({ playerId: playerStates.playerId }).from(playerStates).where(eq(playerStates.playerId, playerId)).for("update");
  await requireNoCombat(tx, playerId);
  const config = fogOf(world);
  const map = fogMapOf(config, mapId);
  const run = await refreshTravel(tx, playerId, mapId, config, now);
  const tx_ = Math.floor(Number(input.x));
  const ty = Math.floor(Number(input.y));
  if (!Number.isFinite(tx_) || !Number.isFinite(ty)) {
    throw new AppError("INVALID_INPUT", "目标格子不正确");
  }
  const adj = neighbors4(run.posX, run.posY).some((n) => n.x === tx_ && n.y === ty);
  if (!adj) throw new AppError("INVALID_INPUT", "只能走到相邻格子");
  if (isBlocked(map, tx_, ty)) throw new AppError("FOG_CELL_BLOCKED");
  if (livingMonsterAt(map, run.objects, tx_, ty)) {
    throw new AppError("FOG_CELL_BLOCKED", "有妖物挡路，先交战");
  }
  const cost = config.travelCostPerStep;
  if (run.travelPoints < cost) throw new AppError("FOG_TRAVEL_EMPTY", "游历点不足，明日再来");
  run.travelPoints -= cost;
  run.posX = tx_;
  run.posY = ty;
  revealAround(run.revealed, map, tx_, ty, config.revealRadius);
  await persistRun(tx, playerId, mapId, run, now);
  return { fog: toDto(config, map, run) };
}

/** 邻格或同格可交互 */
function canReachObject(run: { posX: number; posY: number }, x: number, y: number): boolean {
  if (run.posX === x && run.posY === y) return true;
  return neighbors4(run.posX, run.posY).some((n) => n.x === x && n.y === y);
}

export async function interactFog(
  tx: Tx,
  world: World,
  playerId: string,
  mapId: string,
  input: { objectId: string; optionId?: string },
  now: Date,
) {
  await tx
    .select({ playerId: playerStates.playerId })
    .from(playerStates)
    .where(eq(playerStates.playerId, playerId))
    .for("update");
  await requireNoCombat(tx, playerId);
  const config = fogOf(world);
  const map = fogMapOf(config, mapId);
  const run = await refreshTravel(tx, playerId, mapId, config, now);
  const obj = map.objects.find((o) => o.id === input.objectId);
  if (!obj) throw new AppError("INVALID_INPUT", "没有这个物件");
  if (!canReachObject(run, obj.x, obj.y))
    throw new AppError("INVALID_INPUT", "请先走到附近");
  if (!run.revealed.has(cellKey(obj.x, obj.y)))
    throw new AppError("INVALID_INPUT", "迷雾未散，看不清");

  if (obj.kind === "chest") {
    const prog = run.objects[obj.id] ?? {};
    if (prog.opened) throw new AppError("FOG_OBJECT_GONE", "宝箱已经打开过了");
    const gained = await grantLoot(
      tx,
      world,
      playerId,
      obj.loot,
      "fog_chest",
      now,
      {
        grantSkillBook: obj.grantSkillBook === true,
      },
    );
    run.objects[obj.id] = { ...prog, opened: true };
    await persistRun(tx, playerId, mapId, run, now);
    return { fog: toDto(config, map, run), gained, kind: "chest" as const };
  }

  if (obj.kind === "event") {
    const prog = run.objects[obj.id] ?? {};
    if (prog.done) throw new AppError("FOG_OBJECT_GONE", "这件事已经过去了");
    const optionId = input.optionId;
    if (!optionId) {
      return {
        fog: toDto(config, map, run),
        kind: "event_prompt" as const,
        event: { id: obj.id, title: obj.title, options: obj.options },
      };
    }
    const opt = obj.options.find((o) => o.id === optionId);
    if (!opt) throw new AppError("INVALID_INPUT", "没有这个选项");
    if (opt.effect === "none") {
      run.objects[obj.id] = { ...prog, done: true };
      await persistRun(tx, playerId, mapId, run, now);
      return {
        fog: toDto(config, map, run),
        gained: [],
        kind: "event_leave" as const,
      };
    }
    // battle：返回需开战标记；真正结算走 battleFog with objectId=e_herb
    return {
      fog: toDto(config, map, run),
      kind: "event_battle" as const,
      event: { id: obj.id, title: obj.title, enemy: obj.battleEnemy },
    };
  }

  if (obj.kind === "monster") {
    if (isFogExit(obj) && !explorationOf(map, run.revealed).exploreFull)
      throw new AppError("INVALID_INPUT", "还要再探索一下才能走这个出口");
    const prog = run.objects[obj.id] ?? {};
    if (prog.defeated) throw new AppError("FOG_OBJECT_GONE", "已经击败过了");
    // 客户端先弹确认气泡；此接口仅用于校验可达。真正开战 POST battle。
    return {
      fog: toDto(config, map, run),
      kind: "monster_prompt" as const,
      monster: { id: obj.id, name: obj.name },
    };
  }

  throw new AppError("INVALID_INPUT");
}

export async function battleFog(
  tx: Tx,
  world: World,
  playerId: string,
  mapId: string,
  input: { objectId: string },
  now: Date,
  options: { preview?: boolean; resolvedBattle?: BattleResult } = {},
) {
  await tx
    .select({ playerId: playerStates.playerId })
    .from(playerStates)
    .where(eq(playerStates.playerId, playerId))
    .for("update");
  if (!options.resolvedBattle) await requireNoCombat(tx, playerId);
  const config = fogOf(world);
  const map = fogMapOf(config, mapId);
  const run = await refreshTravel(tx, playerId, mapId, config, now);
  const obj = map.objects.find((o) => o.id === input.objectId);
  if (!obj) throw new AppError("INVALID_INPUT", "没有这个目标");
  if (!canReachObject(run, obj.x, obj.y))
    throw new AppError("INVALID_INPUT", "请先走到附近");

  let monsterSide: {
    attack: number;
    defense: number;
    hp: number;
    interval: number;
  };
  let monsterName: string;
  let loot: FogLoot[];
  let skillBookSkillSlug: string | undefined;
  const grantSkillBook = false;
  let onWin: () => void;

  if (obj.kind === "monster") {
    if (isFogExit(obj) && !explorationOf(map, run.revealed).exploreFull)
      throw new AppError("INVALID_INPUT", "还要再探索一下才能走这个出口");
    const prog = run.objects[obj.id] ?? {};
    if (prog.defeated) throw new AppError("FOG_OBJECT_GONE", "已经击败过了");
    const m = obj as FogMonsterObject;
    monsterSide = {
      attack: m.attack,
      defense: m.defense,
      hp: m.hp,
      interval: m.interval,
    };
    monsterName = m.name;
    loot = m.loot;
    skillBookSkillSlug = m.skillBookSkillSlug;
    onWin = () => {
      run.objects[obj.id] = { ...prog, defeated: true };
    };
  } else if (obj.kind === "event") {
    const prog = run.objects[obj.id] ?? {};
    if (prog.done) throw new AppError("FOG_OBJECT_GONE", "这件事已经过去了");
    const e = obj as FogEventObject;
    const enemy = e.battleEnemy;
    monsterSide = {
      attack: enemy.attack,
      defense: enemy.defense,
      hp: enemy.hp,
      interval: enemy.interval,
    };
    monsterName = enemy.name;
    loot = enemy.loot;
    onWin = () => {
      run.objects[obj.id] = { ...prog, done: true };
    };
  } else {
    throw new AppError("INVALID_INPUT", "不能对这个开战");
  }

  const fighter = await playerFighter(tx, world, playerId);
  const runtime = runtimeConfigOf(world.globals.tuning?.battle);
  const skills = configuredSkills(fighter.skills, runtime);
  const playerSide = { ...fighter.side, ...combatTraits(skills, runtime) };
  // Fog owns its enemy/loot/time limit, sharing only damage rules and playback.
  const timeLimitSeconds = map.timeLimitSeconds ?? runtime.fogTimeLimitSeconds;
  const battle =
    options.resolvedBattle ??
    simulateBattle(
      playerSide,
      monsterSide,
      { ...battleConfigOf(world), timeLimitSeconds, rage: runtime.rage },
      skills,
    );

  let gained: { itemSlug: string; quantity: number; displayName: string }[] =
    [];
  if (battle.win && !options.preview) {
    gained = await grantLoot(tx, world, playerId, loot, "fog_battle", now, {
      skillBookSkillSlug,
      grantSkillBook,
    });
    onWin();
    await persistRun(tx, playerId, mapId, run, now);
  }

  return {
    fog: toDto(config, map, run),
    playback: {
      player: playerSide,
      monster: { id: obj.id, name: monsterName, ...monsterSide },
      timeLimitSeconds,
      rageMax: runtime.rage.max,
      speeds: runtime.speeds,
      canSkip: false,
    },
    win: battle.win,
    reason: battle.reason,
    durationSeconds: battle.durationSeconds,
    log: battle.log,
    gained,
    monster: { id: obj.id, name: monsterName, ...monsterSide },
    player: { ...fighter.side, power: fighter.power },
  };
}

export async function ensureFogGlobals(tx: Tx, config: FogConfig = requireFog(null)) {
  const [row] = await tx.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  if (!row) return;
  if (!row.fog) {
    await tx.update(contentGlobals).set({ fog: config, updatedAt: new Date() }).where(eq(contentGlobals.id, 1));
  }
}
