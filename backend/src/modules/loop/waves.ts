import { randomInt as cryptoRandomInt } from "node:crypto";
import type { Tx } from "../../db/tx.js";
import { advanceWaves, waveCycle, type WaveCycle } from "../combat/wave.js";
import { dropMultsOf, rollMonsterKillDrop } from "../content/monster-drops.js";
import type { StageMonster } from "../content/combat-types.js";
import type { ContentSnapshot } from "../content/validate.js";
import type { GameRules } from "../content/rules.js";
import { grantItem } from "./bag.js";

type World = ContentSnapshot & { version: number };
type Stage = ContentSnapshot["stages"][number];
type RandomInt = (min: number, max: number) => number;

/**
 * 结算时掷骰用的随机数来源。结算在很多入口都会发生（GET /me/state、/me、各种操作前后），
 * 一个个传参数太散，所以放在模块里，由 app.ts 在启动时用注入的 randomInt 设置；测试里注入固定序列即可。
 */
let waveRandom: RandomInt = (min, max) => cryptoRandomInt(min, max);
export function setWaveRandom(fn: RandomInt): void {
  waveRandom = fn;
}

/** 可以刷怪的关卡：启用、配了普通怪、境界够得着。 */
export function farmableStages(world: World, realmOrder: number): Stage[] {
  return world.stages.filter((stage) => stage.enabled && (stage.monsters?.length ?? 0) > 0 && stage.requiredRealmOrder != null && stage.requiredRealmOrder <= realmOrder);
}

/**
 * 现在在哪个关卡刷怪：玩家选过（idleStageSlug）且还有效就用它，否则用境界够得着的最高关卡（突破后自动换到新关卡）。
 * 没有可刷的关卡就返回 null（这个世界没配普通怪，或者玩家境界太低）。
 */
export function resolveFarmStage(world: World, realmOrder: number, idleStageSlug: string | null): Stage | null {
  const candidates = farmableStages(world, realmOrder);
  if (candidates.length === 0) {
    return null;
  }
  const chosen = idleStageSlug ? candidates.find((stage) => stage.slug === idleStageSlug) : undefined;
  if (chosen) {
    return chosen;
  }
  return [...candidates].sort((left, right) => (right.requiredRealmOrder ?? 0) - (left.requiredRealmOrder ?? 0) || (right.sortOrder ?? 0) - (left.sortOrder ?? 0))[0] ?? null;
}

export type WaveDrop = {
  itemSlug: string;
  quality: string | null;
  /** 行囊满，新掉落的白/绿直接分解成了强化经验。 */
  decomposed: boolean;
  /** 行囊满且腾不出格子（或自动分解关着），这件没掉。 */
  dropped: boolean;
  /** 为了放下这件蓝/紫，分解了包里的几件白/绿。 */
  freed: { itemSlug: string; enhanceExp: number }[];
  enhanceExp: number;
  /** 这件来自关卡的指定掉落（不是随机掉落）。 */
  designated?: boolean;
};

export type WaveSettlement = {
  /** 这次结算是不是在线（距离上次结算不超过 onlineGapSeconds）。 */
  online: boolean;
  stageSlug: string | null;
  monsterName: string | null;
  kills: number;
  deaths: number;
  killCultivation: number;
  drops: WaveDrop[];
  bagFull: boolean;
  progress: number;
  deathsInRow: number;
};

export const EMPTY_WAVES: WaveSettlement = { online: false, stageSlug: null, monsterName: null, kills: 0, deaths: 0, killCultivation: 0, drops: [], bagFull: false, progress: 0, deathsInRow: 0 };

export function cycleFor(rules: GameRules, stats: { attack: number; defense: number; hp: number; interval: number }, monster: StageMonster): WaveCycle {
  return waveCycle(
    { attack: stats.attack, defense: stats.defense, hp: stats.hp, interval: stats.interval },
    { attack: monster.attack, defense: monster.defense, hp: monster.hp, interval: monster.interval },
    { waveSize: rules.waveSize, transitionSeconds: rules.waveTransitionSeconds, reviveSeconds: rules.reviveSeconds, defenseConstant: rules.defenseConstant },
  );
}

