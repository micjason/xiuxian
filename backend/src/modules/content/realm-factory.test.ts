import { describe, expect, it } from "vitest";
import { DEFAULT_REALM_YIELD_MULT, REALM_YIELD_MAJORS, resolveRealmYieldMajor } from "./enhance.js";
import { REALM_FACTORY, canonicalNextSlug, changedFieldKeys, editableKeys, listFixedRealms, showsBreakthroughCost, showsGate, type RealmNumbers } from "./realm-factory.js";

/** 照抄 realm_defaults §4.4：每秒修为、突破消耗、攻击、防御、气血、速度、预计时长。 */
const TABLE: [number, string, number, number, number, number, number, number, string][] = [
  [1, "炼气一层", 1, 1080, 10, 10, 33, 20, "约 30 分"],
  [2, "炼气二层", 1, 2160, 2, 2, 7, 0, "约 1.5 小时"],
  [3, "炼气三层", 1, 5400, 2, 2, 7, 0, "约 4 小时"],
  [4, "筑基一层", 3, 16200, 9, 9, 30, 10, "约 6.5 小时"],
  [5, "筑基二层", 3, 16200, 5, 5, 17, 0, "约 9 小时"],
  [6, "筑基三层", 3, 19440, 5, 5, 17, 0, "约 2 天"],
  [7, "金丹一层", 9, 77760, 20, 20, 67, 10, "约 2.5 天"],
  [8, "金丹二层", 9, 77760, 11, 11, 37, 0, "约 3.5 天"],
  [9, "金丹三层", 9, 77760, 12, 12, 40, 0, "约 4 天"],
  [10, "元婴一层", 27, 466560, 46, 46, 153, 10, "约 5.5 天"],
  [11, "元婴二层", 27, 466560, 25, 25, 83, 0, "约 7 天"],
  [12, "元婴三层", 27, 466560, 29, 29, 97, 0, "约 8 天"],
  [13, "化神一层", 81, 2099520, 106, 106, 353, 10, "约 10 天"],
  [14, "化神二层", 81, 2099520, 56, 56, 186, 0, "约 12 天"],
  [15, "化神三层", 81, 2099520, 68, 68, 226, 0, "约 14 天"],
  [16, "炼虚一层", 243, 8398080, 243, 243, 809, 10, "约 17 天"],
  [17, "炼虚二层", 243, 10497600, 130, 130, 433, 0, "约 20 天"],
  [18, "炼虚三层", 243, 10497600, 156, 156, 519, 0, "约 23 天"],
  [19, "合体一层", 729, 39366000, 561, 561, 1868, 10, "约 28 天"],
  [20, "合体二层", 729, 39366000, 299, 299, 996, 0, "约 32 天"],
  [21, "合体三层", 729, 47239200, 359, 359, 1195, 0, "约 37 天"],
  [22, "大乘一层", 2187, 165337200, 1292, 1292, 4302, 10, "约 43 天"],
  [23, "大乘二层", 2187, 165337200, 690, 690, 2298, 0, "约 48 天"],
  [24, "大乘三层", 2187, 0, 827, 827, 2754, 0, "约 55 天"],
];

function numbersOf(code: number, patch: Partial<RealmNumbers> = {}): RealmNumbers {
  const seed = REALM_FACTORY[code - 1]!;
  return {
    gainPerTick: seed.gainPerTick,
    breakthroughCost: seed.breakthroughCost,
    attack: seed.attack,
    defense: seed.defense,
    hp: seed.hp,
    speed: seed.speed,
    requiredStageId: seed.requiredStageId,
    ...patch,
  };
}

