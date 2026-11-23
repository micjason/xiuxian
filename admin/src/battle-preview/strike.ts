/** 后台普通一击的对拍计算。只看表现时间，不算伤害。游戏战斗不读这里。 */

export const DEFAULT_FRAME_MS = 83;
export const MIN_FRAME_MS = 30;
export const MAX_FRAME_MS = 400;

export const ACTION_IDS = ["idle", "attack", "hit", "projectile", "impact"] as const;
export type ActionId = (typeof ACTION_IDS)[number];

export const ACTION_LABEL: Record<ActionId, string> = {
  idle: "待机",
  attack: "出招",
  hit: "受击",
  projectile: "飞出物",
  impact: "打中爆开",
};

export type PreviewFrame = {
  id: string;
  name: string;
  hidden: boolean;
  durationMs: number;
  action: ActionId | null;
};

export type PreviewClip = {
  id: string;
  name: string;
  frames: PreviewFrame[];
};

export type HitMode = "attackFrame" | "projectileArrive";
export type Side = "left" | "right";

export type BattlePreviewDocument = {
  schemaVersion: 1;
  characterClipId: string | null;
  opponentClipId: string | null;
  characterSide: Side;
  attackerSide: Side;
  demoNumber: string;
  attackLeadMs: number | null;
  projectileFrame: number;
  projectileShiftMs: number;
  hitMode: HitMode;
  hitFrame: number;
  hitShiftMs: number;
  impactOffsetMs: number;
  numberOffsetMs: number;
  defenderHitOffsetMs: number;
  clips: PreviewClip[];
};

export function emptyDocument(): BattlePreviewDocument {
  return {
    schemaVersion: 1,
    characterClipId: null,
    opponentClipId: null,
    characterSide: "left",
    attackerSide: "left",
    demoNumber: "123",
    attackLeadMs: null,
    projectileFrame: 1,
    projectileShiftMs: 0,
    hitMode: "attackFrame",
    hitFrame: 1,
    hitShiftMs: 0,
    impactOffsetMs: 0,
    numberOffsetMs: 0,
    defenderHitOffsetMs: 0,
    clips: [],
  };
}

export function clipById(doc: BattlePreviewDocument, id: string | null): PreviewClip | null {
  if (!id) return null;
  return doc.clips.find((clip) => clip.id === id) ?? null;
}

/** 隐藏帧不进播放，也不算进动作段。 */
export function visibleActionFrames(clip: PreviewClip | null, action: ActionId): PreviewFrame[] {
  if (!clip) return [];
  return clip.frames.filter((frame) => !frame.hidden && frame.action === action);
}

export function effectFrames(doc: BattlePreviewDocument, action: "projectile" | "impact"): PreviewFrame[] {
  const frames: PreviewFrame[] = [];
  for (const clip of doc.clips) {
    for (const frame of clip.frames) {
      if (!frame.hidden && frame.action === action) frames.push(frame);
    }
  }
  return frames;
}

export function sideClipId(doc: BattlePreviewDocument, side: Side): string | null {
  if (side === doc.characterSide) return doc.characterClipId;
  if (doc.opponentClipId && doc.opponentClipId === doc.characterClipId) return doc.characterClipId;
  return doc.opponentClipId;
}

function sumDuration(frames: PreviewFrame[]): number {
  return frames.reduce((total, frame) => total + frame.durationMs, 0);
}

function frameOffset(frames: PreviewFrame[], frameNumber: number): number {
  if (frames.length === 0) return 0;
  const index = Math.min(frames.length, Math.max(1, Math.floor(frameNumber))) - 1;
  return sumDuration(frames.slice(0, index));
}

export function frameIndexAtTime(frames: PreviewFrame[], timeMs: number, loop: boolean): number {
  if (frames.length === 0) return -1;
  const total = sumDuration(frames);
  if (total <= 0) return 0;
  let time = Math.max(0, timeMs);
  if (loop) time %= total;
  else if (time >= total) return frames.length - 1;
  let cursor = 0;
  for (let index = 0; index < frames.length; index += 1) {
    cursor += frames[index]?.durationMs ?? 0;
    if (time < cursor) return index;
  }
  return frames.length - 1;
}

