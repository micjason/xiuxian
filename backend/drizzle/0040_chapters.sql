-- 第三批（2026-10-21）：正式的章节配置。
-- 1) 新表 content_chapters：名称、排序、战斗区背景 bg_key、章节首领特效 boss_fx（default | chiyan）、
--    可选的章末关 chief_stage_slug（null = 自动取本章 sort_order 最大的一关）。
-- 2) content_stages.chapter_slug：关卡所属章节。
-- 3) 按现有关卡名「·」前面的部分建出黑风岭 / 幽冥古道 / 赤炎火山 3 章并回填；名字对不上的关卡保持没有章节（发布校验会报错）。
-- 4) 关卡 sort_order 是 0 的（后台保存过的老数据）按所需境界补上，章末 =「sort_order 最大」才有意义。
-- 可以重复执行。
CREATE TABLE IF NOT EXISTS "content_chapters" (
  "slug" text PRIMARY KEY NOT NULL,
  "display_name" text NOT NULL,
  "sort_order" integer DEFAULT 0 NOT NULL,
  "bg_key" text NOT NULL,
  "boss_fx" text DEFAULT 'default' NOT NULL,
  "chief_stage_slug" text,
  "enabled" boolean DEFAULT true NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_by" uuid
);
--> statement-breakpoint
ALTER TABLE "content_stages" ADD COLUMN IF NOT EXISTS "chapter_slug" text;
--> statement-breakpoint
INSERT INTO "content_chapters" ("slug", "display_name", "sort_order", "bg_key", "boss_fx")
SELECT v.slug, v.name, v.ord, v.bg, v.fx
FROM (VALUES
  ('heifeng', '黑风岭', 1, 'heifeng', 'default'),
  ('youming', '幽冥古道', 2, 'youming', 'default'),
  ('chiyan', '赤炎火山', 3, 'chiyan', 'chiyan')
) AS v(slug, name, ord, bg, fx)
WHERE EXISTS (SELECT 1 FROM "content_stages" s WHERE split_part(s."display_name", '·', 1) = v.name)
ON CONFLICT ("slug") DO NOTHING;
--> statement-breakpoint
UPDATE "content_stages" AS s
SET "chapter_slug" = c."slug"
FROM "content_chapters" AS c
WHERE s."chapter_slug" IS NULL AND split_part(s."display_name", '·', 1) = c."display_name";
--> statement-breakpoint
UPDATE "content_stages" SET "sort_order" = "required_realm_order" WHERE "sort_order" = 0;
