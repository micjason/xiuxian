import { describe, expect, it } from "vitest";
import {
  DEFAULT_FOG,
  cellKey,
  fogConfigFromInput,
  fogMapOf,
  isBlocked,
  livingMonsterAt,
  revealAround,
  explorationOf,
  isFogExit,
} from "./config.js";

describe("fog config 问心谷", () => {
  it("matches level_objects meta IDs and spawn", () => {
    expect(DEFAULT_FOG.defaultMapId).toBe("fog_wenxin_valley");
    expect(DEFAULT_FOG.travelPointsMax).toBe(200);
    const map = fogMapOf(DEFAULT_FOG, "fog_wenxin_valley");
    expect(map.cols).toBe(8);
    expect(map.rows).toBe(12);
    expect(map.spawn).toEqual({ x: 3, y: 10 });
    const ids = map.objects.map((o) => o.id).sort();
    expect(ids).toEqual(
      [
        "c_high",
        "c_mid",
        "c_near",
        "e_herb",
        "m_guard",
        "m_slime",
        "m_wolf",
      ].sort(),
    );
    expect(map.objects.find((o) => o.id === "m_slime")).toMatchObject({
      x: 2,
      y: 8,
    });
    expect(map.objects.find((o) => o.id === "e_herb")).toMatchObject({
      x: 3,
      y: 4,
      kind: "event",
    });
  });

  it("blocks water/rock from level table", () => {
    const map = fogMapOf(DEFAULT_FOG, "fog_wenxin_valley");
    expect(isBlocked(map, 0, 3)).toBe(true);
    expect(isBlocked(map, 7, 6)).toBe(true);
    expect(isBlocked(map, 3, 10)).toBe(false);
  });

  it("reveals manhattan radius 1", () => {
    const map = fogMapOf(DEFAULT_FOG, "fog_wenxin_valley");
    const set = new Set<string>();
    revealAround(set, map, 3, 10, 1);
    expect(set.has(cellKey(3, 10))).toBe(true);
    expect(set.has(cellKey(3, 9))).toBe(true);
    expect(set.has(cellKey(2, 10))).toBe(true);
    expect(set.has(cellKey(3, 8))).toBe(false);
  });

  it("living monster occupies cell until defeated", () => {
    const map = fogMapOf(DEFAULT_FOG, "fog_wenxin_valley");
    expect(livingMonsterAt(map, {}, 2, 8)?.id).toBe("m_slime");
    expect(
      livingMonsterAt(map, { m_slime: { defeated: true } }, 2, 8),
    ).toBeNull();
  });

  it("parses tech-design shaped input", () => {
    const parsed = fogConfigFromInput({
      travelPointsMax: 20,
      defaultMapId: "fog_wenxin_valley",
      maps: [
        {
          id: "fog_wenxin_valley",
          width: 8,
          height: 12,
          spawn: { x: 3, y: 10 },
          blocks: [{ x: 0, y: 2 }],
          objects: [
            { id: "m_slime", type: "monster", x: 2, y: 8, name: "浊气小妖" },
          ],
        },
      ],
    });
    expect(parsed.maps[0]!.cols).toBe(8);
    expect(parsed.maps[0]!.objects[0]).toMatchObject({
      id: "m_slime",
      kind: "monster",
      x: 2,
      y: 8,
    });
  });
});

it("counts only in-bounds unblocked revealed cells and recognises legacy exit", () => {
  const map = DEFAULT_FOG.maps[0]!;
  expect(explorationOf(map, new Set(["3,10", "0,3", "99,99"]))).toEqual({
    exploreRevealed: 1,
    exploreTotal: 79,
    exploreFull: false,
  });
  const all = new Set<string>();
  for (let y = 0; y < map.rows; y++)
    for (let x = 0; x < map.cols; x++) all.add(cellKey(x, y));
  expect(explorationOf(map, all)).toEqual({
    exploreRevealed: 79,
    exploreTotal: 79,
    exploreFull: true,
  });
  const guard = map.objects.find((o) => o.id === "m_guard")!;
  expect(isFogExit(guard)).toBe(true);
  expect(
    isFogExit({ ...guard, id: "custom_exit", isExit: true } as typeof guard),
  ).toBe(true);
  expect(livingMonsterAt(map, {}, 4, 1)).toBeNull(); // exit doorstep must be walkable to reveal (4,0)
});
it("upgrades stored legacy Wenxin 20-point config, preserves the reveal formula", () => {
  const legacy = structuredClone(DEFAULT_FOG);
  legacy.travelPointsMax = 20;
  const parsed = fogConfigFromInput(legacy);
  expect(parsed.travelPointsMax).toBe(200);
  expect(parsed.revealRadius).toBe(1);
});

it("all 79 walkable cells including behind the gate are reachable within the budget", () => {
  const map = DEFAULT_FOG.maps[0]!;
  const visited = new Set<string>();
  function visit(x: number, y: number) {
    if (isBlocked(map, x, y) || visited.has(cellKey(x, y))) return;
    visited.add(cellKey(x, y));
    visit(x - 1, y);
    visit(x + 1, y);
    visit(x, y - 1);
    visit(x, y + 1);
  }
  visit(map.spawn.x, map.spawn.y);
  expect(visited.size).toBe(79);
  expect(visited.has("4,0")).toBe(true);
  // A DFS round trip costs at most 2*(V-1), plus at most V-1 to return to the exit.
  // This fixed level's shortest exit distance is 12; 200 leaves further interaction slack.
  expect(2 * (visited.size - 1) + 12).toBeLessThanOrEqual(
    DEFAULT_FOG.travelPointsMax,
  );
});
