import { AppError } from "../../shared/errors.js";
import { FEATURED_SLOTS, gearSlug, schemeBookSlugs } from "./numeric-scheme.js";

const QUALITY_WEIGHTS = [
  ["white", 60],
  ["green", 25],
  ["blue", 10],
  ["purple", 4],
  ["orange", 1],
] as const;

const QUALITY_CULTIVATION = { white: 1, green: 2, blue: 4, purple: 8, orange: 16 } as const;
const RANK_CULTIVATION = { yellow: 1, xuan: 2, earth: 4, heaven: 8 } as const;

export type SchemeGrant = { slug: string; kind: "gear" | "book" | "upgrade" };

function pickQuality(randomInt: (min: number, max: number) => number): string {
  const roll = randomInt(0, 100);
  let cursor = 0;
  for (const [quality, weight] of QUALITY_WEIGHTS) {
    cursor += weight;
    if (roll < cursor) {
      return quality;
    }
  }
  return "orange";
}

export function rollSchemeReward(input: {
  major: string;
  nextMajor: string | null;
  stageIndex: number;
  firstClear: boolean;
  pity: Record<string, number>;
  randomInt: (min: number, max: number) => number;
}): { grants: SchemeGrant[]; pity: Record<string, number> } {
  const pity = { ...input.pity };
  const grants: SchemeGrant[] = [];
  const slot = FEATURED_SLOTS[input.stageIndex % FEATURED_SLOTS.length];
  if (!slot) {
    throw new AppError("INVALID_INPUT", "这个关卡还没有掉落部位");
  }
  if (input.firstClear) {
    const quality = input.randomInt(0, 10000) < 7000 ? "white" : "green";
    grants.push({ slug: gearSlug(input.major, slot, quality), kind: "gear" });
  }
  const orangeKey = `${input.major}:orange`;
  const orangeEvery = input.stageIndex < 3 ? 200 : 800;
  const orangeMisses = pity[orangeKey] ?? 0;
  if (orangeMisses + 1 >= orangeEvery) {
    grants.push({ slug: gearSlug(input.major, slot, "orange"), kind: "gear" });
    pity[orangeKey] = 0;
  } else if (input.randomInt(0, 10000) < (input.stageIndex < 3 ? 10000 : 2500)) {
    const quality = pickQuality(input.randomInt);
    grants.push({ slug: gearSlug(input.major, slot, quality), kind: "gear" });
    pity[orangeKey] = quality === "orange" ? 0 : orangeMisses + 1;
  } else {
    pity[orangeKey] = orangeMisses + 1;
  }
  const bookKey = `${input.major}:book`;
  const bookMisses = pity[bookKey] ?? 0;
  const books = schemeBookSlugs(input.major);
  const grantBook = () => {
    const slug = books[input.randomInt(0, books.length)];
    if (!slug) {
      throw new AppError("INVALID_INPUT", "这个境界还没有功法书");
    }
    grants.push({ slug, kind: "book" });
    pity[bookKey] = 0;
  };
  if (bookMisses + 1 >= 25) {
    grantBook();
  } else if (input.randomInt(0, 10000) < 800) {
    grantBook();
  } else {
    pity[bookKey] = bookMisses + 1;
  }
  if (input.nextMajor && input.randomInt(0, 10000) < 100) {
    grants.push({ slug: gearSlug(input.nextMajor, "weapon", "white"), kind: "upgrade" });
  }
  return { grants, pity };
}

function secondsCultivation(factor: number, gainPerTick: number): number {
  if (!(gainPerTick > 0)) {
    throw new AppError("INVALID_INPUT", "请先在后台填写：每秒修为");
  }
  return Math.round(30 * gainPerTick * factor);
}

export function decomposeCultivation(quality: string, gainPerTick: number): number {
  const factor = QUALITY_CULTIVATION[quality as keyof typeof QUALITY_CULTIVATION];
  if (factor === undefined) {
    throw new AppError("INVALID_INPUT", "这件装备还没有品质");
  }
  return secondsCultivation(factor, gainPerTick);
}

export function bookOverflowCultivation(rank: string | null | undefined, gainPerTick: number): number {
  const factor = RANK_CULTIVATION[rank as keyof typeof RANK_CULTIVATION];
  if (factor === undefined) {
    throw new AppError("INVALID_INPUT", "请先在后台填写：功法品阶");
  }
  return secondsCultivation(factor, gainPerTick);
}
