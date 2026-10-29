import { randomBytes } from "node:crypto";
import { eq } from "drizzle-orm";
import { contentItems, contentRealms, contentSkills, contentTrialPuppets } from "../../db/schema.js";
import { ratePower } from "../combat/stats.js";
import { AppError } from "../../shared/errors.js";
import { describeBuild, type PowerDetail } from "./puppet-build.js";
import { readGameRules } from "./rules.js";
import type { Db } from "../operations/record.js";
import { combatStats } from "../loop/actions.js";
import type { ContentSnapshot } from "./validate.js";
import { loadDraftSnapshot } from "./snapshot.js";

export type PuppetKind = "configured" | "manual";

export type PuppetInput = {
  displayName?: string;
  kind?: string;
  realmCode?: number;
  weaponIds?: string[];
  skillIds?: string[];
  attack?: number;
  defense?: number;
  hp?: number;
  speed?: number;
  interval?: number;
};

export type PuppetView = {
  id: string;
  displayName: string;
  kind: PuppetKind;
  kindName: string;
  realmCode: number | null;
  realmName: string;
  realmMissing: boolean;
  weapons: { id: string; displayName: string; missing: boolean }[];
  skills: { id: string; displayName: string; missing: boolean }[];
  attack: number | null;
  defense: number | null;
  hp: number | null;
  speed: number | null;
  interval: number | null;
  power: number | null;
  powerDetail: PowerDetail | null;
  tendency: string | null;
  tendencyNote: string | null;
  problem: string | null;
};

const missingGear = "有武器或技能已经删除，先改这个人偶";
const noBuild = { powerDetail: null, tendency: null, tendencyNote: null };

function buildOf(
  stats: { attack: number; defense: number; hp: number; speed: number },
  weights: { attack: number; defense: number; hp: number; speed: number },
) {
  const described = describeBuild(stats, weights);
  return {
    powerDetail: { lines: described.lines, total: described.total, power: described.power, shares: described.shares },
    tendency: described.tendency,
    tendencyNote: described.note,
  };
}

function newId(): string {
  return `p${randomBytes(8).toString("hex")}`;
}

function textOf(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function numberOf(value: unknown, label: string): number {
  if (value === undefined || value === null || value === "") {
    throw new AppError("INVALID_INPUT", `请填写${label}`);
  }
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) {
    throw new AppError("INVALID_INPUT", `${label}不能小于 0`);
  }
  return number;
}

function kindName(kind: PuppetKind): string {
  return kind === "configured" ? "按配置算" : "手填属性";
}

function secondsText(value: number): string {
  return String(Math.round(value * 1000) / 1000);
}

function idList(value: unknown, label: string): string[] {
  if (value == null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new AppError("INVALID_INPUT", `${label}要按列表选择`);
  }
  const ids = value.map((item) => textOf(item));
  if (ids.some((item) => !item)) {
    throw new AppError("INVALID_INPUT", `有${label}没选`);
  }
  if (new Set(ids).size !== ids.length) {
    throw new AppError("INVALID_INPUT", `${label}不能重复`);
  }
  return ids;
}

function rulesOf(world: ContentSnapshot) {
  return readGameRules(world);
}

function blankView(row: typeof contentTrialPuppets.$inferSelect, kind: PuppetKind, problem: string): PuppetView {
  return {
    id: row.slug,
    displayName: row.displayName,
    kind,
    kindName: kindName(kind),
    realmCode: row.realmCode,
    realmName: "",
    realmMissing: kind === "configured" && row.realmCode != null,
    weapons: (row.weaponIds ?? []).map((id) => ({ id, displayName: "已删除", missing: true })),
    skills: (row.skillIds ?? []).map((id) => ({ id, displayName: "已删除", missing: true })),
    attack: null,
    defense: null,
    hp: null,
    speed: null,
    interval: null,
    power: null,
    ...noBuild,
    problem,
  };
}

