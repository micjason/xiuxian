import { ratePower } from "../combat/stats.js";

export function piecePower(
  stats: { attack: number; defense: number; hp: number; speed: number },
  weights: { attack: number; defense: number; hp: number; speed: number },
): number {
  return ratePower(stats, weights);
}