export const STRIKE_EVENT_IDS = [
  "enterIdle",
  "attackStart",
  "projectile",
  "hit",
  "impact",
  "number",
  "defenderHit",
  "returnIdle",
] as const;

export type StrikeEventId = (typeof STRIKE_EVENT_IDS)[number];

export const STRIKE_EVENT_LABEL: Record<StrikeEventId, string> = {
  enterIdle: "双方进入待机",
  attackStart: "攻击方开始出招",
  projectile: "飞出物出现",
  hit: "命中",
  impact: "爆开",
  number: "伤害数字出现",
  defenderHit: "受击方受击",
  returnIdle: "双方回到待机",
};

export type StrikeEvent = {
  id: StrikeEventId;
  label: string;
  timeMs: number;
  skipped: boolean;
  note: string | null;
};

export type StrikePlan = {
  durationMs: number;
  attackStartMs: number;
  attackEndMs: number;
  defenderHitStartMs: number;
  defenderHitEndMs: number;
  projectileStartMs: number | null;
  projectileEndMs: number | null;
  impactStartMs: number | null;
  impactEndMs: number | null;
  numberStartMs: number | null;
  numberEndMs: number | null;
  numberText: string;
  events: StrikeEvent[];
  warnings: string[];
  attackerClipId: string | null;
  defenderClipId: string | null;
};

