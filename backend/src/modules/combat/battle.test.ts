import { describe, expect, it } from "vitest";
import { cleanUltTaps, DEFAULT_SKILL_CAST_EVERY_ATTACKS, DEFAULT_SKILL_DAMAGE_MULT_BP, hitDamage, publicSkillName, skillCastDamage, skillCastsOnAttack, simulateBattle, simulateBossFight, toCombatSkills } from "./battle.js";

const config = { timeLimitSeconds: 60, defenseConstant: 1 };

describe("hitDamage", () => {
  it("blocks half the damage when attack equals defense", () => {
    expect(hitDamage(100, 100, 1)).toBe(50);
  });

  it("doubles the damage when both sides double", () => {
    expect(hitDamage(200, 200, 1)).toBe(2 * hitDamage(100, 100, 1));
  });

  it("deals full attack against zero defense", () => {
    expect(hitDamage(100, 0, 1)).toBe(100);
  });

  it("deals nothing with zero attack", () => {
    expect(hitDamage(0, 0, 1)).toBe(0);
    expect(hitDamage(0, 50, 1)).toBe(0);
  });

  it("never drops to a cliff when defense is far above attack", () => {
    expect(hitDamage(10, 1000, 1)).toBeGreaterThan(0);
  });
});

describe("simulateBattle", () => {
  it("times out when the boss cannot be finished in time", () => {
    const result = simulateBattle(
      { attack: 1, defense: 0, hp: 100, interval: 10 },
      { attack: 0, defense: 0, hp: 10000, interval: 10 },
      { ...config, timeLimitSeconds: 5 },
    );
    expect(result).toMatchObject({ win: false, reason: "timeout" });
  });

  it("lets the player strike first when both act at the same time", () => {
    const result = simulateBattle(
      { attack: 10, defense: 10, hp: 20, interval: 2 },
      { attack: 10, defense: 0, hp: 10, interval: 2 },
      config,
    );
    expect(result.win).toBe(true);
    expect(result.log[0]?.side).toBe("player");
    expect(result.durationSeconds).toBe(2);
  });

  it("finishes a same-level boss in about nine seconds", () => {
    const side = { attack: 100, defense: 100, hp: 333, interval: 1.25 };
    const result = simulateBattle(side, side, { ...config, timeLimitSeconds: 20 });
    expect(result).toMatchObject({ win: true, reason: "win" });
    expect(result.durationSeconds).toBeCloseTo(8.75, 6);
  });
});

