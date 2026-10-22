import type { FastifyInstance } from "fastify";
import { eq } from "drizzle-orm";
import { contentGlobals, contentRealms, contentStages } from "../../db/schema.js";
import type { Db } from "../operations/record.js";
import { AppError } from "../../shared/errors.js";
import { saveDraftDropTable } from "./draft-service.js";
import { readRules, readGameRules, rulesForSave, rulesFromInput, saveRules } from "./rules.js";
import { formulaExamples } from "./formula-examples.js";
import { buildFormulaPreview } from "./formula-preview.js";
import { loadCurrentWorld, loadDraftSnapshot } from "./snapshot.js";
import { readEnhanceView, saveEnhanceRules } from "./enhance.js";
import { enhanceExpMigrationStatus, migrateAllEnhanceExp } from "../loop/essence-migration.js";
import { listGear, removeMajorGear, resetGearPiece, saveGearQualityFactors, syncGear, updateGearPiece } from "./gear.js";
import { createGearSet, createManualGear, deleteGearSet, updateGearSet, updateManualGear } from "./manual-gear.js";
import { readConfigOverview, readTuning, resetStageDrop, saveConfigOverview, saveGearParams, saveTuning } from "./config-overview.js";
import { SCHEME_TIME_LIMIT_SECONDS } from "./numeric-scheme.js";
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
import { registerBossChapterRoutes } from "./boss-chapter-routes.js";
import { MAJOR_LAYER_LABELS, previewMajorLayers, scaleMajorLayers, previousMajorLayers, type MajorLayerSeed } from "./realm-major.js";

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


type RealmExtras = {
  requiredStageId?: string | null;
};

/** 境界表单里“大境界突破要先通关的首领关”。境界自带大招已取消。 */
async function realmExtras(db: Db, body: RealmExtras, current?: typeof contentRealms.$inferSelect) {
  const out: Partial<typeof contentRealms.$inferInsert> = {};
  if (body.requiredStageId !== undefined) {
    const slug = typeof body.requiredStageId === "string" ? body.requiredStageId.trim() : "";
    if (slug) {
      const [stage] = await db.select().from(contentStages).where(eq(contentStages.slug, slug)).limit(1);
      if (!stage) {
        throw new AppError("INVALID_INPUT", "所需通关关卡不存在");
      }
      const bosses = stage.bosses ?? [];
      if (bosses.length === 0 && stage.bossHp <= 0) {
        throw new AppError("INVALID_INPUT", "这个关卡没有首领，不能作为突破门槛");
      }
      const order = current?.sortOrder;
      if (order !== undefined && stage.requiredRealmOrder > order) {
        throw new AppError("INVALID_INPUT", "所需通关关卡的境界要求比这个境界还高，永远打不到");
      }
    }
    out.requiredStageSlug = slug || null;
  }
  return out;
}

async function globalBaseInterval(db: Db): Promise<number> {
  const [row] = await db.select().from(contentGlobals).where(eq(contentGlobals.id, 1)).limit(1);
  const value = Number(row?.combat?.baseInterval);
  return Number.isFinite(value) && value > 0 ? value : 1.5;
}