export function presentPuppet(row: typeof contentTrialPuppets.$inferSelect, world: ContentSnapshot): PuppetView {
  if (row.kind !== "configured" && row.kind !== "manual") {
    return blankView(row, "configured", "人偶类型不能识别");
  }
  if (row.kind === "manual") {
    let rules: ReturnType<typeof rulesOf>;
    try {
      rules = rulesOf(world);
    } catch (error) {
      if (!(error instanceof AppError)) {
        throw error;
      }
      return {
        id: row.slug,
        displayName: row.displayName,
        kind: "manual",
        kindName: kindName("manual"),
        realmCode: null,
        realmName: "",
        realmMissing: false,
        weapons: [],
        skills: [],
        attack: row.attack,
        defense: row.defense,
        hp: row.hp,
        speed: row.speed,
        interval: row.interval,
        power: null,
        ...noBuild,
        problem: error.message,
      };
    }
    const minInterval = rules.minInterval;
    let problem: string | null = null;
    if (row.hp == null || row.hp <= 0) {
      problem = "气血必须大于 0";
    } else if (row.interval == null || row.interval <= 0) {
      problem = "出手间隔必须大于 0";
    } else if (row.interval < minInterval) {
      problem = `出手间隔不能小于 ${secondsText(minInterval)} 秒`;
    } else if (row.attack == null || row.defense == null || row.speed == null) {
      problem = "请补全属性";
    }
    const weights = rules.powerWeights;
    return {
      id: row.slug,
      displayName: row.displayName,
      kind: "manual",
      kindName: kindName("manual"),
      realmCode: null,
      realmName: "",
      realmMissing: false,
      weapons: [],
      skills: [],
      attack: row.attack,
      defense: row.defense,
      hp: row.hp,
      speed: row.speed,
      interval: row.interval,
      power:
        problem || row.attack == null || row.defense == null || row.hp == null || row.speed == null
          ? null
          : ratePower({ attack: row.attack, defense: row.defense, hp: row.hp, speed: row.speed }, weights),
      ...(problem || row.attack == null || row.defense == null || row.hp == null || row.speed == null
        ? noBuild
        : buildOf({ attack: row.attack, defense: row.defense, hp: row.hp, speed: row.speed }, weights)),
      problem,
    };
  }
  const realm = world.realms.find((item) => item.sortOrder === row.realmCode);
  if (!realm?.slug) {
    const view = blankView(row, "configured", "境界已经不存在");
    view.realmMissing = true;
    return view;
  }
  const weapons = (row.weaponIds ?? []).map((id) => {
    const item = world.items.find((candidate) => candidate.slug === id && candidate.kind === "equipment");
    return { id, displayName: item?.displayName || "已删除", missing: !item };
  });
  const skills = (row.skillIds ?? []).map((id) => {
    const skill = world.skills.find((candidate) => candidate.slug === id);
    return { id, displayName: skill?.displayName || "已删除", missing: !skill };
  });
  if (weapons.some((item) => item.missing) || skills.some((item) => item.missing)) {
    return {
      ...blankView(row, "configured", missingGear),
      realmCode: row.realmCode ?? null,
      realmName: realm.displayName ?? "",
      realmMissing: false,
      weapons,
      skills,
    };
  }
  let stats: ReturnType<typeof combatStats>;
  try {
    stats = combatStats(world, realm.slug, weapons.map((item) => item.id), skills.map((item) => item.id));
  } catch (error) {
    if (!(error instanceof AppError)) {
      throw error;
    }
    return {
      id: row.slug,
      displayName: row.displayName,
      kind: "configured",
      kindName: kindName("configured"),
      realmCode: row.realmCode ?? null,
      realmName: realm.displayName ?? "",
      realmMissing: false,
      weapons,
      skills,
      attack: null,
      defense: null,
      hp: null,
      speed: null,
      interval: null,
      power: null,
      ...noBuild,
      problem: error.message,
    };
  }
  let rules: ReturnType<typeof rulesOf>;
  try {
    rules = rulesOf(world);
  } catch (error) {
    if (!(error instanceof AppError)) {
      throw error;
    }
    return {
      id: row.slug,
      displayName: row.displayName,
      kind: "configured",
      kindName: kindName("configured"),
      realmCode: row.realmCode ?? null,
      realmName: realm.displayName ?? "",
      realmMissing: false,
      weapons,
      skills,
      attack: stats.attack,
      defense: stats.defense,
      hp: stats.hp,
      speed: stats.speed,
      interval: stats.interval,
      power: null,
      ...noBuild,
      problem: error.message,
    };
  }
  return {
    id: row.slug,
    displayName: row.displayName,
    kind: "configured",
    kindName: kindName("configured"),
    realmCode: row.realmCode ?? null,
    realmName: realm.displayName ?? "",
    realmMissing: false,
    weapons,
    skills,
    attack: stats.attack,
    defense: stats.defense,
    hp: stats.hp,
    speed: stats.speed,
    interval: stats.interval,
    power: stats.power,
    ...buildOf(stats, rules.powerWeights),
    problem: null,
  };
}