describe("realm factory seed (§17)", () => {
  it("copies the 24-row factory table and keeps the existing nine slugs", () => {
    expect(REALM_FACTORY.map((row) => [row.code, row.displayName, row.gainPerTick, row.breakthroughCost, row.attack, row.defense, row.hp, row.speed, row.etaLabel])).toEqual(TABLE);
    expect(REALM_FACTORY.slice(0, 9).map((row) => row.slug)).toEqual([
      "lianqi_1", "lianqi_2", "lianqi_3",
      "zhuji_1", "zhuji_2", "zhuji_3",
      "jindan_1", "jindan_2", "jindan_3",
    ]);
    for (let index = 0; index < REALM_FACTORY.length; index += 1) {
      const row = REALM_FACTORY[index]!;
      expect(canonicalNextSlug(row.slug)).toBe(REALM_FACTORY[index + 1]?.slug ?? null);
      expect(resolveRealmYieldMajor({ majorKey: row.majorKey, majorName: row.majorName })).toBe(row.majorKey);
    }
    expect(canonicalNextSlug("mortal")).toBeUndefined();
    expect([...REALM_YIELD_MAJORS]).toEqual([...new Set(REALM_FACTORY.map((row) => row.majorKey))]);
    for (const key of REALM_YIELD_MAJORS) expect(DEFAULT_REALM_YIELD_MULT[key]).toBeGreaterThan(0);
    expect(REALM_FACTORY.slice(0, 9).map((row) => row.majorKey)).toEqual([
      "qi", "qi", "qi",
      "foundation", "foundation", "foundation",
      "core", "core", "core",
    ]);
    expect(REALM_FACTORY.map((row) => row.majorName)).toEqual([
      "炼气", "炼气", "炼气",
      "筑基", "筑基", "筑基",
      "金丹", "金丹", "金丹",
      "元婴", "元婴", "元婴",
      "化神", "化神", "化神",
      "炼虚", "炼虚", "炼虚",
      "合体", "合体", "合体",
      "大乘", "大乘", "大乘",
    ]);
  });

  it("hides breakthrough cost only on 大乘三层, and the gate only on each major's third layer", () => {
    const qi1 = REALM_FACTORY[0]!;
    const qi3 = REALM_FACTORY[2]!;
    const last = REALM_FACTORY[23]!;
    expect(showsBreakthroughCost(last)).toBe(false);
    expect(showsBreakthroughCost(REALM_FACTORY[22]!)).toBe(true);
    expect(showsGate(qi1)).toBe(false);
    expect(showsGate(qi3)).toBe(true);
    expect(showsGate(last)).toBe(true);
    expect(editableKeys(last)).toEqual(["gainPerTick", "attack", "defense", "hp", "speed", "requiredStageId"]);
    expect(editableKeys(qi1)).toEqual(["gainPerTick", "breakthroughCost", "attack", "defense", "hp", "speed"]);
    expect(editableKeys(qi3)).toEqual(["gainPerTick", "breakthroughCost", "attack", "defense", "hp", "speed", "requiredStageId"]);
  });

  it("diffs numbers against the factory constants; shipped gates stay factory and are not recomputed from cultivation", () => {
    // 各大境第 3 层共 7 个闸（不含大乘三层到顶）
    expect(REALM_FACTORY.filter((row) => row.requiredStageId).map((row) => row.requiredStageId)).toEqual([
      "lianqi_3", "zhuji_3", "jindan_3", "yuanying_3", "huashen_3", "lianxu_3", "heti_3",
    ]);
    expect(REALM_FACTORY[23]!.requiredStageId).toBe("");
    expect(REALM_FACTORY.filter((row) => row.layer !== 3).every((row) => row.requiredStageId === "")).toBe(true);
    expect(changedFieldKeys(REALM_FACTORY[4]!, numbersOf(5, { gainPerTick: 4 }))).toEqual(["gainPerTick"]);
    expect(changedFieldKeys(REALM_FACTORY[23]!, numbersOf(24, { breakthroughCost: 5 }))).toEqual(["breakthroughCost"]);
    expect(changedFieldKeys(REALM_FACTORY[0]!, numbersOf(1, { requiredStageId: "lianqi_3" }))).toEqual([]);
    expect(changedFieldKeys(REALM_FACTORY[8]!, numbersOf(9, { requiredStageId: "jindan_3" }))).toEqual([]);
    expect(changedFieldKeys(REALM_FACTORY[8]!, numbersOf(9, { requiredStageId: "" }))).toEqual(["requiredStageId"]);
    expect(REALM_FACTORY[8]!.etaLabel).toBe("约 4 天");
    expect(REALM_FACTORY[14]!.etaLabel).toBe("约 14 天");
    expect(REALM_FACTORY[23]!.etaLabel).toBe("约 55 天");
  });

  it("lists exactly the 24 canonical rows, shows canonical names, and drops extra realms", () => {
    const listed = listFixedRealms([
      {
        slug: "mortal",
        displayName: "凡人",
        sortOrder: 99,
        gainPerTick: 9,
        breakthroughCost: 1,
        baseAttack: 1,
        baseDefense: 1,
        baseHp: 1,
        baseSpeed: 1,
        baseInterval: 1.5,
        tickSeconds: 1,
        requiredStageSlug: null,
      },
      {
        slug: "zhuji_2",
        displayName: "随便改的名字",
        sortOrder: 5,
        gainPerTick: 4,
        breakthroughCost: 16200,
        baseAttack: 5,
        baseDefense: 5,
        baseHp: 17,
        baseSpeed: 0,
        baseInterval: 1.5,
        tickSeconds: 1,
        requiredStageSlug: null,
      },
    ]);
    expect(listed).toHaveLength(24);
    expect(listed.some((row) => row.slug === "mortal" || row.displayName === "凡人")).toBe(false);
    expect(listed[0]).toMatchObject({
      code: 1,
      slug: "lianqi_1",
      displayName: "炼气一层",
      stored: false,
      tuned: false,
      etaLabel: "约 30 分",
      gainPerTick: 1,
      breakthroughCost: 1080,
      attack: 10,
      interval: 1.5,
    });
    expect(listed[4]).toMatchObject({
      code: 5,
      displayName: "筑基二层",
      stored: true,
      gainPerTick: 4,
      tuned: true,
      changed: ["gainPerTick"],
      etaLabel: "约 9 小时",
      showGate: false,
      showBreakthroughCost: true,
    });
    expect(listed[23]).toMatchObject({ showBreakthroughCost: false, showGate: true, etaLabel: "约 55 天", breakthroughCost: 0 });
  });
});
