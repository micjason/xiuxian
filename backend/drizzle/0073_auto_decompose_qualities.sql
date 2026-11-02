-- 挂机自动分解按品质勾选（每玩家）：白/绿/蓝默认勾上，紫/橙默认不勾。
-- 掉落时品质在列表里 → 立刻拆成炼器精粹，不进包。可重复执行。
-- 迁移号 0073；when 1801300000000。
ALTER TABLE "player_states" ADD COLUMN IF NOT EXISTS "auto_decompose_qualities" jsonb DEFAULT '["white","green","blue"]'::jsonb NOT NULL;
--> statement-breakpoint
UPDATE "player_states" SET "auto_decompose_qualities" = '["white","green","blue"]'::jsonb WHERE "auto_decompose_qualities" IS NULL;
