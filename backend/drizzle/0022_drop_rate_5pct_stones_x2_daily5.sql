-- 负责人决定（2026-10-16，第二次）：
-- 1) 普通怪每击杀装备掉率 4% -> 5%（content_stages.monster_drop.chanceBp 400 -> 500）。只改还停在旧默认 400 的关卡，后台改过的不动。
-- 2) 首领重复挑战突破石概率为最初值的 2 倍：下品 35% -> 70%（当前 52.5%）、中品 15% -> 30%（当前 22.5%）。
--    只改还停在上一版默认（5250 / 2250，迁移 0021 写入）的条目；后台改过的不动。
-- 3) 首领每日重复奖励次数 3 -> 5（content_globals.combat.bossDailyRewardCount）。只改还是 3 的。
-- 这些数都可以在后台随时调整：关卡与 Boss（掉落率、重复挑战奖励）、战斗公式与参数（每日奖励次数）。
UPDATE "content_stages"
SET "monster_drop" = jsonb_set("monster_drop", '{chanceBp}', '500'::jsonb)
WHERE "monster_drop" IS NOT NULL AND ("monster_drop" ->> 'chanceBp')::int = 400;

UPDATE "content_stages" AS s
SET "bosses" = (
  SELECT COALESCE(jsonb_agg(
    CASE
      WHEN jsonb_typeof(b -> 'repeat') = 'object' AND jsonb_typeof(b -> 'repeat' -> 'extras') = 'array' THEN
        jsonb_set(b, '{repeat,extras}', (
          SELECT COALESCE(jsonb_agg(
            CASE
              WHEN e ->> 'itemSlug' = 'enh_stone_low' AND (e ->> 'chanceBp')::int = 5250 THEN jsonb_set(e, '{chanceBp}', '7000'::jsonb)
              WHEN e ->> 'itemSlug' = 'enh_stone_mid' AND (e ->> 'chanceBp')::int = 2250 THEN jsonb_set(e, '{chanceBp}', '3000'::jsonb)
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

UPDATE "content_globals"
SET "combat" = jsonb_set("combat", '{bossDailyRewardCount}', '5'::jsonb)
WHERE "combat" IS NOT NULL AND ("combat" ->> 'bossDailyRewardCount') = '3';