describe("simulateBossFight (ultimate with tap timestamps)", () => {
  const ult = { multBp: 40000, cooldownSeconds: 20, firstCooldownSeconds: 8, autoCastWindowSeconds: 2 };
  const player = { hp: 5000, attack: 100, defense: 0, interval: 1 };
  const boss = { hp: 100000, attack: 1, defense: 0, interval: 2 };
  const config = { timeLimitSeconds: 60, defenseConstant: 1 };
  const casts = (taps: number[], limit = config.timeLimitSeconds) => simulateBossFight(player, boss, { ...config, timeLimitSeconds: limit }, ult, taps).ultCasts;

  it("equals simulateBattle exactly when there is no ultimate (null / zero multiplier)", () => {
    let state = 99;
    const rand = (n: number) => {
      state = (state * 48271) % 2147483647;
      return 1 + (state % n);
    };
    for (let i = 0; i < 200; i += 1) {
      const p = { hp: 100 + rand(900), attack: 10 + rand(90), defense: rand(60), interval: 0.5 + rand(20) / 10 };
      const b = { hp: 200 + rand(3000), attack: 5 + rand(80), defense: rand(60), interval: 0.5 + rand(20) / 10 };
      const base = simulateBattle(p, b, config);
      for (const u of [null, { ...ult, multBp: 0 }]) {
        const fight = simulateBossFight(p, b, config, u, [8, 9]);
        expect({ win: fight.win, reason: fight.reason, durationSeconds: fight.durationSeconds, log: fight.log }).toEqual(base);
        expect(fight.ultCasts).toEqual([]);
      }
    }
  });

  it("without taps the ultimate fires automatically 2 s after it is ready (8 + 2 = 10 s), then every 20 s + 2 s", () => {
    const result = casts([]);
    expect(result.map((cast) => [cast.t, cast.readyAt, cast.manual])).toEqual([
      [10, 8, false],
      [32, 30, false],
      [54, 52, false],
    ]);
    expect(result[0]!.damage).toBe(400); // 4 倍普攻 100
  });

  it("a tap inside the window casts at the tap time; the cooldown restarts from the cast", () => {
    const result = casts([8.5, 29]);
    expect(result.slice(0, 2).map((cast) => [cast.t, cast.manual])).toEqual([
      [8.5, true],
      [29, true],
    ]);
    expect(result[1]!.readyAt).toBeCloseTo(28.5, 9);
  });

  it("taps before the ultimate is ready are ignored; taps after the window auto-cast already happened", () => {
    expect(casts([1, 2, 7.99]).map((cast) => [cast.t, cast.manual])[0]).toEqual([10, false]);
    // 10.5 超过窗口（8+2=10）：第 1 次已经自动放了；10.5 也在下一次冷却好之前，无效
    expect(casts([10.5]).map((cast) => cast.manual)).toEqual([false, false, false]);
  });

  it("tapping exactly when ready is the fastest possible cast; nobody can cast earlier by spamming taps", () => {
    const spam = Array.from({ length: 50 }, (_, index) => 7 + index * 0.1);
    const spamCasts = casts(spam);
    expect(spamCasts[0]!.t).toBe(8); // 7.0–7.9 的点击无效，8.0 起的第一个点击立刻放
    expect(spamCasts[0]!.manual).toBe(true);
    const best = casts([8, 28, 48]);
    expect(best.map((cast) => cast.t)).toEqual([8, 28, 48]);
    // 连点不会让第二次提前于冷却好的时间
    expect(spamCasts[1]!.t).toBeGreaterThanOrEqual(28);
  });

  it("the ultimate adds damage on top of normal attacks and shortens the fight; the log marks it", () => {
    const weak = { hp: 1500, attack: 1, defense: 0, interval: 2 };
    const without = simulateBattle(player, weak, config);
    const withUlt = simulateBossFight(player, weak, config, ult, [8]);
    expect(withUlt.win).toBe(true);
    expect(withUlt.durationSeconds).toBeLessThan(without.durationSeconds);
    const ultEvents = withUlt.log.filter((event) => event.kind === "ult");
    expect(ultEvents).toHaveLength(1);
    expect(ultEvents[0]).toMatchObject({ t: 8, side: "player", damage: 400 });
    // 8 秒处同时有普攻和大招：普攻在前
    const atEight = withUlt.log.filter((event) => event.t === 8 && event.side === "player");
    expect(atEight.map((event) => event.kind ?? "hit")).toEqual(["hit", "ult"]);
  });

  it("waits mode: each cast waits 0–2 s after ready; missing or out-of-range entries clamp / fall back to auto", () => {
    const run = (waits: number[]) => simulateBossFight(player, boss, config, ult, { waits }).ultCasts;
    expect(run([0, 1]).slice(0, 2).map((cast) => [cast.t, cast.manual])).toEqual([
      [8, true],
      [29, true],
    ]);
    expect(run([99]).map((cast) => cast.t)[0]).toBe(10); // 超过窗口按 2 秒自动
    expect(run([-5])[0]!.t).toBe(8);
    expect(run([])[0]).toMatchObject({ t: 10, manual: false });
    // 等待 0.5 秒的结果 = 在 ready + 0.5 处点击
    expect(run([0.5, 0.5])).toEqual(casts([8.5, 29]).slice(0, 2).concat(run([0.5, 0.5]).slice(2)));
  });

  it("is deterministic for the same taps and the server re-simulation ignores junk taps", () => {
    const a = simulateBossFight(player, boss, config, ult, [8.2]);
    expect(simulateBossFight(player, boss, config, ult, [8.2])).toEqual(a);
    expect(cleanUltTaps([3, "x", -1, NaN, Infinity, 8.2, null])).toEqual([0, 3, 8.2]);
    expect(cleanUltTaps("nope")).toEqual([]);
    expect(cleanUltTaps(Array.from({ length: 80 }, (_, index) => 80 - index))).toHaveLength(50);
  });

  it("records a cast from a running auto or passive skill without using a realm ultimate", () => {
    const player = { attack: 100, defense: 0, hp: 5000, interval: 1 };
    const boss = { attack: 1, defense: 0, hp: 100000, interval: 5 };
    const limit = { timeLimitSeconds: 20, defenseConstant: 1 };
    const skills = toCombatSkills(
      [
        { skillSlug: "skill_liekong", runningSlot: "run_1" },
        { skillSlug: "skill_tuna", runningSlot: "run_2" },
        { skillSlug: "skill_idle", runningSlot: null },
        { skillSlug: "skill_off", runningSlot: "run_3" },
      ],
      [
        { slug: "skill_liekong", displayName: "裂空斩", castMode: "auto", fxType: "slash", fx: { type: "slash", primary: "#F5FBFF", secondary: "#A8E8E0", scale: 1 }, enabled: true },
        { slug: "skill_tuna", displayName: "吐纳诀", castMode: "passive", fxType: "heal_circle", enabled: true },
        { slug: "skill_idle", displayName: "未运转", castMode: "auto", enabled: true },
        { slug: "skill_off", displayName: "已关闭", castMode: "auto", enabled: false },
        { slug: "skill_bad", displayName: "大招", castMode: "auto", enabled: true },
      ],
      3,
    );
    expect(skills.map((skill) => skill.slug)).toEqual(["skill_liekong", "skill_tuna"]);
    expect(
      toCombatSkills(
        [
          { skillSlug: "skill_liekong", runningSlot: "run_2" },
          { skillSlug: "skill_tuna", runningSlot: "run_1" },
        ],
        [
          { slug: "skill_liekong", displayName: "裂空斩", castMode: "auto", enabled: true },
          { slug: "skill_tuna", displayName: "吐纳诀", castMode: "passive", enabled: true },
        ],
        1,
      ).map((skill) => skill.slug),
    ).toEqual(["skill_tuna"]);
    expect(publicSkillName("大招")).toBe("自动技能");
    expect(publicSkillName("暴击")).toBe("自动技能");
    expect(publicSkillName("")).toBe("自动技能");

    const fight = simulateBossFight(player, boss, limit, null, [], skills);
    const casts = fight.log.filter((event) => event.kind === "ult");
    expect(casts.length).toBeGreaterThan(0);
    expect(casts.map((event) => event.name)).toEqual(["裂空斩", "吐纳诀", "裂空斩", "吐纳诀", "裂空斩"]);
    expect(casts.map((event) => event.t)).toEqual([1, 5, 9, 13, 17]);
    expect(casts[0]).toMatchObject({
      side: "player",
      skillSlug: "skill_liekong",
      name: "裂空斩",
      fxType: "slash",
      castMode: "auto",
      damage: hitDamage(100, 0, 1),
    });
    expect(casts[1]).toMatchObject({ skillSlug: "skill_tuna", name: "吐纳诀", castMode: "passive", fxType: "heal_circle" });
    expect(fight.ultCasts.map((cast) => [cast.t, cast.manual, cast.skillSlug, cast.name])).toEqual(
      casts.map((event) => [event.t, false, event.skillSlug, event.name]),
    );
    const weak = { attack: 1, defense: 0, hp: 800, interval: 5 };
    const plain = simulateBattle(player, weak, limit);
    const shorter = simulateBossFight(player, weak, limit, null, [], skills);
    expect(plain.durationSeconds).toBe(8);
    expect(shorter.durationSeconds).toBeLessThan(plain.durationSeconds);
    expect(shorter.log.some((event) => event.kind === "ult")).toBe(true);
    expect(JSON.stringify(fight.log)).not.toContain("大招");
    expect(JSON.stringify(fight.ultCasts)).not.toContain("大招");

    const renamed = toCombatSkills([{ skillSlug: "skill_bad", runningSlot: "run_1" }], [{ slug: "skill_bad", displayName: "大招", castMode: "auto", enabled: true }], 1);
    const renamedFight = simulateBossFight(player, boss, { ...limit, timeLimitSeconds: 1 }, null, [], renamed);
    expect(renamedFight.log.find((event) => event.kind === "ult")?.name).toBe("自动技能");
    expect(JSON.stringify(renamedFight)).not.toContain("大招");
  });

  it("uses per-skill castEveryAttacks and damageMultBp while defaults match the old every-4 / 1.0x path", () => {
    expect(DEFAULT_SKILL_CAST_EVERY_ATTACKS).toBe(4);
    expect(DEFAULT_SKILL_DAMAGE_MULT_BP).toBe(10000);
    expect(skillCastsOnAttack(1)).toBe(true);
    expect(skillCastsOnAttack(2)).toBe(false);
    expect(skillCastsOnAttack(5)).toBe(true);
    expect(skillCastsOnAttack(1, 2)).toBe(true);
    expect(skillCastsOnAttack(2, 2)).toBe(false);
    expect(skillCastsOnAttack(3, 2)).toBe(true);
    expect(skillCastDamage(100, 10000)).toBe(100);
    expect(skillCastDamage(100, 15000)).toBe(150);

    const player = { attack: 100, defense: 0, hp: 5000, interval: 1 };
    const boss = { attack: 1, defense: 0, hp: 100000, interval: 5 };
    const limit = { timeLimitSeconds: 12, defenseConstant: 1 };
    const basic = hitDamage(100, 0, 1);

    const defaults = toCombatSkills(
      [{ skillSlug: "skill_a", runningSlot: "run_1" }],
      [{ slug: "skill_a", displayName: "测", castMode: "auto", enabled: true }],
      1,
    );
    expect(defaults[0]).toMatchObject({ castEveryAttacks: 4, damageMultBp: 10000 });
    const defaultFight = simulateBossFight(player, boss, limit, null, [], defaults);
    const defaultCasts = defaultFight.log.filter((event) => event.kind === "ult");
    expect(defaultCasts.map((event) => event.t)).toEqual([1, 5, 9]);
    expect(defaultCasts.every((event) => event.damage === basic)).toBe(true);

    const custom = toCombatSkills(
      [{ skillSlug: "skill_b", runningSlot: "run_1" }],
      [{ slug: "skill_b", displayName: "快斩", castMode: "auto", castEveryAttacks: 2, damageMultBp: 20000, enabled: true }],
      1,
    );
    expect(custom[0]).toMatchObject({ castEveryAttacks: 2, damageMultBp: 20000 });
    const customFight = simulateBossFight(player, boss, limit, null, [], custom);
    const customCasts = customFight.log.filter((event) => event.kind === "ult");
    expect(customCasts.map((event) => event.t)).toEqual([1, 3, 5, 7, 9, 11]);
    expect(customCasts.every((event) => event.damage === basic * 2)).toBe(true);
  });

  it("timeout and defeat are reported like simulateBattle", () => {
    const tank = { hp: 10_000_000, attack: 1, defense: 0, interval: 2 };
    expect(simulateBossFight(player, tank, { ...config, timeLimitSeconds: 30 }, ult, []).reason).toBe("timeout");
    const killer = { hp: 10_000_000, attack: 100000, defense: 0, interval: 1 };
    expect(simulateBossFight(player, killer, config, ult, []).reason).toBe("defeated");
  });
});
