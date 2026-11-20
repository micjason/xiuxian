export const SLOT_NAMES = [
  "idle",
  "walk",
  "jump",
  "attack",
  "cast",
  "skill",
  "hit",
  "down",
  "victory",
  "projectile",
  "impact",
] as const;

export const REQUIRED_SLOTS = ["idle", "attack", "cast", "skill", "hit", "down", "victory"] as const;

export const SLOT_LABEL: Record<SlotName, string> = {
  idle: "待机",
  walk: "行走",
  jump: "跳跃",
  attack: "普攻",
  cast: "施法",
  skill: "技能",
  hit: "受击",
  down: "倒地",
  victory: "胜利",
  projectile: "剑气",
  impact: "命中",
};

export type SlotName = (typeof SLOT_NAMES)[number];

export type SlotClip = {
  loop: boolean;
  holdLast: boolean;
  frameDurationMs: number;
  lungePx: number;
  frames: string[];
};

export type TimelineFrame = {
  id: string;
  slot: SlotName;
  name: string;
  hidden: boolean;
};

export type AnimationManifest = {
  cell: { w: number; h: number };
  foot: { x: number; y: number };
  facing: 1 | -1;
  displayHeight: number;
  hitDelaySeconds: number;
  slots: Record<SlotName, SlotClip>;
  timeline?: TimelineFrame[];
};

const LOOPING = new Set<SlotName>(["idle", "walk"]);
const HOLD_LAST = new Set<SlotName>(["down", "victory"]);
const DEFAULT_LUNGE: Partial<Record<SlotName, number>> = { attack: 24, skill: 18 };

export function defaultManifest(): AnimationManifest {
  const slots = {} as Record<SlotName, SlotClip>;
  for (const name of SLOT_NAMES) {
    slots[name] = {
      loop: LOOPING.has(name),
      holdLast: HOLD_LAST.has(name),
      frameDurationMs: 83,
      lungePx: DEFAULT_LUNGE[name] ?? 0,
      frames: [],
    };
  }
  return {
    cell: { w: 640, h: 320 },
    foot: { x: 240, y: 280 },
    facing: 1,
    displayHeight: 260,
    hitDelaySeconds: 1.21,
    slots,
  };
}

export function frameIndexAt(
  clip: { frameCount: number; frameDurationMs: number; loop: boolean },
  timeMs: number,
): number {
  if (clip.frameCount <= 0) return 0;
  const step = Math.max(1, clip.frameDurationMs);
  const index = Math.floor(Math.max(0, timeMs) / step);
  return clip.loop ? index % clip.frameCount : Math.min(index, clip.frameCount - 1);
}

export function lungeAt(lungePx: number, timeMs: number, actionMs: number): number {
  if (lungePx === 0 || actionMs <= 0) return 0;
  const t = Math.min(Math.max(timeMs, 0), actionMs) / actionMs;
  const triangle = t <= 0.5 ? t * 2 : (1 - t) * 2;
  return lungePx * triangle;
}

export function missingSlots(manifest: AnimationManifest): SlotName[] {
  return REQUIRED_SLOTS.filter((name) => manifest.slots[name].frames.length === 0);
}

export function timelineFromManifest(manifest: AnimationManifest): TimelineFrame[] {
  if (manifest.timeline && manifest.timeline.length > 0) return manifest.timeline;
  const frames: TimelineFrame[] = [];
  for (const slot of SLOT_NAMES) {
    manifest.slots[slot].frames.forEach((name, index) => {
      frames.push({ id: `${slot}-${name}-${index}`, slot, name, hidden: false });
    });
  }
  return frames;
}

export type Pose = {
  slot: SlotName;
  frame: number;
  lungePx: number;
  projectile: number | null;
  impact: boolean;
};

const ATTACK_START = 800;
const ATTACK_MS = 600;
const SKILL_START = 1700;

export function poseAt(manifest: AnimationManifest, timeMs: number): Pose {
  const t = Math.max(0, timeMs);
  if (t < ATTACK_START) return body(manifest, "idle", t);
  if (t < ATTACK_START + ATTACK_MS) return body(manifest, "attack", t - ATTACK_START, ATTACK_MS);
  if (t < SKILL_START) return body(manifest, "idle", t);

  const skillTime = t - SKILL_START;
  const hitMs = Math.max(300, manifest.hitDelaySeconds * 1000);
  const flightStart = hitMs * 0.66;
  const projectile =
    skillTime >= flightStart && skillTime < hitMs ? (skillTime - flightStart) / (hitMs - flightStart) : null;

  if (skillTime < hitMs * 0.37) return { ...body(manifest, "cast", skillTime), projectile, impact: false };
  if (skillTime < hitMs) return { ...body(manifest, "skill", skillTime - hitMs * 0.37), projectile, impact: false };
  if (skillTime < hitMs + 400) {
    return { ...body(manifest, "hit", skillTime - hitMs), projectile: null, impact: skillTime < hitMs + 360 };
  }
  return { ...body(manifest, "victory", skillTime - hitMs - 400), projectile: null, impact: false };
}

function body(manifest: AnimationManifest, slot: SlotName, timeMs: number, actionMs?: number): Pose {
  const clip = manifest.slots[slot];
  return {
    slot,
    frame: frameIndexAt(
      { frameCount: clip.frames.length, frameDurationMs: clip.frameDurationMs, loop: clip.loop },
      timeMs,
    ),
    lungePx: lungeAt(clip.lungePx, timeMs, actionMs ?? clip.frames.length * clip.frameDurationMs),
    projectile: null,
    impact: false,
  };
}
