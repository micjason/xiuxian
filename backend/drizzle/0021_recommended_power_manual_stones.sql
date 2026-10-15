-- 负责人决定（2026-10-16）：
-- 1) 关卡推荐战力改为后台手填（content_stages.recommended_power，0 = 没填、按首领数值自动算）；
--    原型三个首领关卡写入设计表 2.3 的默认值 900 / 2450 / 6590（只在还没填的时候写，不覆盖后台已填的值）。
-- 2) 首领重复挑战的突破石产出 +50%：低阶石 35% → 52.5%，中阶石 15% → 22.5%（只改还停在旧默认值的条目；
--    后台改过的不动）。这两个数在后台「关卡与 Boss → 重复挑战奖励」里可以随时调整。
UPDATE "content_stages" SET "recommended_power" = 900 WHERE "slug" = 'lianqi_3' AND "recommended_power" = 0;
UPDATE "content_stages" SET "recommended_power" = 2450 WHERE "slug" = 'zhuji_3' AND "recommended_power" = 0;
UPDATE "content_stages" SET "recommended_power" = 6590 WHERE "slug" = 'jindan_3' AND "recommended_power" = 0;

UPDATE "content_stages" AS s
SET "bosses" = (
  SELECT COALESCE(jsonb_agg(
    CASE
      WHEN jsonb_typeof(b -> 'repeat') = 'object' AND jsonb_typeof(b -> 'repeat' -> 'extras') = 'array' THEN
        jsonb_set(b, '{repeat,extras}', (
          SELECT COALESCE(jsonb_agg(
            CASE
              WHEN e ->> 'itemSlug' = 'enh_stone_low' AND (e ->> 'chanceBp')::int = 3500 THEN jsonb_set(e, '{chanceBp}', '5250'::jsonb)
              WHEN e ->> 'itemSlug' = 'enh_stone_mid' AND (e ->> 'chanceBp')::int = 1500 THEN jsonb_set(e, '{chanceBp}', '2250'::jsonb)
              ELSE e
            END
          ), '[]'::jsonb)
          FROM jsonb_array_elements(b -> 'repeat' -> 'extras') AS e
        ))
      ELSE b
    END
  ), '[]'::jsonb)
  FROM jsonb_array_elements(s."bosses") AS b
)
WHERE jsonb_array_length(s."bosses") > 0;
