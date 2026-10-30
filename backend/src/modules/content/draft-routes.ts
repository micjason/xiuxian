import type { FastifyInstance } from "fastify";
import { eq } from "drizzle-orm";
import { contentRealms, contentStages } from "../../db/schema.js";
import type { Db } from "../operations/record.js";
import { AppError } from "../../shared/errors.js";
import { deleteDraftDropTable, listDraftDropTables, saveDraftDropTable } from "./draft-service.js";
import { readRules, readGameRules, rulesForSave, rulesFromInput, saveRules } from "./rules.js";
import { formulaExamples } from "./formula-examples.js";
import { buildFormulaPreview } from "./formula-preview.js";
import { loadCurrentWorld, loadDraftSnapshot } from "./snapshot.js";
import { readEnhanceView, saveEnhanceRules } from "./enhance.js";
import { enhanceExpMigrationStatus, migrateAllEnhanceExp } from "../loop/essence-migration.js";
import { readDongfuView, saveDongfuConfig } from "../dongfu/admin.js";
import { listGear, previewGearParams, resetGearPiece, saveGearQualityFactors, syncGear, updateGearPiece } from "./gear.js";
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
import { editableKeys, factoryByCode, listFixedRealms, showsBreakthroughCost, showsGate } from "./realm-factory.js";
import { ensureFactoryRealms } from "./realm-seed.js";

const REALM_FIELD_LABELS: Record<string, string> = {
  gainPerTick: "本境每秒修为",
  breakthroughCost: "升到下一层所需修为",
  attack: "攻击",
  defense: "防御",
  hp: "气血",
  speed: "速度",
};

function integerStat(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new AppError("INVALID_INPUT", `${label}必须是大于等于 0 的整数`);
  }
  return value;
}

function realmCode(value: unknown): number {
  const code = Number(value);
  if (!Number.isInteger(code) || code < 1) {
    throw new AppError("INVALID_INPUT", "编号必须是大于 0 的整数");
  }
  return code;
}

type RealmExtras = {
  requiredStageId?: string | null;
};

/** 境界表单里“大境界突破要先通关的首领关”。境界自带终极技字段已停用，保存时清零。 */
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

export async function registerDraftRoutes(app: FastifyInstance, deps: { db: Db; now: () => Date }): Promise<void> {
  // 第三批：章节、首领规则、立绘清单（单独一个文件，少和别的改动撞车）
  await registerBossChapterRoutes(app, deps);
  app.get("/admin/draft/realms", async (request) => {
    await ensureFactoryRealms(deps.db, deps.now(), request.actor?.actorId ?? null);
    const rows = await deps.db.select().from(contentRealms);
    return listFixedRealms(rows);
  });

  app.put("/admin/draft/realms/:code", async (request) => {
    const code = realmCode((request.params as { code: string }).code);
    const seed = factoryByCode(code);
    if (!seed) {
      throw new AppError("NOT_FOUND", "没有这个境界");
    }
    const body = request.body;
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new AppError("INVALID_INPUT", "请提交要修改的数字");
    }
    const record = body as Record<string, unknown>;
    const keys = Object.keys(record);
    if (keys.length === 0) {
      throw new AppError("INVALID_INPUT", "没有要保存的数字");
    }
    const allowed = new Set(editableKeys(seed));
    for (const key of keys) {
      if (allowed.has(key)) continue;
      if (key === "breakthroughCost" && !showsBreakthroughCost(seed)) {
        throw new AppError("INVALID_INPUT", "大乘三层没有下一层，不能改突破修为");
      }
      if (key === "requiredStageId" && !showsGate(seed)) {
        throw new AppError("INVALID_INPUT", "只有各大境三层可以设置突破前通关");
      }
      throw new AppError("INVALID_INPUT", `不能修改「${key}」`);
    }
    await ensureFactoryRealms(deps.db, deps.now(), request.actor?.actorId ?? null);
    const [current] = await deps.db.select().from(contentRealms).where(eq(contentRealms.slug, seed.slug)).limit(1);
    if (!current) {
      throw new AppError("INVALID_INPUT", `编号 ${code} 已被其他境界占用，固定表写不进去`);
    }
    const patch: Partial<typeof contentRealms.$inferInsert> = {
      tickSeconds: 1,
      updatedAt: deps.now(),
      updatedBy: request.actor?.actorId ?? null,
    };
    for (const key of ["gainPerTick", "breakthroughCost", "attack", "defense", "hp", "speed"] as const) {
      if (record[key] === undefined) continue;
      const value = integerStat(record[key], REALM_FIELD_LABELS[key] ?? key);
      if (key === "gainPerTick") patch.gainPerTick = value;
      if (key === "breakthroughCost") patch.breakthroughCost = value;
      if (key === "attack") patch.baseAttack = value;
      if (key === "defense") patch.baseDefense = value;
      if (key === "hp") patch.baseHp = value;
      if (key === "speed") patch.baseSpeed = value;
    }
    if (record.requiredStageId !== undefined) {
      if (typeof record.requiredStageId !== "string") {
        throw new AppError("INVALID_INPUT", "突破前通关关卡不正确");
      }
      Object.assign(patch, await realmExtras(deps.db, { requiredStageId: record.requiredStageId }, current));
    }
    await deps.db.update(contentRealms).set(patch).where(eq(contentRealms.slug, seed.slug));
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
  app.get("/admin/draft/dongfu", async () => readDongfuView(deps.db));
  app.put("/admin/draft/dongfu", async (request) => saveDongfuConfig(deps.db, request.body, request.actor?.actorId ?? null));
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
  app.post("/admin/draft/gear-params/preview", async (request) => previewGearParams(deps.db, (request.body ?? {}) as never));
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
  app.get("/admin/draft/drop-tables", async () => listDraftDropTables(deps.db));
  app.post("/admin/draft/drop-tables", async (request) =>
    saveDraftDropTable(deps.db, request.body as never, request.actor?.actorId ?? null),
  );
  app.put("/admin/draft/drop-tables/:slug", async (request) => {
    const slug = (request.params as { slug: string }).slug;
    return saveDraftDropTable(deps.db, { ...(request.body as object), slug }, request.actor?.actorId ?? null);
  });
  app.delete("/admin/draft/drop-tables/:slug", async (request) =>
    deleteDraftDropTable(deps.db, (request.params as { slug: string }).slug),
  );

  // 可选快照/对比（开发阶段玩家读配置表，不依赖发布）。保留给种子脚本与版本历史页。
  app.get("/admin/draft/versions", async () => listContentVersions(deps.db));
  app.get("/admin/draft/diff", async (request) => diffContent(deps.db, request.query as { from?: unknown; to?: unknown }));

  // 可选：写入历史快照。后台 UI 开发阶段已去掉「必须发布」；种子/e2e 仍可调用。
  app.post("/admin/draft/publish", async (request) => {
    const body = (request.body ?? {}) as { note?: string };
    return publishSnapshot(deps.db, body.note ?? "", request.actor?.actorId ?? null, deps.now());
  });
}
