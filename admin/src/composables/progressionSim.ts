import { api, ApiError } from "../api";

export type ProgressionSimOverviewRow = {
  day: number;
  realmId: string;
  realmName: string;
  stageLabel: string;
  power: number;
  gearTier: string;
  skillTier: string;
  status: "ok" | "stuck";
};

export type ProgressionSimStuck = {
  bossId: string;
  bossName: string;
  day: number;
  playerPower: number;
  requiredPower: number;
  powerGap: number;
  redLights: Array<"power" | "gear" | "skill" | "stage">;
  hint: string;
};

export type ProgressionSimTimelineEvent = {
  day: number;
  hour: number;
  text: string;
  kind: "start" | "boss_win" | "boss_lose" | "idle" | "loot" | "equip" | "enhance" | "breakthrough" | "dongfu" | "other";
};

export type ProgressionSimResult = {
  overview: ProgressionSimOverviewRow[];
  stuck: ProgressionSimStuck | null;
  timeline: ProgressionSimTimelineEvent[];
  meta: { targetRealmId: string; elapsedMs: number; truncated: boolean };
};

export type ProgressionSimSource = "api" | "mock";

export type ProgressionSimRun = ProgressionSimResult & { source: ProgressionSimSource };

const RED_LIGHT_LABEL: Record<ProgressionSimStuck["redLights"][number], string> = {
  power: "战力",
  gear: "装备强化",
  skill: "技能",
  stage: "关卡门槛",
};

export function redLightLabel(key: ProgressionSimStuck["redLights"][number]): string {
  return RED_LIGHT_LABEL[key] ?? key;
}

export function timelineKindLabel(kind: ProgressionSimTimelineEvent["kind"]): string {
  switch (kind) {
    case "start":
      return "开局";
    case "boss_win":
      return "Boss 胜";
    case "boss_lose":
      return "Boss 败";
    case "idle":
      return "挂机";
    case "loot":
      return "掉落";
    case "equip":
      return "穿戴";
    case "enhance":
      return "强化";
    case "breakthrough":
      return "突破";
    case "dongfu":
      return "洞府";
    default:
      return "其它";
  }
}

/** Rich mock so the page is demoable before the server API lands. */
export function buildMockProgressionSim(targetRealmId = "dacheng-3"): ProgressionSimResult {
  const stuckDay = 10;
  return {
    overview: [
      {
        day: 1,
        realmId: "lianqi-1",
        realmName: "炼气一层",
        stageLabel: "黑风林/精英狼 · 推荐战力 730",
        power: 1_200,
        gearTier: "白装 · +0",
        skillTier: "基础心法",
        status: "ok",
      },
      {
        day: 3,
        realmId: "lianqi-3",
        realmName: "炼气三层",
        stageLabel: "黑风林/章末熊王 · 推荐战力 2100",
        power: 4_800,
        gearTier: "绿装 · +3",
        skillTier: "基础心法 Lv.2",
        status: "ok",
      },
      {
        day: 5,
        realmId: "zhuji-2",
        realmName: "筑基二层",
        stageLabel: "赤炎谷/精英火鸦 · 推荐战力 8500",
        power: 18_500,
        gearTier: "蓝装 · +6",
        skillTier: "攻击心法 Lv.3",
        status: "ok",
      },
      {
        day: 8,
        realmId: "jindan-1",
        realmName: "金丹一层",
        stageLabel: "幽冥谷/精英鬼修 · 推荐战力 42000",
        power: 62_000,
        gearTier: "紫装 · +9",
        skillTier: "攻防双修 Lv.4",
        status: "ok",
      },
      {
        day: stuckDay,
        realmId: "jindan-2",
        realmName: "金丹二层",
        stageLabel: "幽冥谷/章末鬼尊 · 推荐战力 96000",
        power: 78_000,
        gearTier: "紫装 · +10",
        skillTier: "攻防双修 Lv.4",
        status: "stuck",
      },
    ],
    stuck: {
      bossId: "boss_ghost_elder",
      bossName: "幽冥谷 · 章末鬼尊",
      day: stuckDay,
      playerPower: 78_000,
      requiredPower: 120_000,
      powerGap: 42_000,
      redLights: ["power", "gear", "skill"],
      hint: "建议优先提高该 Boss 前关卡掉落与强化上限，或下调鬼尊战力门槛。",
    },
    timeline: [
      { day: 1, hour: 0, text: "开局境界炼气一层，战力 1,200", kind: "start" },
      { day: 1, hour: 2, text: "打过精英狼，获得绿装武器，穿戴后战力 1,650", kind: "boss_win" },
      { day: 1, hour: 3, text: "挂机黑风林第 2 关", kind: "idle" },
      { day: 1, hour: 11, text: "洞府产出灵石 / 灵木，强化武器 +1，战力 1,820", kind: "dongfu" },
      { day: 2, hour: 4, text: "突破至炼气二层，战力 2,400", kind: "breakthrough" },
      { day: 3, hour: 6, text: "打过章末熊王，获得蓝装，穿戴后战力 4,800", kind: "boss_win" },
      { day: 3, hour: 8, text: "材料强化全身至 +3，战力 5,200", kind: "enhance" },
      { day: 5, hour: 1, text: "突破至筑基二层，战力 18,500", kind: "breakthrough" },
      { day: 5, hour: 5, text: "挂机赤炎谷，获得紫装碎片", kind: "loot" },
      { day: 8, hour: 2, text: "打过幽冥谷精英鬼修，战力 62,000", kind: "boss_win" },
      { day: 8, hour: 10, text: "穿戴紫装并强化至 +9，战力 71,000", kind: "equip" },
      { day: stuckDay, hour: 0, text: "挑战章末鬼尊：战力不足，失败（连续第 1 天）", kind: "boss_lose" },
      { day: stuckDay, hour: 4, text: "挂机幽冥谷最高可刷关，强化至 +10，战力 78,000", kind: "idle" },
      { day: stuckDay, hour: 12, text: "再次挑战章末鬼尊：仍失败（连续第 1 天汇总）", kind: "boss_lose" },
      { day: stuckDay + 1, hour: 2, text: "挑战章末鬼尊：失败（连续第 2 天）", kind: "boss_lose" },
      { day: stuckDay + 5, hour: 6, text: "挑战章末鬼尊：失败（连续第 6 天）", kind: "boss_lose" },
      { day: stuckDay + 9, hour: 8, text: "挑战章末鬼尊：连续 10 游戏天仍打不过，判定卡死停跑", kind: "boss_lose" },
    ],
    meta: {
      targetRealmId,
      elapsedMs: 42,
      truncated: false,
    },
  };
}

function shouldFallback(error: unknown): boolean {
  if (error instanceof ApiError) {
    return error.status === 404 || error.status === 501 || error.status === 502 || error.status === 503;
  }
  // network / parse / unexpected
  return true;
}

/**
 * Call live progression sim. Falls back to mock when the API is not ready
 * (404/501/network) so the admin page stays demoable.
 */
export async function runProgressionSim(targetRealmId?: string): Promise<ProgressionSimRun> {
  const body: { targetRealmId?: string } = {};
  if (targetRealmId) {
    body.targetRealmId = targetRealmId;
  }
  try {
    const result = await api<ProgressionSimResult>("/admin/sim/progression", {
      method: "POST",
      body: JSON.stringify(body),
    });
    return { ...result, source: "api" };
  } catch (error) {
    if (!shouldFallback(error)) {
      throw error;
    }
    const mock = buildMockProgressionSim(targetRealmId || "dacheng-3");
    return { ...mock, source: "mock" };
  }
}
