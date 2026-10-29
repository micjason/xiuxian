import type { SkillCastMode, SkillFx, SkillFxType } from "./skill-fx.js";

export type DefaultSkill = {
  slug: string;
  displayName: string;
  description: string;
  role: "heart" | "attack" | "body" | "step";
  rank: "yellow" | "xuan" | "earth" | "heaven";
  attack: number;
  defense: number;
  hp: number;
  cultivateBonusBp: number;
  fxType: SkillFxType;
  castMode: SkillCastMode;
  fx: SkillFx;
};

function fx(type: SkillFxType, primary: string, secondary: string): SkillFx {
  return { type, primary, secondary, scale: 1 };
}

/**
 * 默认可玩技能。fx_type 写资源真名（九套都覆盖）。
 * 释放只有自动 / 被动，没有手动，也没有大招。
 * 前三项的顺序被原型首领首通奖励按下标引用，不要调换。
 */
export const DEFAULT_SKILLS: DefaultSkill[] = [
  {
    slug: "skill_tuna",
    displayName: "吐纳诀",
    description: "调息回气，修炼时持续恢复。",
    role: "heart",
    rank: "yellow",
    attack: 0,
    defense: 0,
    hp: 0,
    cultivateBonusBp: 500,
    fxType: "heal_circle",
    castMode: "passive",
    fx: fx("heal_circle", "#5EE1C5", "#FFE27A"),
  },
  {
    slug: "skill_qingyuan",
    displayName: "青元诀",
    description: "青元流转，加快修炼。",
    role: "heart",
    rank: "xuan",
    attack: 0,
    defense: 0,
    hp: 0,
    cultivateBonusBp: 1500,
    fxType: "wind",
    castMode: "auto",
    fx: fx("wind", "#D8F5C8", "#5CB85C"),
  },
  {
    slug: "skill_zifu",
    displayName: "紫府金章",
    description: "紫府金光护持心神。",
    role: "heart",
    rank: "earth",
    attack: 0,
    defense: 0,
    hp: 0,
    cultivateBonusBp: 3000,
    fxType: "gold_light",
    castMode: "auto",
    fx: fx("gold_light", "#FFD45C", "#FFE9A0"),
  },
  {
    slug: "skill_liekong",
    displayName: "裂空斩",
    description: "近身斩击。",
    role: "attack",
    rank: "yellow",
    attack: 800,
    defense: 0,
    hp: 0,
    cultivateBonusBp: 0,
    fxType: "slash",
    castMode: "auto",
    fx: fx("slash", "#F5FBFF", "#A8E8E0"),
  },
  {
    slug: "skill_leiting",
    displayName: "雷霆诀",
    description: "落雷轰击。",
    role: "attack",
    rank: "yellow",
    attack: 800,
    defense: 0,
    hp: 0,
    cultivateBonusBp: 0,
    fxType: "thunder",
    castMode: "auto",
    fx: fx("thunder", "#E8D6FF", "#7B4DFF"),
  },
  {
    slug: "skill_chiyan",
    displayName: "赤炎掌",
    description: "掌心吐炎。",
    role: "attack",
    rank: "xuan",
    attack: 1000,
    defense: 0,
    hp: 0,
    cultivateBonusBp: 0,
    fxType: "fire",
    castMode: "auto",
    fx: fx("fire", "#FF9F43", "#E85D4C"),
  },
  {
    slug: "skill_hanbing",
    displayName: "寒冰刺",
    description: "冰晶刺击。",
    role: "attack",
    rank: "yellow",
    attack: 800,
    defense: 0,
    hp: 0,
    cultivateBonusBp: 0,
    fxType: "ice",
    castMode: "auto",
    fx: fx("ice", "#B9F3FF", "#3D8BFF"),
  },
  {
    slug: "skill_duwu",
    displayName: "毒雾术",
    description: "毒雾缠身。",
    role: "attack",
    rank: "yellow",
    attack: 600,
    defense: 0,
    hp: 0,
    cultivateBonusBp: 0,
    fxType: "poison",
    castMode: "auto",
    fx: fx("poison", "#7DDE6A", "#6B3FA0"),
  },
  {
    slug: "skill_huti",
    displayName: "护体罡气",
    description: "罡气护体，提高防御。",
    role: "body",
    rank: "yellow",
    attack: 0,
    defense: 800,
    hp: 0,
    cultivateBonusBp: 0,
    fxType: "shield",
    castMode: "passive",
    fx: fx("shield", "#FFF8EC", "#E8C872"),
  },
];
