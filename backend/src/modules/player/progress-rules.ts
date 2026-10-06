export function settleCultivation(input: {
  cultivation: number;
  elapsedSeconds: number;
  gainPerSecond: number;
  offlineCapSeconds: number;
}): { cultivation: number; countedSeconds: number; gained: number } {
  const countedSeconds = Math.max(0, Math.min(input.elapsedSeconds, input.offlineCapSeconds));
  const gained = countedSeconds * input.gainPerSecond;
  return {
    cultivation: input.cultivation + gained,
    countedSeconds,
    gained,
  };
}

export function breakthrough(input: {
  cultivation: number;
  cost: number;
  nextSlug: string | null;
}): { ok: true; cultivation: number; nextSlug: string } | { ok: false; reason: "not_enough" | "max_realm" } {
  if (input.nextSlug === null) {
    return { ok: false, reason: "max_realm" };
  }
  if (input.cultivation < input.cost) {
    return { ok: false, reason: "not_enough" };
  }
  return {
    ok: true,
    cultivation: input.cultivation - input.cost,
    nextSlug: input.nextSlug,
  };
}
