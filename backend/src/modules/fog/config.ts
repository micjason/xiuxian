/**
 * 迷雾秘境 P0：问心谷。坐标真源 = fog_art_delivery meta/level_objects.json + FOG_LEVEL_DESIGN。
 * 约定：左上 (0,0)，+x 右，+y 下；8×12。API/DTO 用 x/y；库表 pos_c=x、pos_r=y。
 */

export type FogLoot = { itemSlug: string; quantity: number };

export type FogChestObject = {
  id: string;
  kind: "chest";
  x: number;
  y: number;
  loot: FogLoot[];
  /** 发技能书残页（用 skill_tuna 书） */
  grantSkillBook?: boolean;
};

export type FogMonsterObject = {
  id: string;
  kind: "monster";
  x: number;
  y: number;
  name: string;
  attack: number;
  defense: number;
  hp: number;
  interval: number;
  loot: FogLoot[];
  skillBookSkillSlug?: string;
  isExit?: boolean;
};

export type FogEventOption = {
  id: string;
  label: string;
  effect: "battle" | "none";
  enemyId?: string;
};

export type FogEventObject = {
  id: string;
  kind: "event";
  x: number;
  y: number;
  title: string;
  options: FogEventOption[];
  battleEnemy: {
    name: string;
    attack: number;
    defense: number;
    hp: number;
    interval: number;
    loot: FogLoot[];
  };
};

export type FogMapObject = FogChestObject | FogMonsterObject | FogEventObject;

export type FogMapConfig = {
  id: string;
  displayName: string;
  rows: number;
  cols: number;
  spawn: { x: number; y: number };
  blocks: { x: number; y: number }[];
  objects: FogMapObject[];
  timeLimitSeconds?: number;
};

export type FogConfig = {
  travelPointsMax: number;
  travelCostPerStep: number;
  revealRadius: number;
  initialReveal: number;
  defaultMapId: string;
  maps: FogMapConfig[];
};

/** 关卡表 §3 / meta.blocked */
const WENXIN_BLOCKS: { x: number; y: number }[] = [
  // water
  { x: 0, y: 2 }, { x: 0, y: 3 }, { x: 0, y: 4 }, { x: 0, y: 5 }, { x: 1, y: 3 }, { x: 1, y: 4 },
  // rock
  { x: 2, y: 0 }, { x: 3, y: 0 }, { x: 5, y: 0 }, { x: 6, y: 0 },
  { x: 2, y: 5 }, { x: 5, y: 4 },
  { x: 6, y: 6 }, { x: 6, y: 8 }, { x: 7, y: 5 }, { x: 7, y: 6 }, { x: 7, y: 7 },
];

export const DEFAULT_FOG: FogConfig = {
  travelPointsMax: 200,
  travelCostPerStep: 1,
  revealRadius: 1,
  initialReveal: 1,
  defaultMapId: "fog_wenxin_valley",
  maps: [
    {
      id: "fog_wenxin_valley",
      displayName: "问心谷",
      rows: 12,
      cols: 8,
      spawn: { x: 3, y: 10 },
      blocks: WENXIN_BLOCKS,
      objects: [
        {
          id: "m_slime",
          kind: "monster",
          x: 2,
          y: 8,
          name: "浊气小妖",
          attack: 6,
          defense: 1,
          hp: 30,
          interval: 1.6,
          loot: [{ itemSlug: "herb_lingcao", quantity: 1 }],
        },
        {
          id: "m_wolf",
          kind: "monster",
          x: 5,
          y: 6,
          name: "影狼",
          attack: 12,
          defense: 4,
          hp: 70,
          interval: 1.4,
          loot: [{ itemSlug: "herb_qingxin", quantity: 1 }],
        },
        {
          id: "m_guard",
          kind: "monster",
          x: 4,
          y: 1,
          name: "谷口护卫",
          attack: 18,
          defense: 6,
          hp: 100,
          interval: 1.3,
          loot: [
            { itemSlug: "herb_lingcao", quantity: 2 },
            { itemSlug: "herb_qingxin", quantity: 1 },
          ],
        },
        {
          id: "c_near",
          kind: "chest",
          x: 4,
          y: 9,
          loot: [{ itemSlug: "herb_lingcao", quantity: 3 }],
        },
        {
          id: "c_mid",
          kind: "chest",
          x: 1,
          y: 6,
          loot: [{ itemSlug: "herb_lingcao", quantity: 5 }],
        },
        {
          id: "c_high",
          kind: "chest",
          x: 6,
          y: 3,
          loot: [],
          grantSkillBook: true,
        },
        {
          id: "e_herb",
          kind: "event",
          x: 3,
          y: 4,
          title: "仙草争执",
          options: [
            {
              id: "A",
              label: "上前理论",
              effect: "battle",
              enemyId: "temp_herbalist",
            },
            { id: "B", label: "转身离开", effect: "none" },
          ],
          battleEnemy: {
            name: "采药修士",
            attack: 10,
            defense: 3,
            hp: 50,
            interval: 1.5,
            loot: [{ itemSlug: "herb_qingxin", quantity: 2 }],
          },
        },
      ],
    },
  ],
};

