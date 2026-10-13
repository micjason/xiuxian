import { hitDamage } from "../combat/battle.js";
import { computePower, ratePower } from "../combat/stats.js";

type Weights = { attack: number; defense: number; hp: number; speed: number };

export function formulaExamples(input: { defenseConstant: number; speedBase: number; minInterval: number; weights: Weights }) {
  const standard = { attack: 100, defense: 100, hp: 333, speed: 20 };
  const item = { attack: 10, defense: 0, hp: 0, speed: 0 };
  const naked = { attack: 10, defense: 10, hp: 33, speed: 0 };
  const geared = { attack: 40, defense: 30, hp: 120, speed: 8 };
  const add = (left: typeof naked, right: typeof item) => ({
    attack: left.attack + right.attack,
    defense: left.defense + right.defense,
    hp: left.hp + right.hp,
    speed: left.speed + right.speed,
  });
  const nakedPower = ratePower(naked, input.weights);
  const gearedPower = ratePower(geared, input.weights);
  return {
    defenseConstant: input.defenseConstant,
    weights: input.weights,
    evenDamage: hitDamage(100, 100, input.defenseConstant),
    doubledDamage: hitDamage(200, 200, input.defenseConstant),
    standard,
    standardPower: ratePower(standard, input.weights),
    item,
    nakedPower,
    nakedWithItemPower: ratePower(add(naked, item), input.weights),
    gearedPower,
    gearedWithItemPower: ratePower(add(geared, item), input.weights),
    nakedDelta: ratePower(add(naked, item), input.weights) - nakedPower,
    gearedDelta: ratePower(add(geared, item), input.weights) - gearedPower,
    intervalSeconds: computePower({
      ...standard,
      baseInterval: 1.5,
      minInterval: input.minInterval,
      speedBase: input.speedBase,
      weights: input.weights,
    }).interval,
  };
}
