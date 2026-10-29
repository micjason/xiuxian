-- 洞府 v1 · 关卡种子掉落（开发二号）。可以重复执行。
-- 1) 种子 / 草药 / 丹药占位物品（已有同编号不覆盖）。
-- 2) content_stages.seed_drops：单关覆盖（NULL = 跟随全局；[] = 本关不掉）。
-- 3) tuning.seedDrops 全局默认（配置概览）；没有才写入。
INSERT INTO "content_items" ("slug", "display_name", "description", "kind", "quality", "stackable", "icon_key")
VALUES
  ('seed_lingcao', '灵草种子', '药园种植，成熟后收获灵草。', 'material', 'green', true, 'seed_lingcao'),
  ('seed_qingxin', '清心草种子', '药园种植，成熟后收获清心草。', 'material', 'blue', true, 'seed_qingxin'),
  ('herb_lingcao', '灵草', '药园产出，炼丹材料。', 'material', 'green', true, 'herb_lingcao'),
  ('herb_qingxin', '清心草', '药园产出，炼丹材料。', 'material', 'blue', true, 'herb_qingxin'),
  ('pill_cultivate', '修为丹', '使用后增加修为或短时加快修炼（洞府炼丹）。', 'pill', 'green', true, 'pill_cultivate'),
  ('pill_atk_temp', '攻击临时丹', '战斗中临时提升攻击（洞府炼丹）。', 'pill', 'blue', true, 'pill_atk_temp'),
  ('pill_def_temp', '防御临时丹', '战斗中临时提升防御（洞府炼丹）。', 'pill', 'blue', true, 'pill_def_temp')
ON CONFLICT ("slug") DO NOTHING;
--> statement-breakpoint
ALTER TABLE "content_stages" ADD COLUMN IF NOT EXISTS "seed_drops" jsonb;
--> statement-breakpoint
UPDATE "content_globals"
SET "tuning" = "tuning" || jsonb_build_object(
  'seedDrops',
  '[{"itemSlug":"seed_lingcao","chanceBp":800,"minCount":1,"maxCount":1},{"itemSlug":"seed_qingxin","chanceBp":400,"minCount":1,"maxCount":1}]'::jsonb
), "updated_at" = now()
WHERE jsonb_typeof("tuning") = 'object' AND NOT ("tuning" ? 'seedDrops');
