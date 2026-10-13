export type BattleSide = { attack: number; defense: number; hp: number; interval: number };

export type BattleEvent = { t: number; side: "player" | "boss"; damage: number; targetHpAfter: number };

export type BattleResult = {
  win: boolean;
  reason: "win" | "defeated" | "timeout";
  durationSeconds: number;
  log: BattleEvent[];
};

export type BattleConfig = {
  timeLimitSeconds: number;
  defenseConstant: number;
};

function trimLog(log: BattleEvent[]): BattleEvent[] {
  if (log.length <= 200) {
    return log;
  }
  return [...log.slice(0, 100), ...log.slice(-100)];
}

export function hitDamage(attack: number, defense: number, defenseConstant: number): number {
  if (attack <= 0) {
    return 0;
  }
  return (attack * attack) / (attack + defenseConstant * Math.max(defense, 0));
}

export function simulateBattle(player: BattleSide, boss: BattleSide, config: BattleConfig): BattleResult {
  const playerDamage = hitDamage(player.attack, boss.defense, config.defenseConstant);
  const bossDamage = hitDamage(boss.attack, player.defense, config.defenseConstant);
  let playerHp = player.hp;
  let bossHp = boss.hp;
  let playerNext = player.interval;
  let bossNext = boss.interval;
  const log: BattleEvent[] = [];
  while (playerHp > 0 && bossHp > 0) {
    const next = Math.min(playerNext, bossNext);
    if (next > config.timeLimitSeconds) {
      return { win: false, reason: "timeout", durationSeconds: config.timeLimitSeconds, log: trimLog(log) };
    }
    if (playerNext === next) {
      bossHp = Math.max(0, bossHp - playerDamage);
      log.push({ t: next, side: "player", damage: playerDamage, targetHpAfter: bossHp });
      playerNext += player.interval;
      if (bossHp <= 0) {
        return { win: true, reason: "win", durationSeconds: next, log: trimLog(log) };
      }
    }
    if (bossNext === next && bossHp > 0) {
      playerHp = Math.max(0, playerHp - bossDamage);
      log.push({ t: next, side: "boss", damage: bossDamage, targetHpAfter: playerHp });
      bossNext += boss.interval;
      if (playerHp <= 0) {
        return { win: false, reason: "defeated", durationSeconds: next, log: trimLog(log) };
      }
    }
  }
  return { win: bossHp <= 0, reason: bossHp <= 0 ? "win" : "defeated", durationSeconds: 0, log: trimLog(log) };
}
