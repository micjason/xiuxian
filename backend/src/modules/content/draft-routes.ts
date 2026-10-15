import type { FastifyInstance } from "fastify";
import { eq } from "drizzle-orm";
import { contentRealms } from "../../db/schema.js";
import type { Db } from "../operations/record.js";
import { AppError } from "../../shared/errors.js";
import { saveDraftDropTable } from "./draft-service.js";
import { readRules, readGameRules, rulesForSave, rulesFromInput, saveRules } from "./rules.js";
import { formulaExamples } from "./formula-examples.js";
import { buildFormulaPreview } from "./formula-preview.js";
import { loadDraftSnapshot } from "./snapshot.js";
import { readEnhanceView, saveEnhanceRules } from "./enhance.js";
import { listGear, removeMajorGear, saveGearQualityFactors, syncGear, updateGearPiece } from "./gear.js";
import {
  createOpsItem,
  createOpsSkill,
  createOpsStage,
  createSkillCategory,
  deleteOpsItem,
  deleteOpsSkill,
  deleteOpsStage,
  deleteSkillCategory,
  listOpsItems,
  listOpsSkills,
  listOpsStages,
  listSkillCategories,
  updateOpsItem,
  updateOpsSkill,
  updateOpsStage,
  updateSkillCategory,
} from "./ops-content.js";
import { publishSnapshot } from "./snapshot.js";
import { duelTrialPuppets } from "./puppet-duel.js";
import { createTrialPuppet, deleteTrialPuppet, listTrialPuppets, updateTrialPuppet } from "./puppets.js";
import { runTrial, type TrialInput } from "./trial.js";
import { diffContent, listContentVersions } from "./versions.js";

function requiredPositive(value: unknown, label: string): number {
  if (value === undefined || value === null || value === "") {
    throw new AppError("INVALID_INPUT", `请填写${label}`);
  }
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) {
    throw new AppError("INVALID_INPUT", `${label}必须大于 0`);
  }
  return number;
}

function statNumber(value: unknown, label: string, fallback: number): number {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0) {
    throw new AppError("INVALID_INPUT", `${label}不能小于 0`);
  }
  return number;
}

function realmCode(value: unknown): number {
  const code = Number(value);
  if (!Number.isInteger(code) || code < 1) {
    throw new AppError("INVALID_INPUT", "编号必须是大于 0 的整数");
  }
  return code;
}

async function assertCodeAvailable(db: Db, code: number, currentSlug?: string) {
  const rows = await db.select().from(contentRealms);
  if (rows.some((row) => row.sortOrder === code && row.slug !== currentSlug)) {
    throw new AppError("INVALID_INPUT", "编号不能重复");
  }
}

