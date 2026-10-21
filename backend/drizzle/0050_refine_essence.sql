-- 第五批（2026-10-22）：分解改为玩家自选、产出「炼器精粹」，强化消耗精粹（SPEC_Q §17.2 / 17.3）。可以重复执行。
-- 1) 精粹物品 refine_essence（可堆叠材料，橙色底，图标 refine_essence）。已有同编号物品不覆盖。
-- 2) 强化规则补上 essence（产出 白20/绿60/蓝150/紫400/橙1000、每级返还 40、消耗 40×1.25^级×品质倍数、迁移比例 7000）。
--    只在草稿里还没有 essence 时写入，后台改过的不动。全部可在后台「装备强化」/ 配置概览改。
-- 3) 迁移记录表 enhance_exp_migrations：玩家剩余强化经验 → 精粹，每人只迁一次（主键），在玩家下次结算时做。
-- 4) 配置概览 tuning：去掉「行囊满时自动分解」（autoDecomposeQualities），换成「行囊满时不发装备的来源」默认值。
--    老数据里留着 autoDecomposeQualities 也没关系（读的时候忽略）。
INSERT INTO "content_items" ("slug", "display_name", "description", "kind", "quality", "stackable", "icon_key")
VALUES ('refine_essence', '炼器精粹', '分解装备得到，用来强化装备。', 'material', 'orange', true, 'refine_essence')
ON CONFLICT ("slug") DO NOTHING;
--> statement-breakpoint
UPDATE "content_globals"
SET "enhance" = "enhance" || jsonb_build_object('essence', jsonb_build_object(
  'itemSlug', 'refine_essence',
  'yields', jsonb_build_object('white', 20, 'green', 60, 'blue', 150, 'purple', 400, 'orange', 1000),
  'slotMultBp', '{}'::jsonb,
  'slotOverrides', '{}'::jsonb,
  'refundPerLevel', 40,
  'costBase', 40,
  'costGrowth', 1.25,
  'costTable', '{}'::jsonb,
  'migrationRatioBp', 7000
)), "updated_at" = now()
WHERE jsonb_typeof("enhance") = 'object' AND NOT ("enhance" ? 'essence');
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "enhance_exp_migrations" (
  "player_id" uuid PRIMARY KEY NOT NULL REFERENCES "players"("id") ON DELETE CASCADE,
  "enhance_exp" bigint NOT NULL,
  "essence" bigint NOT NULL,
  "ratio_bp" integer NOT NULL,
  "item_slug" text NOT NULL,
  "migrated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
UPDATE "content_globals"
SET "tuning" = ("tuning" - 'autoDecomposeQualities') || jsonb_build_object('bagFullSkipSources', '["stage_drop","boss_first","boss_repeat"]'::jsonb), "updated_at" = now()
WHERE jsonb_typeof("tuning") = 'object' AND NOT ("tuning" ? 'bagFullSkipSources');