export async function registerDraftRoutes(app: FastifyInstance, deps: { db: Db; now: () => Date }): Promise<void> {
  // 第三批：章节、首领规则、立绘清单（单独一个文件，少和别的改动撞车）
  await registerBossChapterRoutes(app, deps);
  app.get("/admin/draft/realms", async () => {
    const rows = await deps.db.select().from(contentRealms);
    return rows
      .sort((left, right) => left.sortOrder - right.sortOrder)
      .map((row) => ({
        code: row.sortOrder,
        slug: row.slug,
        displayName: row.displayName,
        majorName: row.majorName,
        tickSeconds: row.tickSeconds,
        gainPerTick: row.gainPerTick,
        breakthroughCost: row.breakthroughCost,
        attack: row.baseAttack,
        defense: row.baseDefense,
        hp: row.baseHp,
        speed: row.baseSpeed,
        requiredStageId: row.requiredStageSlug ?? "",
      }));
  });

  /** 新建大境界预览：按上一大境界三层 × 固定倍率（可改后再 POST）。 */
  app.get("/admin/draft/realms/major-preview", async (request) => {
    const majorName = String((request.query as { majorName?: string }).majorName ?? "");
    const rows = await deps.db.select().from(contentRealms);
    const baseInterval = await globalBaseInterval(deps.db);
    return {
      baseInterval,
      tickSeconds: 1,
      layers: previewMajorLayers(rows, majorName),
      rule: "上一大境界同层：修为/攻防血/突破消耗×3、速度+10；无上一境用炼气种子",
    };
  });

  /** 新建大境界：一次写入三层（一层/二层/三层），编号自动接在末尾。 */
  app.post("/admin/draft/realms/major", async (request) => {
    const body = request.body as {
      majorName?: string;
      layers?: Partial<MajorLayerSeed>[];
    };
    const majorName = body.majorName?.trim() ?? "";
    if (!majorName) {
      throw new AppError("INVALID_INPUT", "请填写大境界名称");
    }
    const rows = await deps.db.select().from(contentRealms);
    if (rows.some((row) => row.majorName.trim() === majorName)) {
      throw new AppError("INVALID_INPUT", `大境界「${majorName}」已存在`);
    }
    const defaults = scaleMajorLayers(previousMajorLayers(rows));
    const layers: MajorLayerSeed[] = [0, 1, 2].map((index) => {
      const override = body.layers?.[index] ?? {};
      const base = defaults[index]!;
      return {
        gainPerTick: statNumber(override.gainPerTick, "每次获得修为", base.gainPerTick),
        breakthroughCost: statNumber(override.breakthroughCost, "突破消耗修为", base.breakthroughCost),
        attack: statNumber(override.attack, "攻击", base.attack),
        defense: statNumber(override.defense, "防御", base.defense),
        hp: statNumber(override.hp, "气血", base.hp),
        speed: statNumber(override.speed, "速度", base.speed),
      };
    });
    const maxCode = rows.reduce((max, row) => Math.max(max, row.sortOrder), 0);
    const baseInterval = await globalBaseInterval(deps.db);
    const codes: number[] = [];
    for (let index = 0; index < 3; index += 1) {
      const code = maxCode + index + 1;
      codes.push(code);
      const layer = layers[index]!;
      await deps.db.insert(contentRealms).values({
        slug: String(code),
        displayName: `${majorName}${MAJOR_LAYER_LABELS[index]}`,
        majorName,
        sortOrder: code,
        nextRealmSlug: null,
        tickSeconds: 1,
        gainPerTick: layer.gainPerTick,
        breakthroughCost: layer.breakthroughCost,
        baseAttack: layer.attack,
        baseDefense: layer.defense,
        baseHp: layer.hp,
        baseSpeed: layer.speed,
        baseInterval,
        ultName: "",
        ultDamageMultBp: 0,
        ultCooldownSeconds: 0,
        ultFirstCooldownSeconds: 0,
        updatedAt: deps.now(),
        updatedBy: request.actor?.actorId ?? null,
      });
    }
    await syncGear(deps.db, request.actor?.actorId ?? null);
    return { ok: true, codes, majorName };
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
    } & RealmExtras;
    const code = realmCode(body.code);
    if (!body.displayName?.trim()) {
      throw new AppError("INVALID_INPUT", "请填写境界名称");
    }
    await assertCodeAvailable(deps.db, code);
    const extras = await realmExtras(deps.db, body, { sortOrder: code } as typeof contentRealms.$inferSelect);
    const baseInterval = await globalBaseInterval(deps.db);
    await deps.db.insert(contentRealms).values({
      ...extras,
      slug: String(code),
      displayName: body.displayName.trim(),
      majorName: body.majorName?.trim() ?? "",
      sortOrder: code,
      nextRealmSlug: null,
      tickSeconds: 1,
      gainPerTick: body.gainPerTick ?? 0,
      breakthroughCost: body.breakthroughCost ?? 0,
      baseAttack: statNumber(body.attack, "攻击", 0),
      baseDefense: statNumber(body.defense, "防御", 0),
      baseHp: statNumber(body.hp, "气血", 0),
      baseSpeed: statNumber(body.speed, "速度", 0),
      baseInterval,
      ultName: "",
      ultDamageMultBp: 0,
      ultCooldownSeconds: 0,
      ultFirstCooldownSeconds: 0,
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
    } & RealmExtras;
    const nextCode = realmCode(body.code ?? currentCode);
    const [current] = await deps.db.select().from(contentRealms).where(eq(contentRealms.sortOrder, currentCode)).limit(1);
    if (!current) {
      throw new AppError("NOT_FOUND", "没有这个境界");
    }
    if (!body.displayName?.trim()) {
      throw new AppError("INVALID_INPUT", "请填写境界名称");
    }
    const gainPerTick = body.gainPerTick ?? current.gainPerTick;
    const breakthroughCost = body.breakthroughCost ?? current.breakthroughCost;
    const attack = statNumber(body.attack, "攻击", current.baseAttack);
    const defense = statNumber(body.defense, "防御", current.baseDefense);
    const hp = statNumber(body.hp, "气血", current.baseHp);
    const speed = statNumber(body.speed, "速度", current.baseSpeed);
    const baseInterval = await globalBaseInterval(deps.db);
    if (gainPerTick < 0 || breakthroughCost < 0) {
      throw new AppError("INVALID_INPUT", "修为和突破消耗不能小于 0");
    }
    await assertCodeAvailable(deps.db, nextCode, current.slug);
    const extras = await realmExtras(deps.db, body, { ...current, sortOrder: nextCode });
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
        ...extras,
        // 编号没变就保持原来的编号（slug）：玩家进度、关卡门槛都按它引用，改名字不能改它。
        slug: nextCode === current.sortOrder ? current.slug : String(nextCode),
        displayName: body.displayName.trim(),
        majorName,
        sortOrder: nextCode,
        nextRealmSlug: null,
        tickSeconds: 1,
        gainPerTick,
        breakthroughCost,
        baseAttack: attack,
        baseDefense: defense,
        baseHp: hp,
        baseSpeed: speed,
        baseInterval,
        ultName: "",
        ultDamageMultBp: 0,
        ultCooldownSeconds: 0,
        ultFirstCooldownSeconds: 0,
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
        offlineCapSeconds: 28800,
        bagCapacity: 20,
        combat: { challengeCooldownSeconds: 0, timeLimitSeconds: SCHEME_TIME_LIMIT_SECONDS, recommendedPowerMargin: 1.05 },
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
  app.get("/admin/draft/enhance", async () => ({ ...(await readEnhanceView(deps.db)), migration: await enhanceExpMigrationStatus(deps.db) }));
  // 第五批：一键把所有玩家剩余的强化经验换成炼器精粹（每人只迁一次；不点也会在玩家下次结算时自动迁）
  app.post("/admin/draft/enhance/migrate-exp", async () => {
    const world = await loadCurrentWorld(deps.db);
    if (!world) {
      throw new AppError("INVALID_INPUT", "请先新建境界");
    }
    return migrateAllEnhanceExp(deps.db, world, new Date());
  });
  app.put("/admin/draft/enhance", async (request) => saveEnhanceRules(deps.db, request.body, request.actor?.actorId ?? null));
  app.get("/admin/draft/gear", async () => listGear(deps.db));
  app.put("/admin/draft/gear-qualities", async (request) =>
    saveGearQualityFactors(deps.db, request.body as Record<string, unknown>, request.actor?.actorId ?? null),
  );
  app.put("/admin/draft/gear/:id", async (request) =>
    updateGearPiece(
      deps.db,
      (request.params as { id: string }).id,
      request.body as { displayName?: string | null; description?: string | null; iconKey?: string | null; dropMult?: number | null },
      request.actor?.actorId ?? null,
    ),
  );
  // 手动装备、套装（ADMIN_SPEC §10、§12）
  app.post("/admin/draft/gear/manual", async (request) => createManualGear(deps.db, (request.body ?? {}) as never, request.actor?.actorId ?? null));
  app.put("/admin/draft/gear/manual/:id", async (request) =>
    updateManualGear(deps.db, (request.params as { id: string }).id, (request.body ?? {}) as never, request.actor?.actorId ?? null),
  );
  app.post("/admin/draft/gear-sets", async (request) => createGearSet(deps.db, (request.body ?? {}) as never, request.actor?.actorId ?? null));
  app.put("/admin/draft/gear-sets/:id", async (request) =>
    updateGearSet(deps.db, (request.params as { id: string }).id, (request.body ?? {}) as never, request.actor?.actorId ?? null),
  );
  app.delete("/admin/draft/gear-sets/:id", async (request) => deleteGearSet(deps.db, (request.params as { id: string }).id, request.actor?.actorId ?? null));
  app.post("/admin/draft/gear/:id/reset", async (request) =>
    resetGearPiece(deps.db, (request.params as { id: string }).id, request.actor?.actorId ?? null),
  );
  app.put("/admin/draft/gear-params", async (request) => saveGearParams(deps.db, (request.body ?? {}) as never, request.actor?.actorId ?? null));
  app.post("/admin/draft/gear/regenerate", async (request) => {
    await syncGear(deps.db, request.actor?.actorId ?? null);
    return { ok: true };
  });
  // 配置概览
  app.get("/admin/draft/config-overview", async () => readConfigOverview(deps.db));
  app.put("/admin/draft/config-overview", async (request) => saveConfigOverview(deps.db, (request.body ?? {}) as never, request.actor?.actorId ?? null));
  app.get("/admin/draft/tuning", async () => readTuning(deps.db));
  app.put("/admin/draft/tuning", async (request) => saveTuning(deps.db, (request.body ?? {}) as never, request.actor?.actorId ?? null));
  app.post("/admin/draft/stages/:id/reset-drop", async (request) =>
    resetStageDrop(deps.db, (request.params as { id: string }).id, request.actor?.actorId ?? null),
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
