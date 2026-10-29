-- 技能表现字段 + 9 条默认可玩技能。迁移号 0062。可以重复执行。
-- fx_type 写资源真名。客户端缺资源才降级，这里不写降级类型。
-- 释放只有 auto / passive。不播种手动释放。
ALTER TABLE "content_skills" ADD COLUMN IF NOT EXISTS "fx_type" text;
--> statement-breakpoint
ALTER TABLE "content_skills" ADD COLUMN IF NOT EXISTS "fx" jsonb;
--> statement-breakpoint
ALTER TABLE "content_skills" ADD COLUMN IF NOT EXISTS "cast_mode" text DEFAULT 'auto';
--> statement-breakpoint
UPDATE "content_skills" SET "cast_mode" = 'auto' WHERE "cast_mode" IS NULL;
--> statement-breakpoint
ALTER TABLE "content_skills" ALTER COLUMN "cast_mode" SET DEFAULT 'auto';
--> statement-breakpoint
ALTER TABLE "content_skills" ALTER COLUMN "cast_mode" SET NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_skills" DROP CONSTRAINT IF EXISTS "content_skills_fx_type_check";
--> statement-breakpoint
ALTER TABLE "content_skills" ADD CONSTRAINT "content_skills_fx_type_check" CHECK (
  "fx_type" IS NULL OR "fx_type" IN (
    'slash', 'thunder', 'fire', 'heal_circle', 'ice', 'wind', 'poison', 'gold_light', 'shield'
  )
);
--> statement-breakpoint
ALTER TABLE "content_skills" DROP CONSTRAINT IF EXISTS "content_skills_cast_mode_check";
--> statement-breakpoint
ALTER TABLE "content_skills" ADD CONSTRAINT "content_skills_cast_mode_check" CHECK ("cast_mode" IN ('auto', 'passive'));
--> statement-breakpoint
INSERT INTO "content_skill_categories" ("slug", "display_name")
SELECT 'cat_heart', '心法'
WHERE NOT EXISTS (
  SELECT 1 FROM "content_skill_categories" WHERE "slug" = 'cat_heart' OR "display_name" = '心法'
);
--> statement-breakpoint
INSERT INTO "content_skills" (
  "slug", "display_name", "description", "role", "rank",
  "attack", "defense", "hp", "cultivate_bonus_bp",
  "skill_category_slug", "fx_type", "fx", "cast_mode", "prerequisite_skill_slugs", "enabled"
)
SELECT
  v.slug, v.display_name, v.description, v.role, v.rank,
  v.attack, v.defense, v.hp, v.cultivate_bonus_bp,
  (SELECT "slug" FROM "content_skill_categories" WHERE "display_name" = '心法' ORDER BY "slug" LIMIT 1),
  v.fx_type, v.fx::jsonb, v.cast_mode, '[]'::jsonb, true
FROM (
  VALUES
    ('skill_tuna', '吐纳诀', '调息回气，修炼时持续恢复。', 'heart', 'yellow', 0, 0, 0, 500, 'heal_circle', '{"type":"heal_circle","primary":"#5EE1C5","secondary":"#FFE27A","scale":1}', 'passive'),
    ('skill_qingyuan', '青元诀', '青元流转，加快修炼。', 'heart', 'xuan', 0, 0, 0, 1500, 'wind', '{"type":"wind","primary":"#D8F5C8","secondary":"#5CB85C","scale":1}', 'auto'),
    ('skill_zifu', '紫府金章', '紫府金光护持心神。', 'heart', 'earth', 0, 0, 0, 3000, 'gold_light', '{"type":"gold_light","primary":"#FFD45C","secondary":"#FFE9A0","scale":1}', 'auto'),
    ('skill_liekong', '裂空斩', '近身斩击。', 'attack', 'yellow', 800, 0, 0, 0, 'slash', '{"type":"slash","primary":"#F5FBFF","secondary":"#A8E8E0","scale":1}', 'auto'),
    ('skill_leiting', '雷霆诀', '落雷轰击。', 'attack', 'yellow', 800, 0, 0, 0, 'thunder', '{"type":"thunder","primary":"#E8D6FF","secondary":"#7B4DFF","scale":1}', 'auto'),
    ('skill_chiyan', '赤炎掌', '掌心吐炎。', 'attack', 'xuan', 1000, 0, 0, 0, 'fire', '{"type":"fire","primary":"#FF9F43","secondary":"#E85D4C","scale":1}', 'auto'),
    ('skill_hanbing', '寒冰刺', '冰晶刺击。', 'attack', 'yellow', 800, 0, 0, 0, 'ice', '{"type":"ice","primary":"#B9F3FF","secondary":"#3D8BFF","scale":1}', 'auto'),
    ('skill_duwu', '毒雾术', '毒雾缠身。', 'attack', 'yellow', 600, 0, 0, 0, 'poison', '{"type":"poison","primary":"#7DDE6A","secondary":"#6B3FA0","scale":1}', 'auto'),
    ('skill_huti', '护体罡气', '罡气护体，提高防御。', 'body', 'yellow', 0, 800, 0, 0, 'shield', '{"type":"shield","primary":"#FFF8EC","secondary":"#E8C872","scale":1}', 'passive')
) AS v(slug, display_name, description, role, rank, attack, defense, hp, cultivate_bonus_bp, fx_type, fx, cast_mode)
ON CONFLICT ("slug") DO UPDATE SET
  "fx_type" = COALESCE("content_skills"."fx_type", EXCLUDED."fx_type"),
  "fx" = CASE WHEN "content_skills"."fx_type" IS NULL THEN EXCLUDED."fx" ELSE "content_skills"."fx" END,
  "cast_mode" = CASE WHEN "content_skills"."fx_type" IS NULL THEN EXCLUDED."cast_mode" ELSE "content_skills"."cast_mode" END,
  "skill_category_slug" = COALESCE(NULLIF("content_skills"."skill_category_slug", ''), EXCLUDED."skill_category_slug"),
  "description" = CASE WHEN "content_skills"."description" = '' THEN EXCLUDED."description" ELSE "content_skills"."description" END;
--> statement-breakpoint
INSERT INTO "content_items" ("slug", "display_name", "description", "kind", "quality", "stackable", "skill_slug", "icon_key")
SELECT
  'book_' || s."slug",
  s."display_name" || '技能书',
  '使用后学会技能「' || s."display_name" || '」；已学会时每用一本提升一层（最多 7 层），满层后再使用会转为修为。',
  'skill_book',
  'white',
  false,
  s."slug",
  'book_other'
FROM "content_skills" AS s
WHERE s."slug" IN (
  'skill_tuna', 'skill_qingyuan', 'skill_zifu', 'skill_liekong', 'skill_leiting',
  'skill_chiyan', 'skill_hanbing', 'skill_duwu', 'skill_huti'
)
AND NOT EXISTS (
  SELECT 1 FROM "content_items" AS i WHERE i."skill_slug" = s."slug" AND i."kind" = 'skill_book'
);
--> statement-breakpoint
UPDATE "content_items"
SET "description" = replace("description", '学会功法「', '学会技能「')
WHERE "kind" = 'skill_book' AND "description" LIKE '使用后学会功法「%';
