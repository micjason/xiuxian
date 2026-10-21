-- 后台改版（2026-10-21，Chengpeng 确认）：
-- 1) content_globals.tuning：配置概览里的默认数值（装备预算比例、部位占比、功法层数系数 / 满层、自动分解范围、
--    多余功法书折算修为、普通怪默认掉率和品质权重、首领橙装概率）。null = 全部用代码里的默认值（和改版前一样）。
-- 2) content_items：装备掉率倍数 drop_mult（默认 1）和「名称 / 描述改过」标记（重新生成时不覆盖）。
-- 3) content_stages.recommended_power 允许 null：null = 按公式自动算，数字 = 手动覆盖；原来的 0（= 自动）改成 null。
--    已经手填的 900 / 2450 / 6590 保留为「手动覆盖」，后台可一键恢复自动。
-- 4) content_stages.monster_drop 只存关卡自己改过的项：和新默认值（每只 5%、白 70 / 绿 25 / 蓝 5 / 紫 0）相同的项去掉，
--    跟随配置概览。原来没写的权重表示 0，这里写成显式的 0（默认不是 0 的时候），保证迁移前后实际掉落完全一样。
ALTER TABLE "content_globals" ADD COLUMN IF NOT EXISTS "tuning" jsonb;
--> statement-breakpoint
ALTER TABLE "content_items" ADD COLUMN IF NOT EXISTS "drop_mult" double precision DEFAULT 1 NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_items" ADD COLUMN IF NOT EXISTS "name_custom" boolean DEFAULT false NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_items" ADD COLUMN IF NOT EXISTS "description_custom" boolean DEFAULT false NOT NULL;
--> statement-breakpoint
-- 装备名称不是自动生成的格式（大境界·品质·部位）就算后台改过
UPDATE "content_items" SET "name_custom" = true WHERE "kind" = 'equipment' AND "display_name" NOT LIKE '%·%·%';
--> statement-breakpoint
ALTER TABLE "content_stages" ALTER COLUMN "recommended_power" DROP NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_stages" ALTER COLUMN "recommended_power" DROP DEFAULT;
--> statement-breakpoint
UPDATE "content_stages" SET "recommended_power" = NULL WHERE "recommended_power" = 0;
--> statement-breakpoint
UPDATE "content_stages" AS s
SET "monster_drop" = (
  SELECT CASE WHEN c = '{}'::jsonb THEN NULL ELSE c END
  FROM (
    SELECT jsonb_strip_nulls(jsonb_build_object(
      'chanceBp', CASE WHEN COALESCE((s."monster_drop" ->> 'chanceBp')::numeric, 0) = 500 THEN NULL ELSE to_jsonb(COALESCE((s."monster_drop" ->> 'chanceBp')::numeric, 0)) END,
      'qualityWeights', NULLIF(jsonb_strip_nulls(jsonb_build_object(
        'white', CASE WHEN COALESCE((s."monster_drop" -> 'qualityWeights' ->> 'white')::numeric, 0) = 70 THEN NULL ELSE to_jsonb(COALESCE((s."monster_drop" -> 'qualityWeights' ->> 'white')::numeric, 0)) END,
        'green', CASE WHEN COALESCE((s."monster_drop" -> 'qualityWeights' ->> 'green')::numeric, 0) = 25 THEN NULL ELSE to_jsonb(COALESCE((s."monster_drop" -> 'qualityWeights' ->> 'green')::numeric, 0)) END,
        'blue', CASE WHEN COALESCE((s."monster_drop" -> 'qualityWeights' ->> 'blue')::numeric, 0) = 5 THEN NULL ELSE to_jsonb(COALESCE((s."monster_drop" -> 'qualityWeights' ->> 'blue')::numeric, 0)) END,
        'purple', CASE WHEN COALESCE((s."monster_drop" -> 'qualityWeights' ->> 'purple')::numeric, 0) = 0 THEN NULL ELSE to_jsonb(COALESCE((s."monster_drop" -> 'qualityWeights' ->> 'purple')::numeric, 0)) END
      )), '{}'::jsonb)
    )) AS c
  ) AS compact
)
WHERE s."monster_drop" IS NOT NULL AND jsonb_typeof(s."monster_drop") = 'object'
  -- 只在第一次执行时转换（之后 tuning 已经是 '{}'，关卡里存的就是新格式了）
  AND NOT EXISTS (SELECT 1 FROM "content_globals" WHERE "tuning" IS NOT NULL);
--> statement-breakpoint
-- 标记已转换：tuning = {}（全部用默认值）
UPDATE "content_globals" SET "tuning" = '{}'::jsonb WHERE "tuning" IS NULL;
