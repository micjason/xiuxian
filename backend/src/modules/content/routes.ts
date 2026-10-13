import type { FastifyInstance } from "fastify";
import type { Db } from "../operations/record.js";
import {
  buildPublishedContent,
  importContentBodies,
  type JsonRecord,
  listBuildings,
  listStages,
  readDraftSettings,
  saveBuilding,
  saveDrop,
  saveStage,
  updateDraftSettings,
} from "./pack.js";
import { AppError } from "../../shared/errors.js";
import { PublishRejected } from "./service.js";
import { ensureSkillBooks } from "./ops-content.js";
import { loadCurrentWorld } from "./snapshot.js";
import { stageRecommendedPower } from "./stage-power.js";
import {
  diffDraft,
  listDraftItems,
  listDraftRealms,
  listDraftSkills,
  publish,
  saveItem,
  saveRealm,
  saveSkill,
  type ItemInput,
  type RealmInput,
  type SkillInput,
} from "./service.js";

function slugList(value: string | string[] | undefined): string[] {
  const source = Array.isArray(value) ? value : String(value ?? "").split(/[,，]/);
  return source.map((item) => item.trim()).filter((item) => item.length > 0);
}


export async function registerContentRoutes(
  app: FastifyInstance,
  deps: { db: Db; now: () => Date },
): Promise<void> {
  app.get("/content/published", async () => {
    return (await buildPublishedContent(deps.db)) ?? { offlineCapSeconds: null, idle: null, adventure: null, longterm: null };
  });

  app.get("/content/current", async () => {
    await ensureSkillBooks(deps.db);
    const world = await loadCurrentWorld(deps.db);
    if (!world) {
      throw new AppError("CONTENT_NOT_PUBLISHED");
    }
    return {
      ...world,
      stages: world.stages.map((stage) => {
        if (!stage.bosses?.[0]) {
          return stage;
        }
        try {
          return { ...stage, recommendedPower: stageRecommendedPower(world, stage) };
        } catch (cause) {
          if (cause instanceof AppError) {
            return { ...stage, powerProblem: cause.message };
          }
          throw cause;
        }
      }),
    };
  });

  app.get("/admin/content/settings", async (request, reply) => {
    return readDraftSettings(deps.db);
  });

  app.put("/admin/content/settings", async (request, reply) => {
    const body = request.body as {
      offlineCapSeconds?: number;
      inventoryCapacity?: number;
      queueLimit?: number;
    };
    await updateDraftSettings(deps.db, body);
    return readDraftSettings(deps.db);
  });

  app.get("/admin/content/stages", async (request, reply) => {
    return listStages(deps.db);
  });

  app.put("/admin/content/stages/:id", async (request, reply) => {
    const params = request.params as { id: string };
    const body = request.body as {
      displayName: string;
      bossName: string;
      attack: number;
      defense: number;
      hp: number;
      interval: number;
    };
    await saveStage(deps.db, params.id, body);
    return { ok: true };
  });

  app.put("/admin/content/stages/:id/drops", async (request, reply) => {
    const params = request.params as { id: string };
    const body = request.body as { itemSlug: string; chance: number; quantity: number };
    try {
      await saveDrop(deps.db, params.id, {
        itemSlug: body.itemSlug,
        chance: Number(body.chance),
        quantity: Number(body.quantity),
      });
    } catch (cause) {
      throw new AppError("INVALID_INPUT", cause instanceof Error ? cause.message : undefined);
    }
    return { ok: true };
  });

  app.get("/admin/content/buildings", async (request, reply) => {
    return listBuildings(deps.db);
  });

  app.put("/admin/content/buildings/:id", async (request, reply) => {
    const params = request.params as { id: string };
    const body = request.body as {
      displayName: string;
      maxLevel: number;
      laborBonus: number;
      cultivateBonusPerLevel: number;
    };
    await saveBuilding(deps.db, params.id, body);
    return { ok: true };
  });

  app.post("/admin/content/import", async (request, reply) => {
    const body = request.body as { idle?: JsonRecord; adventure?: JsonRecord; longterm?: JsonRecord };
    if (!body.idle || !body.adventure || !body.longterm) {
      throw new AppError("INVALID_INPUT");
    }
    await importContentBodies(deps.db, { idle: body.idle, adventure: body.adventure, longterm: body.longterm });
    return { ok: true };
  });

  app.get("/admin/content/realms", async (request, reply) => {
    return listDraftRealms(deps.db);
  });

  app.get("/admin/content/skills", async (request, reply) => {
    return listDraftSkills(deps.db);
  });

  app.get("/admin/content/items", async (request, reply) => {
    return listDraftItems(deps.db);
  });

  app.get("/admin/content/diff", async (request, reply) => {
    return diffDraft(deps.db);
  });

  app.put("/admin/content/realms/:slug", async (request, reply) => {
    const body = request.body as Omit<RealmInput, "slug">;
    const params = request.params as { slug: string };
    await saveRealm(deps.db, request.actor!.actorId, { ...body, slug: params.slug });
    return { ok: true };
  });

  app.put("/admin/content/skills/:slug", async (request, reply) => {
    const body = request.body as Omit<SkillInput, "slug"> & { prerequisiteSlugs?: string | string[] };
    const params = request.params as { slug: string };
    await saveSkill(deps.db, { ...body, slug: params.slug, prerequisiteSlugs: slugList(body.prerequisiteSlugs) });
    return { ok: true };
  });

  app.put("/admin/content/items/:slug", async (request, reply) => {
    const body = request.body as Omit<ItemInput, "slug">;
    const params = request.params as { slug: string };
    const raw = request.body as { grantable?: boolean | string; skillSlug?: string | null };
    await saveItem(deps.db, {
      ...body,
      slug: params.slug,
      grantable: raw.grantable === true || raw.grantable === "true",
      skillSlug: raw.skillSlug ? String(raw.skillSlug) : null,
    });
    return { ok: true };
  });

  app.post("/admin/content/publish", async (request, reply) => {
    try {
      return await publish(deps.db, { id: request.actor!.actorId, name: request.actor!.actorName, actorType: "admin" }, deps.now());
    } catch (cause) {
      if (cause instanceof PublishRejected) {
        throw new AppError("PUBLISH_REJECTED", cause.message);
      }
      throw cause;
    }
  });
}
