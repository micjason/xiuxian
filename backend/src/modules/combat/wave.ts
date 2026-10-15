import { simulateBattle, type BattleSide } from "./battle.js";

export type WaveMonster = BattleSide;

export type WaveConfig = {
  waveSize: number;
  transitionSeconds: number;
  reviveSeconds: number;
  defenseConstant: number;
};

export type WaveEvent = { t: number; kind: "kill" | "death" };

export type WaveCycle = {
  /** 一个完整波次的秒数：每只的战斗（阵亡的还要加复活秒数）加转场。 */
  cycleSeconds: number;
  /** 一波里按时间排好的击杀/阵亡，t 是相对波次开始的秒数。 */
  events: WaveEvent[];
  kills: number;
  deaths: number;
  /** 一波里主角剩血最低的百分比（只统计打赢的那几只，和模拟脚本一致）。 */
  minHpPct: number;
};

/**
 * 一波普通怪的确定性推演（设计表 2.2 / 2.5）：N 只依次上前，一次只和一只交战，每只从上前时开始计时，
 * 中间不回血；打输就阵亡，过 reviveSeconds 后原地复活回满血，这只算没打死；一波之后有转场，转场时回满血。
 * 普通波次大招只做表演，不参与结算，所以这里只有普攻。纯函数，没有随机。
 */
export function waveCycle(player: BattleSide, monster: WaveMonster, config: WaveConfig): WaveCycle {
  let hp = player.hp;
  let total = 0;
  let kills = 0;
  let deaths = 0;
  let minHpPct = 100;
  const events: WaveEvent[] = [];
  for (let index = 0; index < config.waveSize; index += 1) {
    const fight = simulateBattle({ ...player, hp }, monster, { timeLimitSeconds: 600, defenseConstant: config.defenseConstant });
    total += fight.durationSeconds;
    if (!fight.win) {
      deaths += 1;
      events.push({ t: total, kind: "death" });
      total += config.reviveSeconds;
      hp = player.hp;
      continue;
    }
    kills += 1;
    events.push({ t: total, kind: "kill" });
    const lastBossHit = [...fight.log].reverse().find((event) => event.side === "boss");
    hp = lastBossHit ? lastBossHit.targetHpAfter : hp;
    minHpPct = Math.min(minHpPct, player.hp > 0 ? (hp / player.hp) * 100 : 0);
  }
  return { cycleSeconds: total + config.transitionSeconds, events, kills, deaths, minHpPct };
}

export type WaveAdvance = {
  kills: number;
  deaths: number;
  /** 推进后当前波次已进行的秒数，写回 player_states.wave_progress。 */
  progress: number;
  /** 推进后连续阵亡次数。 */
  deathsInRow: number;
};

const EPSILON = 1e-9;

/**
 * 在线 elapsedSeconds 秒内波次推进了多少：从“当前波次已进行 progress 秒”走到 progress + elapsed 秒，
 * 数这段时间里落下的击杀/阵亡（完整波次整数倍 + 当前波次里新越过的事件）。
 * 不足一只的时间保留在 progress 里，下次接着算，所以 3 秒一次的轮询和一次性算出来的击杀数完全相同，不会丢。
 */
export function advanceWaves(progress: number, elapsedSeconds: number, cycle: WaveCycle, deathsInRow = 0): WaveAdvance {
  if (!(cycle.cycleSeconds > 0) || elapsedSeconds <= 0) {
    return { kills: 0, deaths: 0, progress, deathsInRow };
  }
  const start = Math.min(Math.max(0, progress), cycle.cycleSeconds - EPSILON);
  const total = start + elapsedSeconds;
  const fullCycles = Math.floor((total + EPSILON) / cycle.cycleSeconds);
  const rest = Math.max(0, total - fullCycles * cycle.cycleSeconds);
  let row = deathsInRow;
  const apply = (events: WaveEvent[]) => {
    for (const event of events) {
      row = event.kind === "kill" ? 0 : row + 1;
    }
  };
  const count = (events: WaveEvent[]) => ({
    kills: events.filter((event) => event.kind === "kill").length,
    deaths: events.filter((event) => event.kind === "death").length,
  });
  const upTo = (seconds: number) => cycle.events.filter((event) => event.t <= seconds + EPSILON);
  let kills = 0;
  let deaths = 0;
  if (fullCycles === 0) {
    const fresh = cycle.events.filter((event) => event.t > start + EPSILON && event.t <= rest + EPSILON);
    ({ kills, deaths } = count(fresh));
    apply(fresh);
  } else {
    const tail = cycle.events.filter((event) => event.t > start + EPSILON);
    const head = upTo(rest);
    const tailCount = count(tail);
    const headCount = count(head);
    kills = tailCount.kills + headCount.kills + (fullCycles - 1) * cycle.kills;
    deaths = tailCount.deaths + headCount.deaths + (fullCycles - 1) * cycle.deaths;
    apply(tail);
    if (fullCycles > 1) {
      if (cycle.kills > 0) {
        row = 0;
        apply(cycle.events.slice(cycle.events.map((event) => event.kind).lastIndexOf("kill") + 1));
      } else {
        row += (fullCycles - 1) * cycle.deaths;
      }
    }
    apply(head);
  }
  return { kills, deaths, progress: rest, deathsInRow: row };
}
