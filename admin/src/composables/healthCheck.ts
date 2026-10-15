// 草稿体检：用现有的草稿接口数据，提前发现「发布后玩家会卡住」的问题。纯函数，便于测试。
export type Problem = { level: "error" | "warn"; area: string; message: string; to: string };

export type HealthInput = {
  realms: { requiredStageId?: string | null; code: number; displayName: string; majorName: string; tickSeconds: number; gainPerTick: number; interval: number | null }[];
  stages: {
    id: string;
    displayName: string;
    realmMissing?: boolean;
    powerProblem?: string | null;
    bosses: { name: string; hp: number; interval: number; drops: unknown[]; firstClear?: unknown[]; repeat?: unknown }[];
  }[];
  items: { id: string; displayName: string }[];
  skills: { id: string; displayName: string; categoryMissing?: boolean }[];
  rules: Record<string, number | null> | null;
  puppets?: { displayName: string; problem: string | null }[];
};

export function analyzeDraft(input: HealthInput): Problem[] {
  const problems: Problem[] = [];
  if (input.realms.length === 0) {
    problems.push({ level: "error", area: "境界", message: "还没有任何境界，玩家无法开始游戏。", to: "/config/realms" });
  }
  const sorted = [...input.realms].sort((a, b) => a.code - b.code);
  sorted.forEach((realm, index) => {
    const to = `/config/realms?open=${realm.code}`;
    if (!realm.displayName) {
      problems.push({ level: "error", area: "境界", message: `境界 ${realm.code} 没有名称。`, to });
    }
    if (index < sorted.length - 1 && (realm.tickSeconds <= 0 || realm.gainPerTick <= 0)) {
      problems.push({ level: "error", area: "境界", message: `「${realm.displayName || realm.code}」还没设置修炼间隔和每次获得修为，玩家得不到修为。`, to });
    }
    if (realm.interval == null) {
      problems.push({ level: "warn", area: "境界", message: `「${realm.displayName || realm.code}」没填基础出手间隔，战斗会算不出出手间隔。`, to });
    }
  });
  // 没有首领的关卡是正常的（只刷小怪、挂机）；只有被某个境界的「突破前要先通关」指到，才必须有首领。
  const gateStages = new Set(input.realms.map((realm) => realm.requiredStageId).filter((id): id is string => Boolean(id)));
  for (const stage of input.stages) {
    const to = `/config/stages?open=${stage.id}`;
    if (stage.realmMissing) {
      problems.push({ level: "error", area: "关卡", message: `关卡「${stage.displayName}」指向的境界不存在。`, to });
    }
    if (stage.bosses.length === 0 && gateStages.has(stage.id)) {
      problems.push({ level: "error", area: "关卡", message: `关卡「${stage.displayName}」是某个境界突破前要通关的关卡，但还没有首领，玩家永远通不了。`, to });
    }
    for (const boss of stage.bosses) {
      if (boss.hp <= 0 || boss.interval <= 0) {
        problems.push({ level: "error", area: "关卡", message: `首领「${boss.name || "未命名"}」的气血或出手间隔没填，玩家无法挑战。`, to });
      }
      const hasFirstClear = (boss.firstClear?.length ?? 0) > 0;
      const hasRepeat = Boolean(boss.repeat);
      if (boss.drops.length === 0 && !hasFirstClear && !hasRepeat) {
        problems.push({ level: "warn", area: "关卡", message: `首领「${boss.name || "未命名"}」没有任何掉落。`, to });
      }
    }
    if (stage.powerProblem) {
      problems.push({ level: "warn", area: "关卡", message: `关卡「${stage.displayName}」算不出推荐战力：${stage.powerProblem}`, to });
    }
  }
  for (const item of input.items) {
    if (!item.displayName) {
      problems.push({ level: "warn", area: "物品", message: `物品 ${item.id} 没有名称，玩家会看到「名称缺失」。`, to: `/config/items?open=${item.id}` });
    }
  }
  for (const skill of input.skills) {
    const to = `/config/skills?open=${skill.id}`;
    if (!skill.displayName) {
      problems.push({ level: "warn", area: "技能", message: `技能 ${skill.id} 没有名称。`, to });
    }
    if (skill.categoryMissing) {
      problems.push({ level: "warn", area: "技能", message: `技能「${skill.displayName}」的分类已不存在。`, to });
    }
  }
  if (input.rules) {
    const empty = Object.entries(input.rules).filter(([, value]) => value === null || value === undefined);
    if (empty.length > 0) {
      problems.push({ level: "error", area: "战斗参数", message: `战斗公式与参数还有 ${empty.length} 项没填，发布会被拒绝。`, to: "/config/combat" });
    }
  }
  for (const puppet of input.puppets ?? []) {
    if (puppet.problem) {
      problems.push({ level: "warn", area: "试炼人偶", message: `人偶「${puppet.displayName}」：${puppet.problem}`, to: "/config/combat?tab=sim" });
    }
  }
  return problems;
}