/**
 * 在线 consumedSeconds 秒内的普通怪波次：确定性推进击杀/阵亡（见 combat/wave.ts），
 * 每次击杀给固定修为（整数、不吃功法加成），并按“每只 chanceBp 万分比、品质按区域权重、6 部位等概率”掷装备。
 * 掉落走行囊规则（grantItem）：满包时白/绿直接分解，蓝/紫腾格，腾不出则不掉并标记 bagFull。
 */
export async function settleWaves(
  tx: Tx,
  world: World,
  playerId: string,
  input: {
    rules: GameRules;
    stage: Stage;
    stats: { attack: number; defense: number; hp: number; interval: number };
    progress: number;
    deathsInRow: number;
    consumedSeconds: number;
    autoDecompose: boolean;
    capacity: number;
    now: Date;
  },
): Promise<WaveSettlement> {
  const monster = input.stage.monsters?.[0];
  if (!monster) {
    return { ...EMPTY_WAVES, online: true };
  }
  const cycle = cycleFor(input.rules, input.stats, monster);
  const advance = advanceWaves(input.progress, input.consumedSeconds, cycle, input.deathsInRow);
  const drops: WaveDrop[] = [];
  let bagFull = false;
  // 掉落的装备阶：关卡所属境界的大境界（炼气关刷炼气阶装备）。
  const majorKey = world.realms.find((row) => row.sortOrder === input.stage.requiredRealmOrder)?.majorKey ?? null;
  if (advance.kills > 0 && majorKey) {
    const multOf = dropMultsOf(world.items, world.realms);
    for (let index = 0; index < advance.kills; index += 1) {
      const rolled = rollMonsterKillDrop(majorKey, input.stage.monsterDrop, waveRandom, multOf);
      if (!rolled || !world.items.some((item) => item.slug === rolled.slug)) {
        continue;
      }
      const granted = await grantItem(tx, world, playerId, rolled.slug, 1, `wave:${input.stage.slug}`, input.now, {
        autoDecompose: input.autoDecompose,
        capacity: input.capacity,
      });
      drops.push({
        itemSlug: rolled.slug,
        quality: rolled.quality,
        decomposed: granted.decomposed > 0,
        dropped: granted.dropped > 0,
        freed: granted.freed,
        enhanceExp: granted.enhanceExp,
      });
      if (granted.dropped > 0) {
        bagFull = true;
      }
    }
  }
  // 指定掉落（普通怪每只）：和随机掉落同时生效，每条单独按概率抽；走同样的行囊规则。
  const designated = (input.stage.designatedDrops ?? []).filter((row) => row.trigger === "monster" && row.chanceBp > 0 && world.items.some((item) => item.slug === row.itemSlug));
  if (advance.kills > 0 && designated.length > 0) {
    for (let index = 0; index < advance.kills; index += 1) {
      for (const row of designated) {
        if (waveRandom(0, 10000) >= row.chanceBp) {
          continue;
        }
        const definition = world.items.find((item) => item.slug === row.itemSlug);
        const granted = await grantItem(tx, world, playerId, row.itemSlug, row.count, `wave:${input.stage.slug}`, input.now, {
          autoDecompose: input.autoDecompose,
          capacity: input.capacity,
          grant: { source: "stage_drop", sourceRef: input.stage.slug },
        });
        drops.push({
          itemSlug: row.itemSlug,
          quality: definition?.quality ?? null,
          decomposed: granted.decomposed > 0,
          dropped: granted.dropped > 0,
          freed: granted.freed,
          enhanceExp: granted.enhanceExp,
          designated: true,
        });
        if (granted.dropped > 0) {
          bagFull = true;
        }
      }
    }
  }
  return {
    online: true,
    stageSlug: input.stage.slug,
    monsterName: monster.name,
    kills: advance.kills,
    deaths: advance.deaths,
    killCultivation: advance.kills * monster.killCultivation,
    drops,
    bagFull,
    progress: advance.progress,
    deathsInRow: advance.deathsInRow,
  };
}
