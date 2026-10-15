// 生成“服务端 simulateBossFight 的标准答案”，给客户端 GUT 测试（test_boss_fight.gd）逐项对照。
// 用法：cd backend && npx tsx ../tools/sim/gen_boss_fixture.ts
import { writeFileSync } from "node:fs";
import { simulateBossFight } from "../../backend/src/modules/combat/battle.js";

const config = { timeLimitSeconds: 45, defenseConstant: 1 };
const ult = { multBp: 40000, cooldownSeconds: 20, firstCooldownSeconds: 8, autoCastWindowSeconds: 2 };
const cases = [
  { name: "炼气参考配置·全程自动", player: { attack: 63.4, defense: 23.7, hp: 547.3, interval: 1.5 }, boss: { attack: 34, defense: 19, hp: 1500, interval: 1.6 }, ult, taps: [] as number[] },
  { name: "炼气参考配置·冷却好立刻点", player: { attack: 63.4, defense: 23.7, hp: 547.3, interval: 1.5 }, boss: { attack: 34, defense: 19, hp: 1500, interval: 1.6 }, ult, taps: [8.25, 28.5, 48] },
  { name: "点太早无效 + 窗口内手动", player: { attack: 63.4, defense: 23.7, hp: 547.3, interval: 1.5 }, boss: { attack: 34, defense: 19, hp: 1500, interval: 1.6 }, ult, taps: [1, 2.5, 7.99, 9.5, 29.25] },
  { name: "打不过：被首领击败", player: { attack: 20, defense: 5, hp: 120, interval: 1.2 }, boss: { attack: 60, defense: 10, hp: 5000, interval: 1 }, ult, taps: [8.5] },
  { name: "超时", player: { attack: 5, defense: 40, hp: 9000, interval: 2 }, boss: { attack: 3, defense: 30, hp: 100000, interval: 2 }, ult, taps: [] },
  { name: "没有大招", player: { attack: 63.4, defense: 23.7, hp: 547.3, interval: 1.5 }, boss: { attack: 34, defense: 19, hp: 1500, interval: 1.6 }, ult: null, taps: [8.5] },
  { name: "筑基·大招倍率 5、冷却 18", player: { attack: 146.2, defense: 53.1, hp: 1209.9, interval: 1.4 }, boss: { attack: 80, defense: 40, hp: 4200, interval: 1.5 }, ult: { ...ult, multBp: 50000, cooldownSeconds: 18 }, taps: [8.4, 26.6] },
];
// 扫描首领气血：自动释放 vs 冷却一好就点（ready + 0.05）会在某些血量上差出一两次普攻，正好验证释放时刻的精确性。
for (let hp = 900; hp <= 1500; hp += 50) {
  const side = { player: { attack: 63.4, defense: 23.7, hp: 547.3, interval: 1.5 }, boss: { attack: 34, defense: 19, hp, interval: 1.6 }, ult };
  cases.push({ name: `扫描 hp ${hp}·自动`, ...side, taps: [] });
  cases.push({ name: `扫描 hp ${hp}·立刻点`, ...side, taps: [8.05, 28.1, 48.15] });
}
const out = cases.map((row) => {
  const result = simulateBossFight(row.player, row.boss, config, row.ult, row.taps);
  return {
    name: row.name,
    player: row.player,
    boss: row.boss,
    ult: row.ult,
    taps: row.taps,
    config,
    expect: {
      win: result.win,
      reason: result.reason,
      durationSeconds: result.durationSeconds,
      casts: result.ultCasts,
      eventCount: result.log.length,
      lastEvent: result.log[result.log.length - 1] ?? null,
    },
  };
});
writeFileSync(new URL("../../game/tests/fixtures/boss_fight_cases.json", import.meta.url), JSON.stringify(out, null, 1));
console.log(`wrote ${out.length} cases`);
