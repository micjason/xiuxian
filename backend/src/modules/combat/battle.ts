export type BattleSide = { attack: number; defense: number; hp: number; interval: number };

export type BattleEvent = { t: number; side: "player" | "boss"; damage: number; targetHpAfter: number; /** 大招那一下（额外一次伤害，不替代普攻）。 */ kind?: "ult" };

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

export type UltConfig = {
  /** 大招伤害 = floor(普攻伤害 × multBp / 10000)，万分比（4 倍 = 40000）。 */
  multBp: number;
  cooldownSeconds: number;
  /** 开战后第一次冷却好的时间。 */
  firstCooldownSeconds: number;
  /** 冷却好后等玩家点击的秒数，超时自动释放。 */
  autoCastWindowSeconds: number;
};

export type UltCast = { t: number; readyAt: number; manual: boolean; damage: number };

export type BossFightResult = BattleResult & { ultCasts: UltCast[] };

/** 点击时间只接受有限的非负数，排好序，最多 50 个（防止乱发）。 */
export function cleanUltTaps(taps: unknown): number[] {
  if (!Array.isArray(taps)) {
    return [];
  }
  return taps
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value) && value >= 0)
    .slice(0, 50)
    .sort((left, right) => left - right);
}

/**
 * 首领战（带手动大招）。服务端用客户端上报的点击时间重新模拟，客户端画面只是预演：
 * - 大招第一次在 firstCooldownSeconds 冷却好，之后冷却从“释放时”算起；
 * - 冷却好之后的 autoCastWindowSeconds 内，第一个点击时间落在窗口里就在那一刻释放（手动）；没有就在窗口结束时自动释放；
 * - 冷却好之前的点击无效；点得再早也只能等到冷却好，所以不可能比“刚好冷却好就点”更快；
 * - 大招 = 额外一次伤害（不替代普攻）；同一时刻先结算玩家普攻、再大招、最后首领出手。
 * 也可以只报每次释放等待的秒数（{ waits }，0 到自动释放窗口）。
 * 不带大招（ult 为空或倍率 0）时和 simulateBattle 逐项一致。
 */
export type UltPlan = number[] | { waits: number[] };

export function simulateBossFight(player: BattleSide, boss: BattleSide, config: BattleConfig, ult: UltConfig | null, plan: UltPlan = []): BossFightResult {
  const taps = Array.isArray(plan) ? plan : [];
  const waits = Array.isArray(plan) ? null : plan.waits;
  if (!ult || ult.multBp <= 0) {
    return { ...simulateBattle(player, boss, config), ultCasts: [] };
  }
  const playerDamage = hitDamage(player.attack, boss.defense, config.defenseConstant);
  const bossDamage = hitDamage(boss.attack, player.defense, config.defenseConstant);
  const ultDamage = Math.floor((playerDamage * ult.multBp) / 10000);
  let playerHp = player.hp;
  let bossHp = boss.hp;
  let playerNext = player.interval;
  let bossNext = boss.interval;
  const log: BattleEvent[] = [];
  const ultCasts: UltCast[] = [];
  let tapIndex = 0;
  let ultReady = ult.firstCooldownSeconds;
  let ultNext = Number.POSITIVE_INFINITY;
  let ultManual = false;
  const schedule = () => {
    if (waits) {
      // 按“每次释放等待了几秒”重算（0..窗口）；没报的次数按自动释放。
      const wanted = Number(waits[ultCasts.length]);
      const wait = Number.isFinite(wanted) ? Math.min(Math.max(wanted, 0), ult.autoCastWindowSeconds) : ult.autoCastWindowSeconds;
      ultNext = ultReady + wait;
      ultManual = wait < ult.autoCastWindowSeconds;
      return;
    }
    while (tapIndex < taps.length && (taps[tapIndex] as number) < ultReady) {
      tapIndex += 1;
    }
    if (tapIndex < taps.length && (taps[tapIndex] as number) <= ultReady + ult.autoCastWindowSeconds) {
      ultNext = taps[tapIndex] as number;
      ultManual = true;
      tapIndex += 1;
    } else {
      ultNext = ultReady + ult.autoCastWindowSeconds;
      ultManual = false;
    }
  };
  schedule();
  const done = (win: boolean, reason: BattleResult["reason"], seconds: number): BossFightResult => ({ win, reason, durationSeconds: seconds, log: trimLog(log), ultCasts });
  for (;;) {
    const next = Math.min(playerNext, bossNext, ultNext);
    if (next > config.timeLimitSeconds) {
      return done(false, "timeout", config.timeLimitSeconds);
    }
    if (playerNext === next) {
      bossHp = Math.max(0, bossHp - playerDamage);
      log.push({ t: next, side: "player", damage: playerDamage, targetHpAfter: bossHp });
      playerNext += player.interval;
      if (bossHp <= 0) {
        return done(true, "win", next);
      }
    }
    if (ultNext === next) {
      bossHp = Math.max(0, bossHp - ultDamage);
      log.push({ t: next, side: "player", damage: ultDamage, targetHpAfter: bossHp, kind: "ult" });
      ultCasts.push({ t: next, readyAt: ultReady, manual: ultManual, damage: ultDamage });
      ultReady = next + ult.cooldownSeconds;
      schedule();
      if (bossHp <= 0) {
        return done(true, "win", next);
      }
    }
    if (bossNext === next && bossHp > 0) {
      playerHp = Math.max(0, playerHp - bossDamage);
      log.push({ t: next, side: "boss", damage: bossDamage, targetHpAfter: playerHp });
      bossNext += boss.interval;
      if (playerHp <= 0) {
        return done(false, "defeated", next);
      }
    }
  }
}