async function storedValues(db: Db, input: PuppetInput, kind: PuppetKind, adminId: string | null) {
  const displayName = textOf(input.displayName);
  if (!displayName) {
    throw new AppError("INVALID_INPUT", "请填写名称");
  }
  const base = { displayName, kind, updatedAt: new Date(), updatedBy: adminId };
  if (kind === "manual") {
    const world = await loadDraftSnapshot(db);
    const minInterval = rulesOf(world).minInterval;
    const attack = numberOf(input.attack, "攻击");
    const defense = numberOf(input.defense, "防御");
    const hp = numberOf(input.hp, "气血");
    const speed = numberOf(input.speed, "速度");
    const interval = numberOf(input.interval, "出手间隔");
    if (hp <= 0) {
      throw new AppError("INVALID_INPUT", "气血必须大于 0");
    }
    if (interval <= 0) {
      throw new AppError("INVALID_INPUT", "出手间隔必须大于 0");
    }
    if (interval < minInterval) {
      throw new AppError("INVALID_INPUT", `出手间隔不能小于 ${secondsText(minInterval)} 秒`);
    }
    return {
      ...base,
      realmCode: null,
      weaponIds: [],
      skillIds: [],
      attack,
      defense,
      hp,
      speed,
      interval,
    };
  }
  const realmCode = Number(input.realmCode);
  if (!Number.isInteger(realmCode) || realmCode < 1) {
    throw new AppError("INVALID_INPUT", "请选择境界");
  }
  const [realm] = await db.select().from(contentRealms).where(eq(contentRealms.sortOrder, realmCode)).limit(1);
  if (!realm) {
    throw new AppError("INVALID_INPUT", "境界不存在");
  }
  const weaponIds = idList(input.weaponIds, "武器");
  const skillIds = idList(input.skillIds, "技能");
  const items = await db.select().from(contentItems);
  if (weaponIds.some((id) => !items.some((item) => item.slug === id && item.kind === "equipment"))) {
    throw new AppError("INVALID_INPUT", "武器不存在");
  }
  const skills = await db.select().from(contentSkills);
  if (skillIds.some((id) => !skills.some((skill) => skill.slug === id))) {
    throw new AppError("INVALID_INPUT", "技能不存在");
  }
  return {
    ...base,
    realmCode,
    weaponIds,
    skillIds,
    attack: null,
    defense: null,
    hp: null,
    speed: null,
    interval: null,
  };
}

function requireKind(value: unknown): PuppetKind {
  if (value === "configured" || value === "manual") {
    return value;
  }
  throw new AppError("INVALID_INPUT", "请选择人偶类型");
}

async function assertNameFree(db: Db, displayName: string, currentId?: string) {
  const rows = await db.select().from(contentTrialPuppets);
  if (rows.some((row) => row.displayName === displayName && row.slug !== currentId)) {
    throw new AppError("INVALID_INPUT", "名称不能重复");
  }
}

export async function listTrialPuppets(db: Db): Promise<PuppetView[]> {
  const [rows, world] = await Promise.all([db.select().from(contentTrialPuppets), loadDraftSnapshot(db)]);
  return rows
    .map((row) => presentPuppet(row, world))
    .sort((left, right) => left.displayName.localeCompare(right.displayName, "zh"));
}

export async function createTrialPuppet(db: Db, input: PuppetInput, adminId: string | null) {
  const kind = requireKind(input.kind);
  const values = await storedValues(db, input, kind, adminId);
  await assertNameFree(db, values.displayName);
  const slug = newId();
  await db.insert(contentTrialPuppets).values({ ...values, slug });
  return { id: slug };
}

export async function updateTrialPuppet(db: Db, id: string, input: PuppetInput, adminId: string | null) {
  const [current] = await db.select().from(contentTrialPuppets).where(eq(contentTrialPuppets.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个人偶");
  }
  if (input.kind != null && input.kind !== "" && input.kind !== current.kind) {
    throw new AppError("INVALID_INPUT", "人偶类型不能改");
  }
  const kind = requireKind(current.kind);
  const values = await storedValues(db, input, kind, adminId);
  await assertNameFree(db, values.displayName, id);
  await db.update(contentTrialPuppets).set(values).where(eq(contentTrialPuppets.slug, id));
  return { id };
}

export async function deleteTrialPuppet(db: Db, id: string) {
  const [current] = await db.select().from(contentTrialPuppets).where(eq(contentTrialPuppets.slug, id)).limit(1);
  if (!current) {
    throw new AppError("NOT_FOUND", "没有这个人偶");
  }
  await db.delete(contentTrialPuppets).where(eq(contentTrialPuppets.slug, id));
  return { ok: true };
}
