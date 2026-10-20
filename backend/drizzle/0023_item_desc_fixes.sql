-- 2026-10-20（负责人 / 美术 SPEC_Q 13.12）：物品说明两处文案修正，只改 description 一个字段，可重复执行。
-- 1) 突破石（迁移 0017 写入）说明末尾的“（起始值，可在后台修改）”是给后台看的提示，玩家在物品详情里会看到 → 去掉。
--    只处理仍以这句结尾的行；后台改过说明的不动。
UPDATE "content_items"
SET "description" = left("description", length("description") - length('（起始值，可在后台修改）'))
WHERE "description" LIKE '%（起始值，可在后台修改）';
--> statement-breakpoint
-- 2) 功法书说明原来是空的 → 按功法名写一句说明（与服务器 useItem 规则一致：学会 / 升一层，最多 7 层，满层转修为）。
--    只填还是空的；后台写过说明的不动。
UPDATE "content_items" AS i
SET "description" = '使用后学会功法「' || s."display_name" || '」；已学会时每用一本提升一层（最多 7 层），满层后再使用会转为修为。'
FROM "content_skills" AS s
WHERE i."kind" = 'skill_book' AND i."skill_slug" = s."slug" AND coalesce(btrim(i."description"), '') = '' AND coalesce(btrim(s."display_name"), '') <> '';
