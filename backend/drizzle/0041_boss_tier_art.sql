-- 第三批（2026-10-21）：每关一个首领 + 怪物 / 首领立绘改成字段。
-- 1) 普通怪、首领加 artKey（立绘编号，见 backend/src/modules/content/art-keys.ts），按现有 9 只怪、3 个首领的名字回填；
--    名字对不上的不填（发布校验会报错，后台选一下就好）。
-- 2) 没有首领的普通关卡（不是本章章末关）补一个小首领（精英）：名字「精英·<本关小怪>」，属性按规则自动算
--    （库里也写一份按默认倍率 气血×5 攻×1.3 防×1.2 算好的数，方便后台看），立绘跟随本关小怪；
--    首通奖励（后台可改）= 灵石（炼气 50 / 筑基 150 / 金丹 450，按所需境界每 3 层 ×3）+ 突破石·下品 ×1（有这个物品时）+ 按首领规则品质抽 1 件装备。
-- 3) player_stage_progress.auto_challenge_at：自动挑战输了以后的重试计时。
-- 可以重复执行（已经有 artKey / 已经有首领的不动）。
UPDATE "content_stages" AS s
SET "monsters" = (
  SELECT jsonb_agg(CASE WHEN e.m ? 'artKey' OR a.key IS NULL THEN e.m ELSE e.m || jsonb_build_object('artKey', a.key) END ORDER BY e.ord)
  FROM jsonb_array_elements(s."monsters") WITH ORDINALITY AS e(m, ord)
  LEFT JOIN (VALUES
    ('青鬃狼', 'wolf'), ('赤眼狐妖', 'fox'), ('毒牙蟒', 'snake'), ('游魂', 'ghost'), ('骨傀', 'bone_golem'),
    ('血蝠', 'bat'), ('炎鳞蜥', 'lava_lizard'), ('火鸦', 'fire_crow'), ('熔岩傀', 'lava_golem')
  ) AS a(name, key) ON a.name = e.m ->> 'name'
)
WHERE jsonb_typeof(s."monsters") = 'array' AND jsonb_array_length(s."monsters") > 0;
--> statement-breakpoint
UPDATE "content_stages" AS s
SET "bosses" = (
  SELECT jsonb_agg(CASE WHEN e.b ? 'artKey' OR a.key IS NULL THEN e.b ELSE e.b || jsonb_build_object('artKey', a.key) END ORDER BY e.ord)
  FROM jsonb_array_elements(s."bosses") WITH ORDINALITY AS e(b, ord)
  LEFT JOIN (VALUES ('黑风熊王', 'bear'), ('噬魂老鬼', 'ghost_elder'), ('赤焰蛟', 'fire_jiao')) AS a(name, key) ON a.name = e.b ->> 'name'
)
WHERE jsonb_typeof(s."bosses") = 'array' AND jsonb_array_length(s."bosses") > 0;
--> statement-breakpoint
WITH chief AS (
  SELECT COALESCE(c."chief_stage_slug", (
    SELECT s2."slug" FROM "content_stages" s2
    WHERE s2."chapter_slug" = c."slug" AND s2."enabled"
    ORDER BY s2."sort_order" DESC, s2."required_realm_order" DESC, s2."slug" DESC LIMIT 1
  )) AS stage_slug
  FROM "content_chapters" c
),
elite AS (
  SELECT
    s."slug",
    '精英·' || (s."monsters" -> 0 ->> 'name') AS name,
    round((s."monsters" -> 0 ->> 'attack')::numeric * 1.3) AS attack,
    round((s."monsters" -> 0 ->> 'defense')::numeric * 1.2) AS defense,
    round((s."monsters" -> 0 ->> 'hp')::numeric * 5) AS hp,
    (s."monsters" -> 0 ->> 'interval')::numeric AS "interval",
    (50 * power(3, greatest(0, (s."required_realm_order" - 1) / 3)))::int AS stones
  FROM "content_stages" s
  WHERE s."bosses" = '[]'::jsonb
    AND jsonb_typeof(s."monsters") = 'array' AND jsonb_array_length(s."monsters") > 0
    AND s."chapter_slug" IS NOT NULL
    AND s."slug" NOT IN (SELECT stage_slug FROM chief WHERE stage_slug IS NOT NULL)
)
UPDATE "content_stages" AS s
SET
  "bosses" = jsonb_build_array(jsonb_build_object(
    'name', e.name,
    'attack', e.attack,
    'defense', e.defense,
    'hp', e.hp,
    'interval', e."interval",
    'drops', '[]'::jsonb,
    'firstClear',
      jsonb_build_array(jsonb_build_object('kind', 'spiritStones', 'amount', e.stones))
      || CASE WHEN EXISTS (SELECT 1 FROM "content_items" WHERE "slug" = 'enh_stone_low')
           THEN jsonb_build_array(jsonb_build_object('kind', 'item', 'itemSlug', 'enh_stone_low', 'quantity', 1))
           ELSE '[]'::jsonb END
      || jsonb_build_array(jsonb_build_object('kind', 'gear', 'count', 1))
  )),
  "boss_name" = e.name,
  "boss_attack" = e.attack,
  "boss_defense" = e.defense,
  "boss_hp" = e.hp,
  "boss_interval" = e."interval",
  "updated_at" = now()
FROM elite e
WHERE s."slug" = e."slug";
--> statement-breakpoint
ALTER TABLE "player_stage_progress" ADD COLUMN IF NOT EXISTS "auto_challenge_at" timestamp with time zone;
