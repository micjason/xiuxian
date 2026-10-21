-- 第三批补丁（2026-10-21）：小首领（精英）的立绘写明。
-- 0041 补出来的精英没写 artKey（快照里按「跟随本关普通怪」补上，所以游戏里有图），但后台首领区显示成「没配图」。
-- 这里把非章末关、首领还没 artKey 的，写成本关第一只普通怪的 artKey（客户端按 tier 用 elite_<key> 金边图 / shader）。
-- 章末关的大首领不动；普通怪也没立绘的不动（发布校验会报）。可以重复执行。
WITH chief AS (
  SELECT COALESCE(c."chief_stage_slug", (
    SELECT s2."slug" FROM "content_stages" s2
    WHERE s2."chapter_slug" = c."slug" AND s2."enabled"
    ORDER BY s2."sort_order" DESC, s2."required_realm_order" DESC, s2."slug" DESC LIMIT 1
  )) AS stage_slug
  FROM "content_chapters" c
)
UPDATE "content_stages" AS s
SET "bosses" = jsonb_set(s."bosses", '{0,artKey}', s."monsters" -> 0 -> 'artKey')
WHERE jsonb_typeof(s."bosses") = 'array' AND jsonb_array_length(s."bosses") > 0
  AND COALESCE(s."bosses" -> 0 ->> 'artKey', '') = ''
  AND jsonb_typeof(s."monsters") = 'array' AND jsonb_array_length(s."monsters") > 0
  AND COALESCE(s."monsters" -> 0 ->> 'artKey', '') <> ''
  AND s."chapter_slug" IS NOT NULL
  AND s."slug" NOT IN (SELECT stage_slug FROM chief WHERE stage_slug IS NOT NULL);
