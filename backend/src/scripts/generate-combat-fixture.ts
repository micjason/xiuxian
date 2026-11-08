/** Offline deterministic capture fixture. Not used for live simulation or rewards. */
import { writeFileSync } from "node:fs";
import { simulateBattle } from "../modules/combat/battle.js";
const player = { attack: 155, defense: 25, hp: 2200, interval: 1.0, critChanceBp: 2500, dodgeChanceBp: 1200, critMultBp: 17000 };
const monster = { id: "m_guard", name: "焚天火鸦", artKey: "boss_fire_crow", attack: 110, defense: 60, hp: 4800, interval: 1.4 };
let seed = 19;
const battle = simulateBattle(player, monster, { timeLimitSeconds: 45, defenseConstant: 1, random: () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; }, rage: { max: 100, onAttack: 25, onHit: 10, damageMultBp: 30000 } }, [
  { slug: "skill_liekong", name: "裂空斩", castMode: "auto", castEveryAttacks: 4, damageMultBp: 14000, fxType: "slash", effects: [{ kind: "attack_up", valueBp: 2000, durationSeconds: 3 }, { kind: "defense_down", valueBp: 3000, durationSeconds: 3 }] },
  { slug: "skill_tuna", name: "吐纳护体", castMode: "passive", castEveryAttacks: 4, damageMultBp: 5000, fxType: "heal_circle", effects: [{ kind: "heal", valueBp: 1000 }, { kind: "shield", valueBp: 1000, durationSeconds: 3 }] },
]);
writeFileSync(new URL("../../../game/fixtures/combat_timeline.json", import.meta.url), JSON.stringify({ combatId: "mock-combat", source: "fog", target: { source: "fog", mapId: "fog_wenxin_valley", objectId: "m_guard" }, battle, playback: { player, monster, timeLimitSeconds: 45, speeds: [1,2,3], canSkip: true } }, null, 2) + "\n");
