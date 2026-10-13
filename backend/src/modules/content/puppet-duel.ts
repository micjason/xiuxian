import { inArray } from "drizzle-orm";
import { contentTrialPuppets } from "../../db/schema.js";
import { simulateBattle } from "../combat/battle.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { readGameRules } from "./rules.js";
import { loadDraftSnapshot } from "./snapshot.js";
import { presentPuppet, type PuppetView } from "./puppets.js";

export type PuppetDuel = {
  attackerId: string;
  attackerName: string;
  defenderId: string;
  defenderName: string;
  result: string;
  wins: number;
  losses: number;
  durationSeconds: number;
  fullSeconds: number | null;
};

function timesOf(value: unknown): number {
  if (value === undefined || value === null || value === "") {
    return 1;
  }
  const times = Number(value);
  if (!Number.isInteger(times) || times < 1 || times > 99) {
    throw new AppError("INVALID_INPUT", "场数要填 1 到 99 的整数");
  }
  return times;
}

function idsOf(value: unknown): string[] {
  if (!Array.isArray(value) || value.length < 2 || value.some((item) => typeof item !== "string" || !item.trim())) {
    throw new AppError("INVALID_INPUT", "请至少选择两个人偶");
  }
  const ids = value.map((item) => item.trim());
  if (new Set(ids).size !== ids.length) {
    throw new AppError("INVALID_INPUT", "人偶不能重复");
  }
  return ids;
}

function sideOf(view: PuppetView) {
  if (
    view.problem ||
    view.attack == null ||
    view.defense == null ||
    view.hp == null ||
    view.interval == null ||
    view.hp <= 0 ||
    view.interval <= 0
  ) {
    throw new AppError("INVALID_INPUT", `「${view.displayName}」还不能打：${view.problem ?? "属性不完整"}`);
  }
  return { attack: view.attack, defense: view.defense, hp: view.hp, interval: view.interval };
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export async function duelTrialPuppets(db: Db, idsValue: unknown, timesValue?: unknown) {
  const ids = idsOf(idsValue);
  const times = timesOf(timesValue);
  const world = await loadDraftSnapshot(db);
  const rules = readGameRules(world);
  const rows = await db.select().from(contentTrialPuppets).where(inArray(contentTrialPuppets.slug, ids));
  const views = ids.map((id) => {
    const row = rows.find((candidate) => candidate.slug === id);
    if (!row) {
      throw new AppError("INVALID_INPUT", "没有这个人偶");
    }
    return presentPuppet(row, world);
  });
  const sides = views.map((view) => ({ view, side: sideOf(view) }));
  const fights: PuppetDuel[] = [];
  for (const attacker of sides) {
    for (const defender of sides) {
      if (attacker.view.id === defender.view.id) {
        continue;
      }
      const capped = simulateBattle(attacker.side, defender.side, {
        timeLimitSeconds: rules.timeLimitSeconds,
        defenseConstant: rules.defenseConstant,
      });
      const full = simulateBattle(attacker.side, defender.side, {
        timeLimitSeconds: 600,
        defenseConstant: rules.defenseConstant,
      });
      const result = capped.reason === "timeout" ? "超时" : capped.win ? `${attacker.view.displayName} 胜` : `${defender.view.displayName} 胜`;
      const wins = capped.win ? times : 0;
      fights.push({
        attackerId: attacker.view.id,
        attackerName: attacker.view.displayName,
        defenderId: defender.view.id,
        defenderName: defender.view.displayName,
        result,
        wins,
        losses: times - wins,
        durationSeconds: round2(capped.durationSeconds),
        fullSeconds: capped.reason === "timeout" && full.reason !== "timeout" ? round2(full.durationSeconds) : null,
      });
    }
  }
  return { timeLimitSeconds: rules.timeLimitSeconds, times, fights };
}