export async function registerDraftRoutes(app: FastifyInstance, deps: { db: Db; now: () => Date }): Promise<void> {
  app.get("/admin/draft/realms", async () => {
    const rows = await deps.db.select().from(contentRealms);
    return rows
      .sort((left, right) => left.sortOrder - right.sortOrder)
      .map((row) => ({
        code: row.sortOrder,
        displayName: row.displayName,
        majorName: row.majorName,
        tickSeconds: row.tickSeconds,
        gainPerTick: row.gainPerTick,
        breakthroughCost: row.breakthroughCost,
        attack: row.baseAttack,
        defense: row.baseDefense,
        hp: row.baseHp,
        speed: row.baseSpeed,
        interval: row.baseInterval,
      }));
  });

  app.post("/admin/draft/realms", async (request) => {
    const body = request.body as {
      code?: number;
      displayName?: string;
      majorName?: string;
      tickSeconds?: number;
      gainPerTick?: number;
      breakthroughCost?: number;
      attack?: number;
      defense?: number;
      hp?: number;
      speed?: number;
      interval?: number;
    };
    const code = realmCode(body.code);
    if (!body.displayName?.trim()) {
      throw new AppError("INVALID_INPUT", "请填写境界名称");
    }
    await assertCodeAvailable(deps.db, code);
    await deps.db.insert(contentRealms).values({
      slug: String(code),
      displayName: body.displayName.trim(),
      majorName: body.majorName?.trim() ?? "",
      sortOrder: code,
      nextRealmSlug: null,
      tickSeconds: body.tickSeconds ?? 0,
      gainPerTick: body.gainPerTick ?? 0,
      breakthroughCost: body.breakthroughCost ?? 0,
      baseAttack: statNumber(body.attack, "攻击", 0),
      baseDefense: statNumber(body.defense, "防御", 0),
      baseHp: statNumber(body.hp, "气血", 0),
      baseSpeed: statNumber(body.speed, "速度", 0),
      baseInterval: requiredPositive(body.interval, "基础出手间隔"),
      updatedAt: deps.now(),
      updatedBy: request.actor?.actorId ?? null,
    });
    if (body.majorName?.trim()) {
      await syncGear(deps.db, request.actor?.actorId ?? null);
    }
    return { ok: true };
  });

  app.put("/admin/draft/realms/:code", async (request) => {
    const currentCode = realmCode((request.params as { code: string }).code);
    const body = request.body as {
      code?: number;
      displayName?: string;
      majorName?: string;
      tickSeconds?: number;
      gainPerTick?: number;
      breakthroughCost?: number;
      attack?: number;
      defense?: number;
      hp?: number;
      speed?: number;
      interval?: number;
    };
    const nextCode = realmCode(body.code ?? currentCode);
    const [current] = await deps.db.select().from(contentRealms).where(eq(contentRealms.sortOrder, currentCode)).limit(1);
    if (!current) {
      throw new AppError("NOT_FOUND", "没有这个境界");
    }
    if (!body.displayName?.trim()) {
      throw new AppError("INVALID_INPUT", "请填写境界名称");
    }
    const tickSeconds = body.tickSeconds ?? current.tickSeconds;
    const gainPerTick = body.gainPerTick ?? current.gainPerTick;
    const breakthroughCost = body.breakthroughCost ?? current.breakthroughCost;
    const attack = statNumber(body.attack, "攻击", current.baseAttack);
    const defense = statNumber(body.defense, "防御", current.baseDefense);
    const hp = statNumber(body.hp, "气血", current.baseHp);
    const speed = statNumber(body.speed, "速度", current.baseSpeed);
    const interval = requiredPositive(body.interval, "基础出手间隔");
    if (tickSeconds < 0 || gainPerTick < 0 || breakthroughCost < 0) {
      throw new AppError("INVALID_INPUT", "秒数、修为和突破消耗不能小于 0");
    }
    await assertCodeAvailable(deps.db, nextCode, current.slug);
    const majorName = body.majorName === undefined ? current.majorName : body.majorName.trim();
    const previousMajor = current.majorName.trim();
    const siblings = await deps.db.select().from(contentRealms);
    const leavingMajor =
      previousMajor !== "" &&
      previousMajor !== majorName &&
      !siblings.some((realm) => realm.slug !== current.slug && realm.majorName.trim() === previousMajor);
    if (leavingMajor && current.majorKey) {
      await removeMajorGear(deps.db, current.majorKey);
    }
    await deps.db
      .update(contentRealms)
      .set({
        slug: String(nextCode),
        displayName: body.displayName.trim(),
        majorName,
        sortOrder: nextCode,
        nextRealmSlug: null,
        tickSeconds,
        gainPerTick,
        breakthroughCost,
        baseAttack: attack,
        baseDefense: defense,
        baseHp: hp,
        baseSpeed: speed,
        baseInterval: interval,
        updatedAt: deps.now(),
        updatedBy: request.actor?.actorId ?? null,
      })
      .where(eq(contentRealms.slug, current.slug));
    const realms = await deps.db.select().from(contentRealms);
    if (realms.some((realm) => realm.majorName.trim())) {
      await syncGear(deps.db, request.actor?.actorId ?? null);
    }
    return { ok: true };
  });

  app.delete("/admin/draft/realms/:code", async (request) => {
    const code = realmCode((request.params as { code: string }).code);
    const [current] = await deps.db.select().from(contentRealms).where(eq(contentRealms.sortOrder, code)).limit(1);
    if (!current) {
      throw new AppError("NOT_FOUND", "没有这个境界");
    }
    const siblings = await deps.db.select().from(contentRealms);
    const majorName = current.majorName.trim();
    const lastOfMajor = majorName !== "" && !siblings.some((realm) => realm.slug !== current.slug && realm.majorName.trim() === majorName);
    if (lastOfMajor && current.majorKey) {
      await removeMajorGear(deps.db, current.majorKey);
    }
    await deps.db.delete(contentRealms).where(eq(contentRealms.slug, current.slug));
    const realms = await deps.db.select().from(contentRealms);
    if (realms.some((realm) => realm.majorName.trim())) {
      await syncGear(deps.db, request.actor?.actorId ?? null);
    }
    return { ok: true };
  });

  app.get("/admin/draft/rules", async () => readRules(deps.db));
  app.put("/admin/draft/rules", async (request) =>
    saveRules(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.post("/admin/draft/formula-preview", async (request) => {
    const rules = rulesFromInput(
      rulesForSave(request.body as Parameters<typeof rulesFromInput>[0], {
        offlineCapSeconds: 36000,
        bagCapacity: 20,
        combat: { challengeCooldownSeconds: 0, timeLimitSeconds: 20, recommendedPowerMargin: 1.05 },
      }),
    );
    return buildFormulaPreview(rules);
  });
  app.get("/admin/draft/formula-examples", async () => {
    const world = await loadDraftSnapshot(deps.db);
    const rules = readGameRules(world);
    return formulaExamples({
      defenseConstant: rules.defenseConstant,
      speedBase: rules.speedBase,
      minInterval: rules.minInterval,
      weights: rules.powerWeights,
    });
  });
  app.get("/admin/draft/items", async () => listOpsItems(deps.db));
  app.post("/admin/draft/items", async (request) =>
    createOpsItem(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.put("/admin/draft/items/:id", async (request) =>
    updateOpsItem(deps.db, (request.params as { id: string }).id, request.body as never, request.actor?.actorId ?? null),
  );
  app.delete("/admin/draft/items/:id", async (request) => deleteOpsItem(deps.db, (request.params as { id: string }).id));
  app.get("/admin/draft/skills", async () => listOpsSkills(deps.db));
  app.post("/admin/draft/skills", async (request) =>
    createOpsSkill(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.put("/admin/draft/skills/:id", async (request) =>
    updateOpsSkill(deps.db, (request.params as { id: string }).id, request.body as never, request.actor?.actorId ?? null),
  );
  app.delete("/admin/draft/skills/:id", async (request) => deleteOpsSkill(deps.db, (request.params as { id: string }).id));
  app.get("/admin/draft/enhance", async () => readEnhanceView(deps.db));
  app.put("/admin/draft/enhance", async (request) => saveEnhanceRules(deps.db, request.body, request.actor?.actorId ?? null));
  app.get("/admin/draft/gear", async () => listGear(deps.db));
  app.put("/admin/draft/gear-qualities", async (request) =>
    saveGearQualityFactors(deps.db, request.body as Record<string, unknown>, request.actor?.actorId ?? null),
  );
  app.put("/admin/draft/gear/:id", async (request) =>
    updateGearPiece(
      deps.db,
      (request.params as { id: string }).id,
      request.body as { displayName?: string; description?: string; iconKey?: string },
      request.actor?.actorId ?? null,
    ),
  );
  app.get("/admin/draft/skill-categories", async () => listSkillCategories(deps.db));
  app.post("/admin/draft/skill-categories", async (request) =>
    createSkillCategory(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.put("/admin/draft/skill-categories/:id", async (request) =>
    updateSkillCategory(deps.db, (request.params as { id: string }).id, request.body as never, request.actor?.actorId ?? null),
  );
  app.delete("/admin/draft/skill-categories/:id", async (request) =>
    deleteSkillCategory(deps.db, (request.params as { id: string }).id),
  );
  app.get("/admin/draft/stages", async () => listOpsStages(deps.db));
  app.post("/admin/draft/stages", async (request) =>
    createOpsStage(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.put("/admin/draft/stages/:id", async (request) =>
    updateOpsStage(deps.db, (request.params as { id: string }).id, request.body as never, request.actor?.actorId ?? null),
  );
  app.delete("/admin/draft/stages/:id", async (request) => deleteOpsStage(deps.db, (request.params as { id: string }).id));
  app.get("/admin/draft/puppets", async () => listTrialPuppets(deps.db));
  app.post("/admin/draft/puppets/duels", async (request) =>
    duelTrialPuppets(deps.db, (request.body as { ids?: unknown; times?: unknown }).ids, (request.body as { times?: unknown }).times),
  );
  app.post("/admin/draft/puppets", async (request) =>
    createTrialPuppet(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.put("/admin/draft/puppets/:id", async (request) =>
    updateTrialPuppet(deps.db, (request.params as { id: string }).id, request.body as never, request.actor?.actorId ?? null),
  );
  app.delete("/admin/draft/puppets/:id", async (request) =>
    deleteTrialPuppet(deps.db, (request.params as { id: string }).id),
  );
  app.post("/admin/draft/trial", async (request) => runTrial(deps.db, request.body as TrialInput));
  app.post("/admin/draft/drop-tables", async (request) =>
    saveDraftDropTable(deps.db, request.body as never, request.actor?.actorId ?? null),
  );

  // 发布中心用的只读接口：版本列表、任意两版（或版本与草稿）的改动清单。
  app.get("/admin/draft/versions", async () => listContentVersions(deps.db));
  app.get("/admin/draft/diff", async (request) => diffContent(deps.db, request.query as { from?: unknown; to?: unknown }));

  app.post("/admin/draft/publish", async (request) => {
    const body = (request.body ?? {}) as { note?: string };
    return publishSnapshot(deps.db, body.note ?? "", request.actor?.actorId ?? null, deps.now());
  });
}