export function resolveStrike(doc: BattlePreviewDocument): StrikePlan {
  const defenderSide: Side = doc.attackerSide === "left" ? "right" : "left";
  const attackerClipId = sideClipId(doc, doc.attackerSide);
  const defenderClipId = sideClipId(doc, defenderSide);
  const attacker = clipById(doc, attackerClipId);
  const defender = clipById(doc, defenderClipId);
  const idle = visibleActionFrames(attacker, "idle");
  const attack = visibleActionFrames(attacker, "attack");
  const defenderIdle = visibleActionFrames(defender, "idle");
  const hits = visibleActionFrames(defender, "hit");
  const projectiles = effectFrames(doc, "projectile");
  const impacts = effectFrames(doc, "impact");
  const warnings: string[] = [];
  if (attack.length === 0) warnings.push("还少：出招");
  if (hits.length === 0) warnings.push("还少：受击");
  if (idle.length === 0) warnings.push("攻击方待机未指定");
  if (defenderIdle.length === 0) warnings.push("受击方待机未指定");

  const naturalLead = sumDuration(idle);
  const attackStartMs = doc.attackLeadMs == null ? naturalLead : Math.max(0, doc.attackLeadMs);
  const attackEndMs = attackStartMs + sumDuration(attack);

  const projectileMissing = projectiles.length === 0;
  let projectileStartMs: number | null = null;
  let projectileEndMs: number | null = null;
  if (!projectileMissing) {
    projectileStartMs = Math.max(0, attackStartMs + frameOffset(attack, doc.projectileFrame) + doc.projectileShiftMs);
    projectileEndMs = projectileStartMs + sumDuration(projectiles);
  } else {
    warnings.push("飞出物没有素材，这一段会跳过");
  }

  let hitBase = attackStartMs + frameOffset(attack, doc.hitFrame);
  let hitNote: string | null = null;
  if (doc.hitMode === "projectileArrive") {
    if (projectileEndMs != null) {
      hitBase = projectileEndMs;
    } else {
      hitNote = "没有飞出物，命中仍停在出招对齐上";
      warnings.push("没有飞出物，命中不能对齐到飞到对方。请改成对齐到出招某一帧。");
    }
  }
  const hitMs = Math.max(0, hitBase + doc.hitShiftMs);

  const impactMissing = impacts.length === 0;
  const impactStartMs = impactMissing ? null : Math.max(0, hitMs + doc.impactOffsetMs);
  const impactEndMs = impactStartMs == null ? null : impactStartMs + sumDuration(impacts);
  if (impactMissing) warnings.push("打中爆开没有素材，这一段会跳过");

  const holdFrame = attack[Math.min(attack.length, Math.max(1, Math.floor(doc.hitFrame))) - 1];
  const numberHold = holdFrame?.durationMs ?? DEFAULT_FRAME_MS;
  const numberStartMs = Math.max(0, hitMs + doc.numberOffsetMs);
  const numberEndMs = numberStartMs + numberHold;
  const defenderHitStartMs = Math.max(0, hitMs + doc.defenderHitOffsetMs);
  const defenderHitEndMs = defenderHitStartMs + sumDuration(hits);
  const tail = Math.max(sumDuration(idle), sumDuration(defenderIdle));
  const returnIdle = Math.max(attackEndMs, defenderHitEndMs, impactEndMs ?? 0, numberEndMs, projectileEndMs ?? 0);
  const durationMs = returnIdle + tail;

  const events: StrikeEvent[] = [
    { id: "enterIdle", label: STRIKE_EVENT_LABEL.enterIdle, timeMs: 0, skipped: false, note: null },
    {
      id: "attackStart",
      label: STRIKE_EVENT_LABEL.attackStart,
      timeMs: attackStartMs,
      skipped: attack.length === 0,
      note: attack.length === 0 ? "无素材，将跳过" : null,
    },
    {
      id: "projectile",
      label: STRIKE_EVENT_LABEL.projectile,
      timeMs: projectileStartMs ?? attackStartMs,
      skipped: projectileMissing,
      note: projectileMissing ? "无素材，将跳过" : null,
    },
    { id: "hit", label: STRIKE_EVENT_LABEL.hit, timeMs: hitMs, skipped: false, note: hitNote },
    {
      id: "impact",
      label: STRIKE_EVENT_LABEL.impact,
      timeMs: impactStartMs ?? hitMs,
      skipped: impactMissing,
      note: impactMissing ? "无素材，将跳过" : null,
    },
    {
      id: "number",
      label: STRIKE_EVENT_LABEL.number,
      timeMs: numberStartMs,
      skipped: false,
      note: "只看位置和出现时机，不是真实伤害",
    },
    {
      id: "defenderHit",
      label: STRIKE_EVENT_LABEL.defenderHit,
      timeMs: defenderHitStartMs,
      skipped: hits.length === 0,
      note: hits.length === 0 ? "无素材，将跳过" : null,
    },
    { id: "returnIdle", label: STRIKE_EVENT_LABEL.returnIdle, timeMs: returnIdle, skipped: false, note: null },
  ];

  return {
    durationMs,
    attackStartMs,
    attackEndMs,
    defenderHitStartMs,
    defenderHitEndMs,
    projectileStartMs,
    projectileEndMs,
    impactStartMs,
    impactEndMs,
    numberStartMs,
    numberEndMs,
    numberText: doc.demoNumber,
    events,
    warnings,
    attackerClipId,
    defenderClipId,
  };
}

export type StrikePose = {
  attackerFrameId: string | null;
  defenderFrameId: string | null;
  projectileFrameId: string | null;
  impactFrameId: string | null;
  showNumber: boolean;
  attackerAction: ActionId | "missing";
  defenderAction: ActionId | "missing";
};

