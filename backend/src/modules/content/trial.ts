import { contentTrialPuppets } from "../../db/schema.js";
import { hitDamage, simulateBattle } from "../combat/battle.js";
import { AppError } from "../../shared/errors.js";
import type { Db } from "../operations/record.js";
import { battleConfigOf } from "../loop/actions.js";
import { loadDraftSnapshot } from "./snapshot.js";
import { presentPuppet, type PuppetView } from "./puppets.js";

export type TrialInput = {
  puppetIds?: string[];
  boss?: { attack?: number; defense?: number; hp?: number; interval?: number };
};

export type TrialPuppetResult = {
  puppetId: string;
  displayName: string;
  kindName: string;
  error: string | null;
  win: boolean | null;
  reason: "win" | "defeated" | "timeout" | null;
  durationSeconds: number | null;
  timeLimitSeconds: number | null;
  player: { power: number; attack: number; defense: number; hp: number; speed: number; interval: number } | null;
  playerHit: number | null;
  playerHits: number | null;
  playerKillSeconds: number | null;
  bossHit: number | null;
  bossHits: number | null;
  bossKillSeconds: number | null;
};

function bossNumber(value: unknown, label: string): number {
  const number = Number(value);
  if (value === undefined || value === null || value === "" || !Number.isFinite(number) || number < 0) {
    throw new AppError("INVALID_INPUT", `请先填好首领的${label}`);
  }
  return number;
}

function puppetIdsOf(value: unknown): string[] {
  if (!Array.isArray(value) || value.length === 0 || value.some((item) => typeof item !== "string" || !item.trim())) {
    throw new AppError("INVALID_INPUT", "请选择人偶");
  }
  const ids = value.map((item) => item.trim());
  if (new Set(ids).size !== ids.length) {
    throw new AppError("INVALID_INPUT", "人偶不能重复");
  }
  return ids;
}

function failed(view: Pick<PuppetView, "id" | "displayName" | "kindName">, error: string): TrialPuppetResult {
  return {
    puppetId: view.id,
    displayName: view.displayName,
    kindName: view.kindName,
    error,
    win: null,
    reason: null,
    durationSeconds: null,
    timeLimitSeconds: null,
    player: null,
    playerHit: null,
    playerHits: null,
    playerKillSeconds: null,
    bossHit: null,
    bossHits: null,
    bossKillSeconds: null,
  };
}

export async function runTrial(db: Db, input: TrialInput) {
  const puppetIds = puppetIdsOf(input.puppetIds);
  const boss = {
    attack: bossNumber(input.boss?.attack, "攻击"),
    defense: bossNumber(input.boss?.defense, "防御"),
    hp: bossNumber(input.boss?.hp, "气血"),
    interval: bossNumber(input.boss?.interval, "出手间隔"),
  };
  if (boss.hp <= 0 || boss.interval <= 0) {
    throw new AppError("INVALID_INPUT", "首领气血和出手间隔要大于 0");
  }
  const world = await loadDraftSnapshot(db);
  const config = battleConfigOf(world);
  const rows = await db.select().from(contentTrialPuppets);
  const results = puppetIds.map((id) => {
    const row = rows.find((candidate) => candidate.slug === id);
    if (!row) {
      return failed({ id, displayName: "", kindName: "" }, "没有这个人偶");
    }
    const view = presentPuppet(row, world);
    if (view.problem || view.attack == null || view.defense == null || view.hp == null || view.speed == null || view.interval == null || view.power == null) {
      return failed(view, view.problem ?? "这个人偶还不能打");
    }
    if (view.hp <= 0 || view.interval <= 0) {
      return failed(view, "这个人偶还不能打");
    }
    const player = {
      attack: view.attack,
      defense: view.defense,
      hp: view.hp,
      speed: view.speed,
      interval: view.interval,
      power: view.power,
    };
    const battle = simulateBattle(player, boss, config);
    const playerHit = hitDamage(player.attack, boss.defense, config.playerDefenseFactor, 1, config.playerDamageFloor);
    const bossHit = hitDamage(boss.attack, player.defense, config.bossDefenseFactor, 1, config.bossDamageFloor);
    const playerHits = Math.ceil(boss.hp / playerHit);
    const bossHits = bossHit > 0 ? Math.ceil(player.hp / bossHit) : null;
    return {
      puppetId: view.id,
      displayName: view.displayName,
      kindName: view.kindName,
      error: null,
      win: battle.win,
      reason: battle.reason,
      durationSeconds: battle.durationSeconds,
      timeLimitSeconds: config.timeLimitSeconds,
      player,
      playerHit,
      playerHits,
      playerKillSeconds: playerHits * player.interval,
      bossHit,
      bossHits,
      bossKillSeconds: bossHits == null ? null : bossHits * boss.interval,
    };
  });
  return { results };
}
