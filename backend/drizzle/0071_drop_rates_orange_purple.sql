-- 掉率定案（2026-11-02）：紫/橙装备掉率提高；白/蓝定位材料向。
-- 1) 全局 tuning.monsterQualityWeights / bossRules.gearQualityPct / repeatGearQualityPct 写成新出厂。
-- 2) 关卡 monster_drop.qualityWeights 若仍是旧厂或 tip 旧值，清掉以跟随全局（橙装仍只由首领掉）。
-- 可重复执行。迁移号 0071；when 1801100000000。
UPDATE "content_globals"
SET "tuning" = jsonb_set(
  jsonb_set(
    jsonb_set(
      COALESCE("tuning", '{}'::jsonb),
      '{monsterQualityWeights}',
      '{"white":40,"green":20,"blue":15,"purple":25,"orange":0}'::jsonb
    ),
    '{bossRules,gearQualityPct}',
    '{"white":0,"green":20,"blue":20,"purple":35,"orange":25}'::jsonb
  ),
  '{bossRules,repeatGearQualityPct}',
  '{"white":0,"green":10,"blue":15,"purple":35,"orange":40}'::jsonb
),
"updated_at" = now()
WHERE "id" = 1
  AND COALESCE("tuning" -> 'bossRules', '{}'::jsonb) ? 'statMode';
--> statement-breakpoint
UPDATE "content_stages"
SET "monster_drop" = CASE
  WHEN "monster_drop" IS NULL THEN NULL
  WHEN jsonb_typeof("monster_drop" -> 'qualityWeights') = 'object' THEN ("monster_drop" - 'qualityWeights')
  ELSE "monster_drop"
END,
"updated_at" = now()
WHERE "monster_drop" IS NOT NULL
  AND jsonb_typeof("monster_drop" -> 'qualityWeights') = 'object';
