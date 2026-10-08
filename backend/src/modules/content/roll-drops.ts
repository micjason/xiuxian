export type DropEntry = { itemSlug: string; chanceBp: number; minQty: number; maxQty: number };

export function rollDropTable(
  entries: DropEntry[],
  randomInt: (min: number, max: number) => number,
): { itemSlug: string; quantity: number }[] {
  const grants: { itemSlug: string; quantity: number }[] = [];
  for (const entry of entries) {
    if (randomInt(0, 10000) >= entry.chanceBp) {
      continue;
    }
    const quantity = entry.minQty === entry.maxQty ? entry.minQty : randomInt(entry.minQty, entry.maxQty + 1);
    grants.push({ itemSlug: entry.itemSlug, quantity });
  }
  return grants;
}
