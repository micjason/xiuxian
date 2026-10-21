import type { SetStat, SetTier } from "./combat-types.js";
import type { ContentSnapshot } from "./validate.js";

type Stats = Record<SetStat, number>;

export type ActiveSet = {
  setSlug: string;
  displayName: string;
  /** 身上穿着的这个套装的件数 */
  worn: number;
  /** 已生效的档位（件数） */
  activePieces: number[];
};

export type SetBonus = {
  /** 百分比合计（6 = +6%），按角色总属性算 */
  pct: Stats;
  /** 固定值合计，直接加 */
  flat: Stats;
  sets: ActiveSet[];
};

const zero = (): Stats => ({ attack: 0, defense: 0, hp: 0, speed: 0 });

/**
 * 穿着的装备凑成的套装加成：每个套装数身上穿着的成员件数，穿够的档位全部生效（叠加）。
 * 同一件装备穿两次（不可能）也只算一件。
 */
export function setBonusOf(world: Pick<ContentSnapshot, "items" | "gearSets">, equippedSlugs: string[]): SetBonus {
  const bonus: SetBonus = { pct: zero(), flat: zero(), sets: [] };
  const sets = world.gearSets ?? [];
  if (sets.length === 0) {
    return bonus;
  }
  const worn = new Map<string, Set<string>>();
  for (const slug of equippedSlugs) {
    const setSlug = world.items.find((item) => item.slug === slug)?.setSlug;
    if (setSlug) {
      worn.set(setSlug, (worn.get(setSlug) ?? new Set()).add(slug));
    }
  }
  for (const set of sets) {
    const count = worn.get(set.slug)?.size ?? 0;
    if (count === 0) {
      continue;
    }
    const active = activeTiers(set.tiers, count);
    for (const tier of active) {
      for (const row of tier.stats) {
        bonus[row.mode === "pct" ? "pct" : "flat"][row.stat] += row.value;
      }
    }
    bonus.sets.push({ setSlug: set.slug, displayName: set.displayName, worn: count, activePieces: active.map((tier) => tier.pieces) });
  }
  return bonus;
}

export function activeTiers(tiers: SetTier[], worn: number): SetTier[] {
  return [...tiers].filter((tier) => worn >= tier.pieces).sort((left, right) => left.pieces - right.pieces);
}

/** 把套装加成加到总属性上：总属性 × (1 + 百分比) + 固定值。 */
export function applySetBonus(stats: Stats, bonus: SetBonus): Stats {
  return {
    attack: stats.attack * (1 + bonus.pct.attack / 100) + bonus.flat.attack,
    defense: stats.defense * (1 + bonus.pct.defense / 100) + bonus.flat.defense,
    hp: stats.hp * (1 + bonus.pct.hp / 100) + bonus.flat.hp,
    speed: stats.speed * (1 + bonus.pct.speed / 100) + bonus.flat.speed,
  };
}
