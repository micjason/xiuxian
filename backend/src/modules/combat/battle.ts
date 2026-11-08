export type BattleSide = { attack: number; defense: number; hp: number; interval: number; critChanceBp?: number; dodgeChanceBp?: number; critMultBp?: number };

export type SkillEffect = { kind: "attack_up" | "defense_down" | "heal" | "shield"; valueBp: number; durationSeconds?: number };
export type BattleStatus = SkillEffect & { side: "player" | "boss"; expiresAt: number; source: string; remaining?: number };

/** 正在运转、会在战报里出手的技能。名字已经换成玩家能看的叫法。 */
export type CombatSkill = {
  slug: string;
  name: string;
  castMode: "auto" | "passive";
  /** 每 N 次普攻施放；默认 4。 */
  castEveryAttacks: number;
  /** 相对普攻伤害的万分比；默认 10000 = 1.0×。 */
  damageMultBp: number;
  effects?: SkillEffect[];
  fxType?: string;
  fx?: { type: string; primary?: string; secondary?: string; scale?: number };
};

export type BattleEvent = {
  t: number;
  side: "player" | "boss";
  damage: number;
  targetHpAfter: number;
  /** 自动技能出手。协议字段沿用 ult，界面文案不读这个词。 */
  kind?: "attack" | "skill" | "ult";
  critical?: boolean;
  dodged?: boolean;
  absorbed?: number;
  healed?: number;
  playerHpAfter?: number;
  bossHpAfter?: number;
  rageAfter?: number;
  statuses?: BattleStatus[];
  skillSlug?: string;
  name?: string;
  fxType?: string;
  fx?: CombatSkill["fx"];
  castMode?: CombatSkill["castMode"];
};

/** 默认每 4 次普攻追加一次自动技能（第 1、5、9… 次）。由技能表 castEveryAttacks 覆盖。 */
export const DEFAULT_SKILL_CAST_EVERY_ATTACKS = 4;
/** 默认自动技能伤害 = 当次普攻 × 1.0（万分比 10000）。由技能表 damageMultBp 覆盖。 */
export const DEFAULT_SKILL_DAMAGE_MULT_BP = 10000;

const HIDDEN_SKILL_NAMES = new Set(["大招", "暴击"]);

/** 战报上的技能名。空名，或配置仍写成不能给玩家看的旧称呼时，写成「自动技能」。 */
export function publicSkillName(raw: string | null | undefined): string {
  const name = (raw ?? "").trim();
  if (!name || HIDDEN_SKILL_NAMES.has(name)) {
    return "自动技能";
  }
  return name;
}

export function normalizeCastEveryAttacks(value: unknown): number {
  const n = Math.floor(Number(value));
  if (!Number.isFinite(n) || n < 1) {
    return DEFAULT_SKILL_CAST_EVERY_ATTACKS;
  }
  return Math.min(n, 99);
}

export function normalizeDamageMultBp(value: unknown): number {
  const n = Math.floor(Number(value));
  if (!Number.isFinite(n) || n < 0) {
    return DEFAULT_SKILL_DAMAGE_MULT_BP;
  }
  return Math.min(n, 1_000_000);
}

export function skillCastsOnAttack(attackIndex: number, everyAttacks: number = DEFAULT_SKILL_CAST_EVERY_ATTACKS): boolean {
  const every = normalizeCastEveryAttacks(everyAttacks);
  return attackIndex > 0 && (attackIndex - 1) % every === 0;
}

export function skillCastDamage(basicAttackDamage: number, damageMultBp: number = DEFAULT_SKILL_DAMAGE_MULT_BP): number {
  return basicAttackDamage * (normalizeDamageMultBp(damageMultBp) / 10000);
}

type LearnedSkill = { skillSlug: string; runningSlot: string | null };
type SkillDefinition = {
  slug: string;
  displayName?: string | null;
  enabled?: boolean;
  castMode?: string | null;
  castEveryAttacks?: number | null;
  damageMultBp?: number | null;
  effects?: SkillEffect[];
  fxType?: string | null;
  fx?: { type?: string; primary?: string; secondary?: string; scale?: number } | null;
};

function slotIndex(slot: string | null): number {
  return Number(slot?.match(/^run_(\d+)$/)?.[1] ?? Number.MAX_SAFE_INTEGER);
}

/**
 * 战报施放只用「正在运转、栏位还开着、没停用」的自动 / 被动技能。
 * 栏位顺序与属性计算相同：run_1、run_2…，其它栏位名排在后面。
 */