export function poseAt(doc: BattlePreviewDocument, plan: StrikePlan, timeMs: number): StrikePose {
  const time = Math.max(0, timeMs);
  const attacker = clipById(doc, plan.attackerClipId);
  const defender = clipById(doc, plan.defenderClipId);
  const idle = visibleActionFrames(attacker, "idle");
  const attack = visibleActionFrames(attacker, "attack");
  const defenderIdle = visibleActionFrames(defender, "idle");
  const hits = visibleActionFrames(defender, "hit");
  const projectiles = effectFrames(doc, "projectile");
  const impacts = effectFrames(doc, "impact");

  let attackerFrameId: string | null;
  let attackerAction: ActionId | "missing";
  if (time < plan.attackStartMs || attack.length === 0) {
    const index = frameIndexAtTime(idle, time < plan.attackStartMs ? time : time - plan.attackEndMs, true);
    attackerFrameId = index >= 0 ? (idle[index]?.id ?? null) : null;
    attackerAction = attackerFrameId ? "idle" : "missing";
  } else if (time < plan.attackEndMs) {
    const index = frameIndexAtTime(attack, time - plan.attackStartMs, false);
    attackerFrameId = index >= 0 ? (attack[index]?.id ?? null) : null;
    attackerAction = "attack";
  } else {
    const index = frameIndexAtTime(idle, time - plan.attackEndMs, true);
    attackerFrameId = index >= 0 ? (idle[index]?.id ?? null) : null;
    attackerAction = attackerFrameId ? "idle" : "missing";
  }

  let defenderFrameId: string | null;
  let defenderAction: ActionId | "missing";
  if (plan.defenderHitEndMs > plan.defenderHitStartMs && time >= plan.defenderHitStartMs && time < plan.defenderHitEndMs) {
    const index = frameIndexAtTime(hits, time - plan.defenderHitStartMs, false);
    defenderFrameId = index >= 0 ? (hits[index]?.id ?? null) : null;
    defenderAction = "hit";
  } else {
    const origin = time < plan.defenderHitStartMs ? time : time - plan.defenderHitEndMs;
    const index = frameIndexAtTime(defenderIdle, origin, true);
    defenderFrameId = index >= 0 ? (defenderIdle[index]?.id ?? null) : null;
    defenderAction = defenderFrameId ? "idle" : "missing";
  }

  let projectileFrameId: string | null = null;
  if (plan.projectileStartMs != null && plan.projectileEndMs != null && time >= plan.projectileStartMs && time < plan.projectileEndMs) {
    const index = frameIndexAtTime(projectiles, time - plan.projectileStartMs, false);
    projectileFrameId = index >= 0 ? (projectiles[index]?.id ?? null) : null;
  }
  let impactFrameId: string | null = null;
  if (plan.impactStartMs != null && plan.impactEndMs != null && time >= plan.impactStartMs && time < plan.impactEndMs) {
    const index = frameIndexAtTime(impacts, time - plan.impactStartMs, false);
    impactFrameId = index >= 0 ? (impacts[index]?.id ?? null) : null;
  }
  const showNumber =
    plan.numberStartMs != null && plan.numberEndMs != null && time >= plan.numberStartMs && time < plan.numberEndMs;

  return { attackerFrameId, defenderFrameId, projectileFrameId, impactFrameId, showNumber, attackerAction, defenderAction };
}

export function alignLabel(doc: BattlePreviewDocument, eventId: StrikeEventId): string {
  if (eventId === "attackStart") {
    return doc.attackLeadMs == null ? "从待机播完后开始，可拖色块起点改早晚" : `出招开始改到第 ${doc.attackLeadMs} 毫秒`;
  }
  if (eventId === "projectile") return `${frameSentence(doc.projectileFrame)}${shiftSentence(doc.projectileShiftMs)}`;
  if (eventId === "hit") {
    const base = doc.hitMode === "projectileArrive" ? "对齐到飞出物到达对方" : frameSentence(doc.hitFrame);
    return `${base}${shiftSentence(doc.hitShiftMs)}`;
  }
  if (eventId === "impact") return offsetSentence("爆开", doc.impactOffsetMs);
  if (eventId === "number") return offsetSentence("伤害数字", doc.numberOffsetMs);
  if (eventId === "defenderHit") return offsetSentence("受击", doc.defenderHitOffsetMs);
  if (eventId === "enterIdle") return "双方先待机";
  return "各自动作播完后接回待机，不用填结束时间";
}

