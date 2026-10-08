export type DropChance = { itemSlug: string; chance: number; quantity: number };

export function assertDropChance(chance: number, quantity: number): void {
  if (!Number.isInteger(chance) || chance < 0 || chance > 100) {
    throw new Error("掉落概率必须是 0 到 100 的整数");
  }
  if (!Number.isInteger(quantity) || quantity < 1) {
    throw new Error("掉落数量必须是不小于 1 的整数");
  }
}

export function rollDrops(drops: DropChance[], random: () => number): { itemSlug: string; quantity: number }[] {
  const granted = [];
  for (const drop of drops) {
    const roll = Math.floor(random() * 100);
    if (roll < drop.chance) {
      granted.push({ itemSlug: drop.itemSlug, quantity: drop.quantity });
    }
  }
  return granted;
}