function asInt(v: unknown, fallback: number, min = 0, max = 9999): number {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}

function asLoot(raw: unknown): FogLoot[] {
  if (!Array.isArray(raw)) return [];
  const out: FogLoot[] = [];
  for (const row of raw) {
    if (!row || typeof row !== "object") continue;
    const o = row as Record<string, unknown>;
    if (typeof o.itemSlug === "string" && o.itemSlug) {
      const quantity = asInt(o.quantity ?? o.count, 0, 1, 999);
      if (quantity > 0) out.push({ itemSlug: o.itemSlug, quantity });
    } else if (o.kind === "herb") {
      out.push({ itemSlug: "herb_lingcao", quantity: asInt(o.count, 1, 1, 999) });
    }
  }
  return out;
}

function xyOf(o: Record<string, unknown>): { x: number; y: number } | null {
  const x = o.x !== undefined ? asInt(o.x, -1) : asInt(o.c, -1);
  const y = o.y !== undefined ? asInt(o.y, -1) : asInt(o.r, -1);
  if (x < 0 || y < 0) return null;
  return { x, y };
}

function asObjects(raw: unknown): FogMapObject[] {
  if (!Array.isArray(raw)) return [];
  const out: FogMapObject[] = [];
  for (const row of raw) {
    if (!row || typeof row !== "object") continue;
    const o = row as Record<string, unknown>;
    const id = typeof o.id === "string" ? o.id : "";
    const kind = String(o.kind ?? o.type ?? "");
    const pos = xyOf(o);
    if (!id || !pos || kind === "spawn") continue;
    if (kind === "chest") {
      out.push({
        id,
        kind: "chest",
        x: pos.x,
        y: pos.y,
        loot: asLoot(o.loot),
        grantSkillBook: o.grantSkillBook === true || id === "c_high",
      });
    } else if (kind === "monster") {
      out.push({
        id,
        kind: "monster",
        x: pos.x,
        y: pos.y,
        name: typeof o.name === "string" && o.name ? o.name : "雾怪",
        attack: asInt(o.attack, 10, 1),
        defense: asInt(o.defense, 0, 0),
        hp: asInt(o.hp, 50, 1),
        interval: Math.max(0.2, Number(o.interval) || 1.5),
        loot: asLoot(o.loot),
        isExit: o.isExit === true || id === "m_guard",
        skillBookSkillSlug:
          typeof o.skillBookSkillSlug === "string"
            ? o.skillBookSkillSlug
            : undefined,
      });
    } else if (kind === "event") {
      const optionsRaw = Array.isArray(o.options) ? o.options : [];
      let options: FogEventOption[] = [];
      for (const opt of optionsRaw) {
        if (!opt || typeof opt !== "object") continue;
        const oo = opt as Record<string, unknown>;
        const oid = typeof oo.id === "string" ? oo.id : "";
        if (!oid) continue;
        options.push({
          id: oid,
          label: typeof oo.label === "string" ? oo.label : oid,
          effect: oo.effect === "battle" ? "battle" : "none",
          enemyId: typeof oo.enemyId === "string" ? oo.enemyId : undefined,
        });
      }
      if (options.length === 0) {
        options = [
          {
            id: "A",
            label: typeof o.option_a === "string" ? o.option_a : "上前理论",
            effect: "battle",
            enemyId: "temp_herbalist",
          },
          {
            id: "B",
            label: typeof o.option_b === "string" ? o.option_b : "转身离开",
            effect: "none",
          },
        ];
      }
      const be =
        o.battleEnemy && typeof o.battleEnemy === "object"
          ? (o.battleEnemy as Record<string, unknown>)
          : null;
      out.push({
        id,
        kind: "event",
        x: pos.x,
        y: pos.y,
        title:
          typeof o.title === "string" && o.title
            ? o.title
            : typeof o.name === "string"
              ? o.name
              : "事件",
        options,
        battleEnemy: be
          ? {
              name: typeof be.name === "string" ? be.name : "临时敌",
              attack: asInt(be.attack, 10, 1),
              defense: asInt(be.defense, 0, 0),
              hp: asInt(be.hp, 50, 1),
              interval: Math.max(0.2, Number(be.interval) || 1.5),
              loot: asLoot(be.loot),
            }
          : {
              name: "采药修士",
              attack: 10,
              defense: 3,
              hp: 50,
              interval: 1.5,
              loot: [{ itemSlug: "herb_qingxin", quantity: 2 }],
            },
      });
    }
  }
  return out;
}

function asMap(raw: unknown): FogMapConfig | null {
  if (!raw || typeof raw !== "object") return null;
  const m = raw as Record<string, unknown>;
  const id = typeof m.id === "string" ? m.id : "";
  if (!id) return null;
  const spawnRaw =
    m.spawn && typeof m.spawn === "object"
      ? (m.spawn as Record<string, unknown>)
      : {};
  const spawnPos = xyOf(spawnRaw) ?? { x: 0, y: 0 };
  const blocks = Array.isArray(m.blocks)
    ? m.blocks
        .map((b) =>
          b && typeof b === "object"
            ? xyOf(b as Record<string, unknown>)
            : null,
        )
        .filter((b): b is { x: number; y: number } => !!b)
    : [];
  return {
    id,
    displayName:
      typeof m.displayName === "string" && m.displayName
        ? m.displayName
        : typeof m.name === "string"
          ? m.name
          : id,
    rows: asInt(m.rows ?? m.height, 12, 3, 32),
    cols: asInt(m.cols ?? m.width, 8, 3, 32),
    spawn: spawnPos,
    blocks,
    objects: asObjects(m.objects),
    timeLimitSeconds:
      m.timeLimitSeconds == null
        ? undefined
        : asInt(m.timeLimitSeconds, 45, 1, 600),
  };
}