export function toCombatSkills(learned: LearnedSkill[], definitions: SkillDefinition[], openSlots: number): CombatSkill[] {
  const bySlug = new Map(definitions.map((row) => [row.slug, row]));
  return learned
    .filter((skill) => skill.runningSlot && slotIndex(skill.runningSlot) >= 1 && slotIndex(skill.runningSlot) <= Math.max(0, openSlots))
    .sort((left, right) => slotIndex(left.runningSlot) - slotIndex(right.runningSlot) || left.skillSlug.localeCompare(right.skillSlug))
    .slice(0, Math.max(0, openSlots))
    .flatMap((skill) => {
      const definition = bySlug.get(skill.skillSlug);
      if (!definition || definition.enabled === false) {
        return [];
      }
      const castMode = definition.castMode === "passive" ? "passive" : definition.castMode === "auto" || definition.castMode == null || definition.castMode === "" ? "auto" : null;
      if (!castMode) {
        return [];
      }
      const combat: CombatSkill = {
        slug: definition.slug,
        name: publicSkillName(definition.displayName),
        castMode,
        castEveryAttacks: normalizeCastEveryAttacks(definition.castEveryAttacks),
        damageMultBp: normalizeDamageMultBp(definition.damageMultBp),
      };
      if (definition.effects) combat.effects = definition.effects;
      if (definition.fxType) {
        combat.fxType = definition.fxType;
      }
      const fx = definition.fx;
      if (fx && typeof fx.type === "string" && fx.type) {
        combat.fx = {
          type: fx.type,
          ...(fx.primary ? { primary: fx.primary } : {}),
          ...(fx.secondary ? { secondary: fx.secondary } : {}),
          ...(fx.scale != null ? { scale: fx.scale } : {}),
        };
      }
      return [combat];
    });
}

export type BattleResult = {
  win: boolean;
  reason: "win" | "defeated" | "timeout" | "retreat";
  durationSeconds: number;
  log: BattleEvent[];
};

export type BattleConfig = {
  timeLimitSeconds: number;
  defenseConstant: number;
  /** Only live battles enable rage. Offline wave simulations retain existing balancing. */
  rage?: { max: number; onAttack: number; onHit: number; damageMultBp: number };
  /** Injected server PRNG for replayable unit tests. Never supplied by clients. */
  random?: () => number;
};

function trimLog(log: BattleEvent[]): BattleEvent[] {
  // Playback requires every HP transition, not just the first/last 100 rows.
  return log;
}

export function hitDamage(attack: number, defense: number, defenseConstant: number): number {
  if (attack <= 0) {
    return 0;
  }
  return (attack * attack) / (attack + defenseConstant * Math.max(defense, 0));
}

function skillCastEvent(t: number, damage: number, targetHpAfter: number, skill: CombatSkill): BattleEvent {
  const event: BattleEvent = {
    t,
    side: "player",
    damage,
    targetHpAfter,
    kind: "ult",
    skillSlug: skill.slug,
    name: publicSkillName(skill.name),
    castMode: skill.castMode,
  };
  if (skill.fxType) {
    event.fxType = skill.fxType;
  }
  if (skill.fx) {
    event.fx = skill.fx;
  }
  return event;
}

