import { AppError } from "../../shared/errors.js";
import { bossPower } from "../combat/stats.js";
import { readGameRules } from "./rules.js";
import type { ContentSnapshot } from "./validate.js";

type Stage = ContentSnapshot["stages"][number];

/** 推荐战力按谁算：有首领按首领，没有首领按普通怪（和首领同一个公式）。 */
export function stagePowerSource(stage: Stage): { kind: "boss" | "monster"; name: string; attack: number; defense: number; hp: number; interval: number } | null {
  const boss = stage.bosses?.[0];
  if (boss) {
    return { kind: "boss", name: boss.name, attack: boss.attack, defense: boss.defense, hp: boss.hp, interval: boss.interval };
  }
  const monster = stage.monsters?.[0];
  if (monster) {
    return { kind: "monster", name: monster.name, attack: monster.attack, defense: monster.defense, hp: monster.hp, interval: monster.interval };
  }
  return null;
}

/** 首领（或普通怪）战力，乘推荐战力倍数之前的原始值。 */
export function stageRawPower(world: ContentSnapshot, stage: Stage): number {
  const source = stagePowerSource(stage);
  if (!source) {
    throw new AppError("INVALID_INPUT", "这个关卡还没有首领和普通怪");
  }
  const realm = world.realms.find((row) => row.sortOrder === stage.requiredRealmOrder);
  if (!realm) {
    throw new AppError("INVALID_INPUT", "关卡的境界不存在");
  }
  const rules = readGameRules(world);
  return bossPower(source, { baseInterval: rules.baseInterval, speedBase: rules.speedBase, weights: rules.powerWeights });
}

function priceStage(world: ContentSnapshot, stage: Stage): { realmOrder: number; power: number } {
  const boss = stagePowerSource(stage);
  if (!boss) {
    throw new AppError("INVALID_INPUT", "这个关卡还没有首领");
  }
  const name = stage.displayName ?? stage.slug;
  const realm = world.realms.find((row) => row.sortOrder === stage.requiredRealmOrder);
  if (!realm || realm.sortOrder === undefined) {
    throw new AppError("INVALID_INPUT", `关卡「${name}」的境界不存在`);
  }
  const rules = readGameRules(world);
  const raw = bossPower(boss, { baseInterval: rules.baseInterval, speedBase: rules.speedBase, weights: rules.powerWeights });
  return { realmOrder: realm.sortOrder, power: Math.round(raw * rules.recommendedPowerMargin) };
}

/** 按首领（没有首领时按普通怪）数值算出的推荐战力（战力 × 推荐战力倍数）。没有手动覆盖时用它。 */
export function stageAutoPower(world: ContentSnapshot, stage: Stage): number {
  return priceStage(world, stage).power;
}

/**
 * 玩家看到的推荐战力：以后台为每个关卡手填的值为准（设计表 2.3：参考配置总战力 × 0.95）。
 * 填 0 表示“没有手填，按首领数值自动算”。服务器不会再用自动值覆盖手填值。
 */
export function stageRecommendedPower(world: ContentSnapshot, stage: Stage): number {
  const manual = Math.round(Number(stage.recommendedPower ?? 0));
  return manual > 0 ? manual : stageAutoPower(world, stage);
}

export function stagePowerErrors(world: ContentSnapshot): { slug: string; message: string }[] {
  const errors: { slug: string; message: string }[] = [];
  const priced: { stage: Stage; realmOrder: number; power: number }[] = [];
  for (const stage of world.stages) {
    if (!stage.bosses?.[0]) {
      continue;
    }
    try {
      priced.push({ stage, realmOrder: stage.requiredRealmOrder ?? 0, power: stageRecommendedPower(world, stage) });
    } catch (cause) {
      if (!(cause instanceof AppError)) {
        throw cause;
      }
      errors.push({ slug: stage.slug, message: cause.message });
    }
  }
  // 只在同一档首领之间比（第三批：精英按小怪 × 倍率自动算，章末首领是手填的，两档本来就不在一条曲线上）
  for (const tier of ["elite", "chief"] as const) {
    const group = priced.filter((row) => (row.stage.tier ?? "chief") === tier);
    const orders = [...new Set(group.map((row) => row.realmOrder))].sort((left, right) => left - right);
    for (let index = 1; index < orders.length; index += 1) {
      const lower = group.filter((row) => row.realmOrder === orders[index - 1]);
      const strongest = lower.reduce((best, row) => (row.power > best.power ? row : best));
      for (const row of group.filter((candidate) => candidate.realmOrder === orders[index])) {
        if (row.power <= strongest.power) {
          errors.push({
            slug: row.stage.slug,
            message: `推荐战力 ${row.power} 不高于低一个境界的关卡「${strongest.stage.displayName ?? strongest.stage.slug}」的 ${strongest.power}`,
          });
        }
      }
    }
  }
  return errors;
}
