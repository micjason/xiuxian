-- 洞府摸索试炼 + 傀儡上工灵石：全局默认补字段；隐藏丹方写入出厂 recipes（若尚未含）。
-- 可重复执行。
UPDATE "content_globals"
SET "dongfu" = "dongfu" || '{"servantAssignLingshi": 5}'::jsonb,
"updated_at" = now()
WHERE "dongfu" IS NOT NULL
  AND jsonb_typeof("dongfu") = 'object'
  AND NOT ("dongfu" ? 'servantAssignLingshi');
