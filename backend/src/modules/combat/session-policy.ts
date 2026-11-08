import { AppError } from "../../shared/errors.js";
import type { BattleResult } from "./battle.js";
export type FinishMode = "complete" | "skip" | "retreat" | "recover";
export function finishDecision(battle: BattleResult, mode: FinishMode, canSkip: boolean, elapsedSeconds: number, maxSpeed: number): BattleResult {
  if (mode === "retreat") return { ...battle, win: false, reason: "retreat", durationSeconds: Math.min(battle.durationSeconds, Math.max(0, elapsedSeconds)), log: [] };
  if (mode === "skip" && !canSkip) throw new AppError("INVALID_INPUT", "首次挑战请先看完战斗");
  if (mode === "complete" && elapsedSeconds + 0.25 < battle.durationSeconds / Math.max(1, maxSpeed)) throw new AppError("INVALID_INPUT", "战斗还未结束");
  return battle;
}
