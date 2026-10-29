-- 洞府 v1（药园 / 炼丹）。迁移号 0060+（0053–0059 留给强化线）。可以重复执行。
-- 1) content_items.effect：丹药效果 jsonb。
-- 2) 种子 / 草药 / 丹药物品（已有同编号不覆盖；缺 effect 的丹药补上）。
-- 3) content_globals.dongfu：地块数、炼丹队列、种子表、配方（没有才写入出厂默认）。
-- 4) player_dongfu_plots / player_dongfu_alchemy：种植与炼丹队列。
-- 5) player_active_buffs：临时属性丹写入的生效 buff（战斗结算归开发二号读取）。
ALTER TABLE "content_items" ADD COLUMN IF NOT EXISTS "effect" jsonb;
--> statement-breakpoint
INSERT INTO "content_items" ("slug", "display_name", "description", "kind", "quality", "stackable", "icon_key", "effect")
VALUES
  ('seed_lingcao', '灵草种子', '药园种植，成熟后收获灵草。', 'material', 'green', true, 'seed_lingcao', NULL),
  ('seed_qingxin', '清心草种子', '药园种植，成熟后收获清心草。', 'material', 'blue', true, 'seed_qingxin', NULL),
  ('herb_lingcao', '灵草', '药园产出，炼丹材料。', 'material', 'green', true, 'herb_lingcao', NULL),
  ('herb_qingxin', '清心草', '药园产出，炼丹材料。', 'material', 'blue', true, 'herb_qingxin', NULL),
  ('pill_cultivate', '修为丹', '使用后立刻增加修为。', 'pill', 'green', true, 'pill_cultivate', '{"cultivationGain":100}'::jsonb),
  ('pill_atk_temp', '攻击临时丹', '战斗中临时提升攻击。', 'pill', 'blue', true, 'pill_atk_temp', '{"buffStat":"attack","buffBp":1000,"durationSeconds":300}'::jsonb),
  ('pill_def_temp', '防御临时丹', '战斗中临时提升防御。', 'pill', 'blue', true, 'pill_def_temp', '{"buffStat":"defense","buffBp":1000,"durationSeconds":300}'::jsonb)
ON CONFLICT ("slug") DO NOTHING;
--> statement-breakpoint
UPDATE "content_items" SET "effect" = '{"cultivationGain":100}'::jsonb
WHERE "slug" = 'pill_cultivate' AND ("effect" IS NULL);
--> statement-breakpoint
UPDATE "content_items" SET "effect" = '{"buffStat":"attack","buffBp":1000,"durationSeconds":300}'::jsonb
WHERE "slug" = 'pill_atk_temp' AND ("effect" IS NULL);
--> statement-breakpoint
UPDATE "content_items" SET "effect" = '{"buffStat":"defense","buffBp":1000,"durationSeconds":300}'::jsonb
WHERE "slug" = 'pill_def_temp' AND ("effect" IS NULL);
--> statement-breakpoint
ALTER TABLE "content_globals" ADD COLUMN IF NOT EXISTS "dongfu" jsonb;
--> statement-breakpoint
UPDATE "content_globals"
SET "dongfu" = '{
  "plotCount": 4,
  "alchemyQueueLength": 2,
  "seeds": [
    {"seedSlug":"seed_lingcao","herbSlug":"herb_lingcao","growSeconds":60},
    {"seedSlug":"seed_qingxin","herbSlug":"herb_qingxin","growSeconds":120}
  ],
  "recipes": [
    {
      "recipeSlug":"pill_cultivate",
      "outputItemSlug":"pill_cultivate",
      "outputQty":1,
      "craftSeconds":30,
      "spiritStones":0,
      "costs":[{"itemSlug":"herb_lingcao","count":2}],
      "effect":{"cultivationGain":100}
    },
    {
      "recipeSlug":"pill_atk_temp",
      "outputItemSlug":"pill_atk_temp",
      "outputQty":1,
      "craftSeconds":45,
      "spiritStones":0,
      "costs":[{"itemSlug":"herb_lingcao","count":1},{"itemSlug":"herb_qingxin","count":1}],
      "effect":{"buffStat":"attack","buffBp":1000,"durationSeconds":300}
    },
    {
      "recipeSlug":"pill_def_temp",
      "outputItemSlug":"pill_def_temp",
      "outputQty":1,
      "craftSeconds":45,
      "spiritStones":0,
      "costs":[{"itemSlug":"herb_qingxin","count":2}],
      "effect":{"buffStat":"defense","buffBp":1000,"durationSeconds":300}
    }
  ]
}'::jsonb,
"updated_at" = now()
WHERE "dongfu" IS NULL OR jsonb_typeof("dongfu") <> 'object';
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "player_dongfu_plots" (
  "player_id" uuid NOT NULL REFERENCES "players"("id") ON DELETE CASCADE,
  "slot" integer NOT NULL,
  "seed_slug" text,
  "planted_at" timestamp with time zone,
  "mature_at" timestamp with time zone,
  CONSTRAINT "player_dongfu_plots_pk" PRIMARY KEY ("player_id", "slot")
);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "player_dongfu_alchemy" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "player_id" uuid NOT NULL REFERENCES "players"("id") ON DELETE CASCADE,
  "recipe_slug" text NOT NULL,
  "started_at" timestamp with time zone NOT NULL,
  "ready_at" timestamp with time zone NOT NULL,
  "claimed_at" timestamp with time zone
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "player_dongfu_alchemy_player_idx" ON "player_dongfu_alchemy" ("player_id");
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "player_active_buffs" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "player_id" uuid NOT NULL REFERENCES "players"("id") ON DELETE CASCADE,
  "buff_stat" text NOT NULL,
  "buff_bp" integer NOT NULL,
  "started_at" timestamp with time zone NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  "source_item_slug" text NOT NULL
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "player_active_buffs_player_idx" ON "player_active_buffs" ("player_id");
