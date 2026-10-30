-- 离线战利品清单：挂机掉落表 + 满包跳过标记。迁移号 0064。可重复执行。
ALTER TABLE "player_offline_reports" ADD COLUMN IF NOT EXISTS "loot" jsonb DEFAULT '[]'::jsonb;
--> statement-breakpoint
ALTER TABLE "player_offline_reports" ADD COLUMN IF NOT EXISTS "bag_full_skipped" boolean DEFAULT false;
--> statement-breakpoint
UPDATE "player_offline_reports" SET "loot" = '[]'::jsonb WHERE "loot" IS NULL;
--> statement-breakpoint
UPDATE "player_offline_reports" SET "bag_full_skipped" = false WHERE "bag_full_skipped" IS NULL;
--> statement-breakpoint
ALTER TABLE "player_offline_reports" ALTER COLUMN "loot" SET DEFAULT '[]'::jsonb;
--> statement-breakpoint
ALTER TABLE "player_offline_reports" ALTER COLUMN "bag_full_skipped" SET DEFAULT false;
--> statement-breakpoint
ALTER TABLE "player_offline_reports" ALTER COLUMN "loot" SET NOT NULL;
--> statement-breakpoint
ALTER TABLE "player_offline_reports" ALTER COLUMN "bag_full_skipped" SET NOT NULL;
