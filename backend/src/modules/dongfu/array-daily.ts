/**
 * 阵法每日小游戏（灵脉接引）：日界、选关、管口连通 BFS。
 */
import { AppError } from "../../shared/errors.js";
import type { DongfuArrayDailyConfig, DongfuArrayPuzzle, DongfuArrayTile } from "./config.js";

export type Dir = "N" | "E" | "S" | "W";
export type ArrayRot = { r: number; c: number; rot: number };

const OPP: Record<Dir, Dir> = { N: "S", E: "W", S: "N", W: "E" };
const DELTA: Record<Dir, readonly [number, number]> = {
  N: [-1, 0],
  E: [0, 1],
  S: [1, 0],
  W: [0, -1],
};
const DIRS: Dir[] = ["N", "E", "S", "W"];

/** Asia/Shanghai 无夏令时：UTC+8 的 YYYY-MM-DD。 */
export function shanghaiDayKey(now: Date): string {
  const shifted = new Date(now.getTime() + 8 * 3_600_000);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, "0");
  const d = String(shifted.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/** dayKey 稳定哈希取模选关。 */
export function pickPuzzleForDay(puzzles: DongfuArrayPuzzle[], dayKey: string): DongfuArrayPuzzle {
  if (puzzles.length === 0) {
    throw new AppError("CONTENT_NOT_PUBLISHED", "阵法日游关卡未配置");
  }
  let hash = 0;
  for (let i = 0; i < dayKey.length; i += 1) {
    hash = (hash * 31 + dayKey.charCodeAt(i)) >>> 0;
  }
  return puzzles[hash % puzzles.length]!;
}

export function puzzleById(config: DongfuArrayDailyConfig, puzzleId: string): DongfuArrayPuzzle {
  const puzzle = config.puzzles.find((row) => row.puzzleId === puzzleId);
  if (!puzzle) {
    throw new AppError("PUZZLE_UNKNOWN", "阵图有变，请重新打开洞府");
  }
  return puzzle;
}

/** I=对边；L=邻边。rot 0..3 顺时针。 */
export function tileOpenings(shape: "I" | "L", rot: number): Dir[] {
  const r = ((rot % 4) + 4) % 4;
  if (shape === "I") {
    return r % 2 === 0 ? ["N", "S"] : ["E", "W"];
  }
  const pairs: Dir[][] = [
    ["N", "E"],
    ["E", "S"],
    ["S", "W"],
    ["W", "N"],
  ];
  return pairs[r]!;
}

function cellOpenings(
  grid: ({ kind: "endpoint"; open: Dir } | { kind: "tile"; opens: Dir[] } | null)[][],
  r: number,
  c: number,
): Dir[] {
  const cell = grid[r]?.[c];
  if (!cell) return [];
  return cell.kind === "endpoint" ? [cell.open] : cell.opens;
}

function canStep(
  grid: ({ kind: "endpoint"; open: Dir } | { kind: "tile"; opens: Dir[] } | null)[][],
  size: number,
  r: number,
  c: number,
  dir: Dir,
): boolean {
  if (!cellOpenings(grid, r, c).includes(dir)) return false;
  const [dr, dc] = DELTA[dir];
  const nr = r + dr;
  const nc = c + dc;
  if (nr < 0 || nc < 0 || nr >= size || nc >= size) return false;
  return cellOpenings(grid, nr, nc).includes(OPP[dir]);
}

/** 合成盘面并 BFS：source ↔ sink 是否正交连通且管口相对。 */
export function isSourceSinkConnected(
  puzzle: DongfuArrayPuzzle,
  rots: ArrayRot[],
  gridSize = 3,
): boolean {
  const grid: ({ kind: "endpoint"; open: Dir } | { kind: "tile"; opens: Dir[] } | null)[][] = Array.from(
    { length: gridSize },
    () => Array.from({ length: gridSize }, () => null),
  );
  grid[puzzle.source.r]![puzzle.source.c] = { kind: "endpoint", open: puzzle.source.open };
  grid[puzzle.sink.r]![puzzle.sink.c] = { kind: "endpoint", open: puzzle.sink.open };
  const rotMap = new Map(rots.map((row) => [`${row.r},${row.c}`, row.rot]));
  for (const tile of puzzle.tiles) {
    const rot = rotMap.has(`${tile.r},${tile.c}`) ? rotMap.get(`${tile.r},${tile.c}`)! : tile.rot;
    grid[tile.r]![tile.c] = { kind: "tile", opens: tileOpenings(tile.shape, rot) };
  }
  const startR = puzzle.source.r;
  const startC = puzzle.source.c;
  const queue: [number, number][] = [[startR, startC]];
  const seen = new Set<string>([`${startR},${startC}`]);
  while (queue.length > 0) {
    const [r, c] = queue.shift()!;
    if (r === puzzle.sink.r && c === puzzle.sink.c) return true;
    for (const dir of DIRS) {
      if (!canStep(grid, gridSize, r, c, dir)) continue;
      const [dr, dc] = DELTA[dir];
      const nr = r + dr;
      const nc = c + dc;
      const key = `${nr},${nc}`;
      if (seen.has(key)) continue;
      seen.add(key);
      queue.push([nr, nc]);
    }
  }
  return false;
}

/** 校验 rots 覆盖全部可旋格且 rot∈0..3；返回规范化列表。 */
export function normalizeRots(puzzle: DongfuArrayPuzzle, rots: unknown): ArrayRot[] {
  if (!Array.isArray(rots)) {
    throw new AppError("INVALID_INPUT", "请提交各格朝向");
  }
  const byKey = new Map<string, number>();
  for (const raw of rots) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new AppError("INVALID_INPUT", "朝向格式不正确");
    }
    const row = raw as Record<string, unknown>;
    if (!Number.isInteger(row.r) || !Number.isInteger(row.c) || !Number.isInteger(row.rot)) {
      throw new AppError("INVALID_INPUT", "朝向格式不正确");
    }
    const rot = row.rot as number;
    if (rot < 0 || rot > 3) {
      throw new AppError("INVALID_INPUT", "朝向须为 0–3");
    }
    byKey.set(`${row.r},${row.c}`, rot);
  }
  const out: ArrayRot[] = [];
  for (const tile of puzzle.tiles) {
    const key = `${tile.r},${tile.c}`;
    if (!byKey.has(key)) {
      throw new AppError("INVALID_INPUT", "朝向未覆盖全部管路");
    }
    out.push({ r: tile.r, c: tile.c, rot: byKey.get(key)! });
  }
  return out;
}

export function puzzlePayload(puzzle: DongfuArrayPuzzle, gridSize: number) {
  return {
    puzzleId: puzzle.puzzleId,
    gridSize,
    source: { ...puzzle.source },
    sink: { ...puzzle.sink },
    tiles: puzzle.tiles.map((tile: DongfuArrayTile) => ({ ...tile })),
  };
}
