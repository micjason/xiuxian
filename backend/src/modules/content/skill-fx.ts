/** 技能表现类型。seed / 后台写资源真名；客户端缺资源时才降级，不在这里改写。 */
export const SKILL_FX_TYPES = ["slash", "thunder", "fire", "heal_circle", "ice", "wind", "poison", "gold_light", "shield"] as const;
export type SkillFxType = (typeof SKILL_FX_TYPES)[number];

/** 玩家侧只自动或被动。不提供手动释放 / 大招入口。 */
export const SKILL_CAST_MODES = ["auto", "passive"] as const;
export type SkillCastMode = (typeof SKILL_CAST_MODES)[number];

export type SkillFx = {
  type: SkillFxType;
  primary?: string;
  secondary?: string;
  scale?: number;
};

/** 客户端缺对应资源时的安全网。seed 不使用这张表。 */
export const FX_FALLBACK: Partial<Record<SkillFxType, SkillFxType>> = {
  ice: "thunder",
  wind: "slash",
  poison: "fire",
  gold_light: "slash",
  shield: "heal_circle",
};

/** 旧名兼容。配置和 seed 仍写 gold_light。 */
export const FX_ALIAS: Record<string, SkillFxType> = {
  gold: "gold_light",
  holy: "gold_light",
};

/** 图标文件与 fx_type 同名。skill_* 只是旧文件名别名。 */
export const SKILL_ICON_KEY: Record<SkillFxType, string> = {
  slash: "slash",
  thunder: "thunder",
  fire: "fire",
  heal_circle: "heal_circle",
  ice: "ice",
  wind: "wind",
  poison: "poison",
  gold_light: "gold_light",
  shield: "shield",
};

const HEX = /^#[0-9A-Fa-f]{6}$/;

export function isSkillFxType(value: string): value is SkillFxType {
  return (SKILL_FX_TYPES as readonly string[]).includes(value);
}

export function canonicalFxType(value: string): SkillFxType | null {
  if (isSkillFxType(value)) {
    return value;
  }
  return FX_ALIAS[value] ?? null;
}

/**
 * 仅当 available 里没有该资源时才降级。available 为空表示一套都没有，最后落到 slash。
 * 不改库存的 fx_type。
 */
export function resolveFxType(raw: string, available: readonly string[]): SkillFxType {
  const type = canonicalFxType(raw) ?? "slash";
  if (available.includes(type)) {
    return type;
  }
  const mapped = FX_FALLBACK[type] ?? "slash";
  if (available.includes(mapped)) {
    return mapped;
  }
  return "slash";
}

export function castModeProblem(value: string): string | null {
  if ((SKILL_CAST_MODES as readonly string[]).includes(value)) {
    return null;
  }
  return "释放方式只能是自动或被动";
}

export function skillFxProblem(value: unknown, fxType: string | null): string | null {
  let raw = value;
  if (typeof value === "string") {
    const text = value.trim();
    if (!text) {
      return null;
    }
    try {
      raw = JSON.parse(text) as unknown;
    } catch {
      return "表现参数要是 JSON";
    }
  }
  if (raw == null) {
    return null;
  }
  if (typeof raw !== "object" || Array.isArray(raw)) {
    return "表现参数格式不正确";
  }
  const record = raw as Record<string, unknown>;
  const declared = record.type == null || record.type === "" ? null : String(record.type);
  if (declared != null && !isSkillFxType(declared)) {
    return "表现参数的 type 不正确";
  }
  if (fxType && !isSkillFxType(fxType)) {
    return "表现类型不正确";
  }
  if (declared && fxType && declared !== fxType) {
    return "表现参数的 type 要和表现类型一致";
  }
  if (!declared && !fxType) {
    return "表现参数要写 type";
  }
  for (const key of ["primary", "secondary"] as const) {
    if (record[key] == null || record[key] === "") {
      continue;
    }
    if (typeof record[key] !== "string" || !HEX.test(record[key])) {
      return "表现颜色要是 #RRGGBB";
    }
  }
  if (record.scale != null && record.scale !== "") {
    const scale = Number(record.scale);
    if (!Number.isFinite(scale) || scale < 0.25 || scale > 4) {
      return "表现缩放要在 0.25 到 4 之间";
    }
  }
  return null;
}

export function normalizeSkillFx(value: unknown, fxType: SkillFxType | null): SkillFx | null {
  if (skillFxProblem(value, fxType)) {
    return null;
  }
  let raw = value;
  if (typeof value === "string") {
    const text = value.trim();
    if (!text) {
      return null;
    }
    raw = JSON.parse(text) as unknown;
  }
  if (raw == null) {
    return null;
  }
  const record = raw as Record<string, unknown>;
  const type = (record.type == null || record.type === "" ? fxType : String(record.type)) as SkillFxType;
  const fx: SkillFx = { type };
  if (typeof record.primary === "string" && record.primary) {
    fx.primary = record.primary;
  }
  if (typeof record.secondary === "string" && record.secondary) {
    fx.secondary = record.secondary;
  }
  if (record.scale != null && record.scale !== "") {
    fx.scale = Number(record.scale);
  }
  return fx;
}