export function fogConfigFromInput(raw: unknown): FogConfig {
  const base = DEFAULT_FOG;
  if (!raw || typeof raw !== "object") return structuredClone(base);
  const o = raw as Record<string, unknown>;
  const mapsRaw = Array.isArray(o.maps) ? o.maps : base.maps;
  const maps = mapsRaw.map(asMap).filter((m): m is FogMapConfig => !!m);
  const storedBudget = asInt(
    o.travelPointsMax ?? o.travel_points_initial,
    base.travelPointsMax,
    1,
    999,
  );
  // Compatibility with globals already stored before the full-exploration exit.
  const legacyWenxin =
    maps.some((m) => m.id === "fog_wenxin_valley") && storedBudget === 20;
  return {
    travelPointsMax: legacyWenxin ? base.travelPointsMax : storedBudget,
    travelCostPerStep: asInt(
      o.travelCostPerStep,
      base.travelCostPerStep,
      1,
      99,
    ),
    revealRadius: asInt(
      o.revealRadius ?? o.revealRadiusManhattan,
      base.revealRadius,
      0,
      5,
    ),
    initialReveal: asInt(
      o.initialReveal ?? o.initialRevealManhattan,
      base.initialReveal,
      0,
      5,
    ),
    defaultMapId:
      typeof o.defaultMapId === "string" && o.defaultMapId
        ? o.defaultMapId
        : (maps[0]?.id ?? base.defaultMapId),
    maps: maps.length > 0 ? maps : structuredClone(base.maps),
  };
}

export function requireFog(raw: unknown): FogConfig {
  return fogConfigFromInput(raw ?? DEFAULT_FOG);
}

export function fogMapOf(config: FogConfig, mapId: string): FogMapConfig {
  const map = config.maps.find((m) => m.id === mapId);
  if (!map) throw new Error(`fog map missing: ${mapId}`);
  return map;
}

export function cellKey(x: number, y: number): string {
  return `${x},${y}`;
}

export function isBlocked(map: FogMapConfig, x: number, y: number): boolean {
  if (x < 0 || y < 0 || x >= map.cols || y >= map.rows) return true;
  return map.blocks.some((b) => b.x === x && b.y === y);
}

export function neighbors4(x: number, y: number): { x: number; y: number }[] {
  return [
    { x: x - 1, y },
    { x: x + 1, y },
    { x, y: y - 1 },
    { x, y: y + 1 },
  ];
}

export function revealAround(revealed: Set<string>, map: FogMapConfig, x: number, y: number, radius: number): string[] {
  const added: string[] = [];
  for (let dy = -radius; dy <= radius; dy += 1) {
    for (let dx = -radius; dx <= radius; dx += 1) {
      if (Math.abs(dx) + Math.abs(dy) > radius) continue;
      const xx = x + dx;
      const yy = y + dy;
      if (xx < 0 || yy < 0 || xx >= map.cols || yy >= map.rows) continue;
      const key = cellKey(xx, yy);
      if (!revealed.has(key)) {
        revealed.add(key);
        added.push(key);
      }
    }
  }
  return added;
}

export function livingMonsterAt(
  map: FogMapConfig,
  objects: Record<string, { defeated?: boolean }>,
  x: number,
  y: number,
): FogMonsterObject | null {
  for (const obj of map.objects) {
    if (obj.kind !== "monster" || isFogExit(obj)) continue;
    if (obj.x !== x || obj.y !== y) continue;
    if (objects[obj.id]?.defeated) continue;
    return obj;
  }
  return null;
}

/** Legacy databases have no isExit flag: the stable guard ID is sufficient. */
export function isFogExit(obj: FogMapObject): boolean {
  return (
    obj.kind === "monster" && (obj.id === "m_guard" || obj.isExit === true)
  );
}
/** Exploration = revealed in-bounds walkable cells / every in-bounds walkable cell.
 * Blocks never contribute to numerator or denominator; duplicates/out-of-bounds are ignored. */
export function explorationOf(map: FogMapConfig, revealed: Set<string>) {
  let exploreRevealed = 0,
    exploreTotal = 0;
  for (let y = 0; y < map.rows; y++)
    for (let x = 0; x < map.cols; x++) {
      if (isBlocked(map, x, y)) continue;
      exploreTotal++;
      if (revealed.has(cellKey(x, y))) exploreRevealed++;
    }
  return {
    exploreRevealed,
    exploreTotal,
    exploreFull: exploreTotal > 0 && exploreRevealed === exploreTotal,
  };
}
