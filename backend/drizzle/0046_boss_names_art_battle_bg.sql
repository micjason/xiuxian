-- 第四批（2026-10-21）：首领默认名字 + 统一首领立绘 + 章节战斗背景。可以重复执行。
-- 1) content_chapters.battle_bg_key：首领战斗页背景（竖版 1080×1640，SPEC_Q §17.8）；空 = 跟随 bg_key。已有章节按 bg_key 回填。
-- 2) 第 1、2 关首领改成策划定的名字：只改「名字还是 0041 / 种子写的默认名（精英·<小怪>）」的首领，后台改过名字的不动。
-- 3) 首领立绘改成统一首领立绘 boss_<怪>（SPEC_Q §17.10）：只改「artKey 还是 0041 / 0044 / 种子写的默认值」的首领
--    （按关卡 + 旧值匹配），后台换过立绘的不动。
ALTER TABLE "content_chapters" ADD COLUMN IF NOT EXISTS "battle_bg_key" text;
--> statement-breakpoint
UPDATE "content_chapters"
SET "battle_bg_key" = "bg_key", "updated_at" = now()
WHERE "battle_bg_key" IS NULL AND "bg_key" IN ('heifeng', 'youming', 'chiyan');
--> statement-breakpoint
UPDATE "content_stages" AS s
SET
  "bosses" = jsonb_set(s."bosses", '{0,name}', to_jsonb(n.new_name)),
  "boss_name" = CASE WHEN s."boss_name" = n.old_name THEN n.new_name ELSE s."boss_name" END,
  "updated_at" = now()
FROM (VALUES
  ('精英·青鬃狼', '青鬃狼王'), ('精英·赤眼狐妖', '赤眼妖狐'),
  ('精英·游魂', '游魂统领'), ('精英·骨傀', '白骨傀将'),
  ('精英·炎鳞蜥', '炎鳞蜥皇'), ('精英·火鸦', '焚天火鸦')
) AS n(old_name, new_name)
WHERE jsonb_typeof(s."bosses") = 'array' AND jsonb_array_length(s."bosses") > 0
  AND s."bosses" -> 0 ->> 'name' = n.old_name;
--> statement-breakpoint
UPDATE "content_stages" AS s
SET "bosses" = jsonb_set(s."bosses", '{0,artKey}', to_jsonb(a.new_key)), "updated_at" = now()
FROM (VALUES
  ('lianqi_1', 'wolf', 'boss_wolf'), ('lianqi_2', 'fox', 'boss_fox'), ('lianqi_3', 'bear', 'boss_bear'),
  ('zhuji_1', 'ghost', 'boss_ghost'), ('zhuji_2', 'bone_golem', 'boss_bone_golem'), ('zhuji_3', 'ghost_elder', 'boss_ghost_elder'),
  ('jindan_1', 'lava_lizard', 'boss_lava_lizard'), ('jindan_2', 'fire_crow', 'boss_fire_crow'), ('jindan_3', 'fire_jiao', 'boss_fire_jiao')
) AS a(slug, old_key, new_key)
WHERE s."slug" = a.slug
  AND jsonb_typeof(s."bosses") = 'array' AND jsonb_array_length(s."bosses") > 0
  AND s."bosses" -> 0 ->> 'artKey' = a.old_key;
