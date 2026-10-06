export function piecePower(stats: {
  attack: number;
  defense: number;
  hp: number;
  speed: number;
}): number {
  return stats.attack + stats.defense * 0.8 + stats.speed * 1.5 + stats.hp * 0.04;
}