function frameSentence(frame: number): string {
  return `对齐到出招第 ${frame} 帧`;
}

function shiftSentence(shift: number): string {
  if (shift === 0) return "";
  return shift > 0 ? `，再晚 ${shift} 毫秒` : `，再早 ${-shift} 毫秒`;
}

function offsetSentence(name: string, offset: number): string {
  if (offset === 0) return `${name}与命中同一拍`;
  return offset > 0 ? `${name}比命中晚 ${offset} 毫秒` : `${name}比命中早 ${-offset} 毫秒`;
}

export function moveEvent(doc: BattlePreviewDocument, eventId: StrikeEventId, timeMs: number): BattlePreviewDocument {
  const next: BattlePreviewDocument = {
    ...doc,
    clips: doc.clips,
  };
  const desired = Math.max(0, Math.round(timeMs));
  const plan = resolveStrike(doc);
  const attacker = clipById(doc, plan.attackerClipId);
  const attack = visibleActionFrames(attacker, "attack");
  if (eventId === "attackStart") {
    next.attackLeadMs = desired;
    return next;
  }
  if (eventId === "projectile") {
    const base = plan.attackStartMs + frameOffset(attack, doc.projectileFrame);
    next.projectileShiftMs = desired - base;
    return next;
  }
  if (eventId === "hit") {
    let base = plan.attackStartMs + frameOffset(attack, doc.hitFrame);
    if (doc.hitMode === "projectileArrive" && plan.projectileEndMs != null) {
      base = plan.projectileEndMs;
    }
    next.hitShiftMs = desired - base;
    return next;
  }
  const hitMs = plan.events.find((event) => event.id === "hit")?.timeMs ?? 0;
  if (eventId === "impact") next.impactOffsetMs = desired - hitMs;
  if (eventId === "number") next.numberOffsetMs = desired - hitMs;
  if (eventId === "defenderHit") next.defenderHitOffsetMs = desired - hitMs;
  return next;
}

export type BandBlock = {
  label: string;
  startMs: number;
  endMs: number;
  tone: "idle" | "attack" | "hit";
};

export function bands(plan: StrikePlan): { attacker: BandBlock[]; defender: BandBlock[] } {
  const end = plan.durationMs;
  const attacker: BandBlock[] = [];
  if (plan.attackStartMs > 0) attacker.push({ label: "待机", startMs: 0, endMs: plan.attackStartMs, tone: "idle" });
  if (plan.attackEndMs > plan.attackStartMs) {
    attacker.push({ label: "出招", startMs: plan.attackStartMs, endMs: plan.attackEndMs, tone: "attack" });
  }
  if (end > plan.attackEndMs) attacker.push({ label: "待机", startMs: plan.attackEndMs, endMs: end, tone: "idle" });

  const defender: BandBlock[] = [];
  if (plan.defenderHitStartMs > 0) defender.push({ label: "待机", startMs: 0, endMs: plan.defenderHitStartMs, tone: "idle" });
  if (plan.defenderHitEndMs > plan.defenderHitStartMs) {
    defender.push({ label: "受击", startMs: plan.defenderHitStartMs, endMs: plan.defenderHitEndMs, tone: "hit" });
  }
  if (end > plan.defenderHitEndMs) defender.push({ label: "待机", startMs: plan.defenderHitEndMs, endMs: end, tone: "idle" });
  return { attacker, defender };
}

/** 飞出物从攻击方飞到受击方的进度。没有飞出物时是 null。 */
export function projectileProgress(plan: StrikePlan, timeMs: number): number | null {
  if (plan.projectileStartMs == null || plan.projectileEndMs == null) return null;
  if (timeMs < plan.projectileStartMs || timeMs >= plan.projectileEndMs) return null;
  const span = plan.projectileEndMs - plan.projectileStartMs;
  if (span <= 0) return 1;
  return (timeMs - plan.projectileStartMs) / span;
}
