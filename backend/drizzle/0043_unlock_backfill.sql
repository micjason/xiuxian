-- 第三批（2026-10-21）：解锁改成「击败上一关首领 + 境界达到」。以前只看境界，所以按境界给老玩家补齐解锁记录：
-- 每个玩家，所需境界 ≤ 当前境界的启用关卡都写一行 player_stage_progress（已经有的不动），原来能刷的关卡不会被锁掉。
-- 小首领的首通不补记（回头打还能拿首通奖励）；大首领已有的首通、次数、每日奖励原样保留。
-- 可以重复执行。
INSERT INTO "player_stage_progress" ("player_id", "stage_slug", "unlocked_at")
SELECT ps."player_id", s."slug", now()
FROM "player_states" ps
JOIN "content_realms" r ON r."slug" = ps."realm_slug"
JOIN "content_stages" s ON s."enabled" AND s."required_realm_order" <= r."sort_order"
ON CONFLICT ("player_id", "stage_slug") DO NOTHING;
