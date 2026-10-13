import { AppError } from "../../shared/errors.js";
import { bossPower } from "../combat/stats.js";
import { readGameRules } from "./rules.js";
import type { ContentSnapshot } from "./validate.js";

type Stage = ContentSnapshot["stages"][number];

function priceStage(world: ContentSnapshot, stage: Stage): { realmOrder: number; power: number } {
  const boss = stage.bosses?.[0];
  if (!boss) {
    throw new AppError("INVALID_INPUT", "这个关卡还没有首领");
  }
  const name = stage.displayName ?? stage.slug;
  const realm = world.realms.find((row) => row.sortOrder === stage.requiredRealmOrder);
  if (!realm || realm.sortOrder === undefined) {
    throw new AppError("INVALID_INPUT", `关卡「${name}」的境界不存在`);
  }
  if (realm.baseInterval === undefined || realm.baseInterval <= 0) {
    throw new AppError("INVALID_INPUT", `请先在后台填写境界「${realm.displayName ?? realm.slug}」的基础出手间隔`);
  }
  const rules = readGameRules(world);
  const raw = bossPower(boss, { baseInterval: realm.baseInterval, speedBase: rules.speedBase, weights: rules.powerWeights });
  return { realmOrder: realm.sortOrder, power: Math.round(raw * rules.recommendedPowerMargin) };
}

export function stageRecommendedPower(world: ContentSnapshot, stage: Stage): number {
  return priceStage(world, stage).power;
}

export function stagePowerErrors(world: ContentSnapshot): { slug: string; message: string }[] {
  const errors: { slug: string; message: string }[] = [];
  const priced: { stage: Stage; realmOrder: number; power: number }[] = [];
  for (const stage of world.stages) {
    if (!stage.bosses?.[0]) {
      continue;
    }
    try {
      priced.push({ stage, ...priceStage(world, stage) });
    } catch (cause) {
      if (!(cause instanceof AppError)) {
        throw cause;
      }
      errors.push({ slug: stage.slug, message: cause.message });
    }
  }
  const orders = [...new Set(priced.map((row) => row.realmOrder))].sort((left, right) => left - right);
  for (let index = 1; index < orders.length; index += 1) {
    const lower = priced.filter((row) => row.realmOrder === orders[index - 1]);
    const strongest = lower.reduce((best, row) => (row.power > best.power ? row : best));
    for (const row of priced.filter((candidate) => candidate.realmOrder === orders[index])) {
      if (row.power <= strongest.power) {
        errors.push({
          slug: row.stage.slug,
          message: `推荐战力 ${row.power} 不高于低一个境界的关卡「${strongest.stage.displayName ?? strongest.stage.slug}」的 ${strongest.power}`,
        });
      }
    }
  }
  return errors;
}