export function simulateBattle(player: BattleSide, boss: BattleSide, config: BattleConfig, skills: CombatSkill[] = []): BattleResult {
  for (const side of [player, boss]) {
    if (![side.attack, side.defense, side.hp, side.interval].every(Number.isFinite) || side.interval <= 0 || side.hp <= 0) {
      throw new Error("Invalid battle side");
    }
  }
  if (!Number.isFinite(config.timeLimitSeconds) || config.timeLimitSeconds < 0) throw new Error("Invalid battle time limit");
  const roll = config.random ?? Math.random;
  const bp = (value = 0) => Math.min(10000, Math.max(0, value));
  let playerHp = player.hp;
  let bossHp = boss.hp;
  let playerNext = player.interval;
  let bossNext = boss.interval;
  let playerAttacks = 0;
  let castCursor = 0;
  let rage = 0;
  let statuses: BattleStatus[] = [];
  const log: BattleEvent[] = [];
  const done = (win: boolean, reason: BattleResult["reason"], durationSeconds: number) => ({ win, reason, durationSeconds, log });
  const snapshot = (event: BattleEvent) => {
    event.playerHpAfter = playerHp;
    event.bossHpAfter = bossHp;
    event.rageAfter = rage;
    event.statuses = statuses.map(s => ({ ...s }));
    log.push(event);
  };
  const strike = (t: number, side: "player" | "boss", kind: "attack" | "skill" | "ult", multiplier = 10000, skill?: CombatSkill) => {
    const attacker = side === "player" ? player : boss;
    const target = side === "player" ? boss : player;
    const targetSide = side === "player" ? "boss" : "player";
    const attackUp = statuses.filter(s => s.side === side && s.kind === "attack_up").reduce((n, s) => n + s.valueBp, 0);
    const defenseDown = statuses.filter(s => s.side === targetSide && s.kind === "defense_down").reduce((n, s) => n + s.valueBp, 0);
    const dodged = bp(target.dodgeChanceBp) > 0 && roll() * 10000 < bp(target.dodgeChanceBp);
    const critical = !dodged && bp(attacker.critChanceBp) > 0 && roll() * 10000 < bp(attacker.critChanceBp);
    let damage = dodged ? 0 : skillCastDamage(hitDamage(attacker.attack * (1 + attackUp / 10000), target.defense * (1 - bp(defenseDown) / 10000), config.defenseConstant), multiplier) * (critical ? Math.max(10000, attacker.critMultBp ?? 15000) / 10000 : 1);
    let absorbed = 0;
    for (const shield of statuses.filter(s => s.side === targetSide && s.kind === "shield")) {
      const amount = Math.min(shield.remaining ?? 0, damage);
      shield.remaining = (shield.remaining ?? 0) - amount;
      damage -= amount;
      absorbed += amount;
    }
    statuses = statuses.filter(s => s.kind !== "shield" || (s.remaining ?? 0) > 0);
    if (side === "player") bossHp = Math.max(0, bossHp - damage);
    else playerHp = Math.max(0, playerHp - damage);
    let healed = 0;
    // A defensive/healing technique still activates when its damage is dodged.
    for (const effect of skill?.effects ?? []) {
      const valueBp = Math.max(0, effect.valueBp);
      if (effect.kind === "heal") {
        healed = Math.min(player.hp - playerHp, player.hp * valueBp / 10000);
        playerHp += healed;
      } else {
        const state: BattleStatus = { ...effect, valueBp, source: skill!.slug, side: effect.kind === "defense_down" ? "boss" : "player", expiresAt: t + Math.max(0.01, effect.durationSeconds ?? 3) };
        if (effect.kind === "shield") state.remaining = player.hp * valueBp / 10000;
        statuses = statuses.filter(s => !(s.kind === state.kind && s.source === state.source));
        statuses.push(state);
      }
    }
    if (config.rage && kind === "attack") {
      rage = Math.min(config.rage.max, rage + (side === "player" ? config.rage.onAttack : !dodged ? config.rage.onHit : 0));
    }
    snapshot({ ...(skill ? skillCastEvent(t, damage, bossHp, skill) : {}), ...(kind === "ult" ? { name: "怒气强击" } : {}), t, side, kind, damage, targetHpAfter: side === "player" ? bossHp : playerHp, critical, dodged, absorbed, healed });
  };
  while (playerHp > 0 && bossHp > 0) {
    const next = Math.min(playerNext, bossNext);
    if (next > config.timeLimitSeconds) return done(false, "timeout", config.timeLimitSeconds);
    statuses = statuses.filter(s => s.expiresAt > next);
    if (playerNext === next) {
      playerAttacks += 1;
      strike(next, "player", "attack");
      playerNext += player.interval;
      if (bossHp <= 0) return done(true, "win", next);
      const skill = skills[castCursor];
      if (skill && skillCastsOnAttack(playerAttacks, skill.castEveryAttacks)) {
        castCursor = (castCursor + 1) % skills.length;
        strike(next, "player", "skill", skill.damageMultBp, skill);
        if (bossHp <= 0) return done(true, "win", next);
      }
    }
    if (bossNext === next && bossHp > 0) {
      strike(next, "boss", "attack");
      bossNext += boss.interval;
      if (playerHp <= 0) return done(false, "defeated", next);
    }
    if (config.rage && config.rage.max > 0 && rage >= config.rage.max && playerHp > 0 && bossHp > 0) {
      rage = 0;
      strike(next, "player", "ult", config.rage.damageMultBp);
      if (bossHp <= 0) return done(true, "win", next);
    }
  }
  return done(bossHp <= 0, bossHp <= 0 ? "win" : "defeated", 0);
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

export type UltCast = { t: number; readyAt: number; manual: boolean; damage: number; skillSlug?: string; name?: string };

function skillCastRecords(log: BattleEvent[]): UltCast[] {
  return log.flatMap((event) => {
    if (event.kind !== "ult" || !event.skillSlug) {
      return [];
    }
    return [{ t: event.t, readyAt: event.t, manual: false, damage: event.damage, skillSlug: event.skillSlug, name: event.name }];
  });
}

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

export function simulateBossFight(player: BattleSide, boss: BattleSide, config: BattleConfig, ult: UltConfig | null, plan: UltPlan = [], skills: CombatSkill[] = []): BossFightResult {
  const taps = Array.isArray(plan) ? plan : [];
  const waits = Array.isArray(plan) ? null : plan.waits;
  if (!ult || ult.multBp <= 0) {
    const battle = simulateBattle(player, boss, config, skills);
    const log = battle.log.map(event => event.kind === "skill" ? { ...event, kind: "ult" as const } : event);
    return { ...battle, log, ultCasts: skillCastRecords(log) };
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
