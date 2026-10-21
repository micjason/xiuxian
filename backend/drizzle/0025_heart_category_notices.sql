-- 批次①：
-- 1) 新建「心法」功法分类，把还没有分类的功法（线上是吐纳诀、青元诀、紫府金章三门心法）归进去，后台才能保存它们。
-- 2) 去掉 60 秒「收益」弹窗（客户端从来没接，离线收益由「闭关归来」弹窗负责）：删掉弹窗类型和已经攒下的收益通知。
INSERT INTO "content_skill_categories" ("slug", "display_name")
SELECT 'cat_heart', '心法'
WHERE NOT EXISTS (SELECT 1 FROM "content_skill_categories" WHERE "display_name" = '心法');
--> statement-breakpoint
UPDATE "content_skills"
SET "skill_category_slug" = (SELECT "slug" FROM "content_skill_categories" WHERE "display_name" = '心法' ORDER BY "slug" LIMIT 1),
    "updated_at" = now()
WHERE ("skill_category_slug" IS NULL OR "skill_category_slug" = '')
  AND ("role" = 'heart' OR "role" IS NULL);
--> statement-breakpoint
DELETE FROM "player_notices" WHERE "type" = 'income';
--> statement-breakpoint
DELETE FROM "popup_types" WHERE "slug" = 'income';
