import { describe, expect, it } from "vitest";
import { DEFAULT_ARRAY_DAILY } from "./config.js";
import {
  isSourceSinkConnected,
  pickPuzzleForDay,
  shanghaiDayKey,
  tileOpenings,
} from "./array-daily.js";

const VEIN_01 = DEFAULT_ARRAY_DAILY.puzzles.find((p) => p.puzzleId === "vein_01")!;

/** 对 vein_01 的一解（BFS 搜出）。 */
const VEIN_01_SOLUTION = [
  { r: 0, c: 1, rot: 1 },
  { r: 0, c: 2, rot: 2 },
  { r: 1, c: 0, rot: 1 },
  { r: 1, c: 1, rot: 1 },
  { r: 1, c: 2, rot: 3 },
  { r: 2, c: 0, rot: 0 },
  { r: 2, c: 1, rot: 1 },
];

describe("array-daily helpers", () => {
  it("shanghaiDayKey uses Asia/Shanghai calendar day", () => {
    // 2026-11-01 00:30 +08 = 2026-10-31 16:30Z
    expect(shanghaiDayKey(new Date("2026-10-31T16:30:00.000Z"))).toBe("2026-11-01");
    // 2026-10-31 23:30 +08 = 2026-10-31 15:30Z
    expect(shanghaiDayKey(new Date("2026-10-31T15:30:00.000Z"))).toBe("2026-10-31");
  });

  it("tileOpenings I/L rotations", () => {
    expect(tileOpenings("I", 0)).toEqual(["N", "S"]);
    expect(tileOpenings("I", 1)).toEqual(["E", "W"]);
    expect(tileOpenings("L", 0)).toEqual(["N", "E"]);
    expect(tileOpenings("L", 2)).toEqual(["S", "W"]);
  });

  it("vein_01 factory initial is not connected; solution is", () => {
    expect(VEIN_01).toBeTruthy();
    const initial = VEIN_01.tiles.map((t) => ({ r: t.r, c: t.c, rot: t.rot }));
    expect(isSourceSinkConnected(VEIN_01, initial, 3)).toBe(false);
    expect(isSourceSinkConnected(VEIN_01, VEIN_01_SOLUTION, 3)).toBe(true);
  });

  it("pickPuzzleForDay is stable for a dayKey", () => {
    const a = pickPuzzleForDay(DEFAULT_ARRAY_DAILY.puzzles, "2026-11-01");
    const b = pickPuzzleForDay(DEFAULT_ARRAY_DAILY.puzzles, "2026-11-01");
    expect(a.puzzleId).toBe(b.puzzleId);
    expect(DEFAULT_ARRAY_DAILY.puzzles.map((p) => p.puzzleId).sort()).toEqual([
      "vein_01",
      "vein_02",
      "vein_03",
    ]);
  });
});
