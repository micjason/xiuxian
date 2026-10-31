-- P1 洞府配表铺垫：试炼/灵气/万年全局字段默认值 + 玩家态列。
-- 不实现 trial/hasten/aura 业务；旧 recipes 缺 discoverMode 由解析器默认 starter。
-- 迁移号 0067（0066 留给洞府 P0 startingSeeds）。可重复执行。
UPDATE "content_globals"
SET "dongfu" = "dongfu" || '{
  "alchemyTrialSlotCount": 3,
  "alchemyTrialDailyLimit": 20,
  "alchemyTrialExtraCostLingshi": 50,
  "alchemyTrialExtraMax": 2,
  "alchemyTrialFailXp": 1,
  "alchemyTrialImperfectXp": 3,
  "alchemyTrialPerfectXp": 10,
  "alchemyHintKeys": ["clash", "missing_main", "ratio_off", "near"],
  "gardenAuraMax": 5,
  "gardenAuraMatureBpPerPoint": 500,
  "gardenAuraYieldBpPerPoint": 0,
  "gardenHastenLingshiPerHourLeft": 20,
  "gardenHastenItemSlug": null,
  "gardenAgeToAncientSeconds": 86400,
  "auraSources": []
}'::jsonb,
"updated_at" = now()
WHERE "dongfu" IS NOT NULL
  AND jsonb_typeof("dongfu") = 'object'
  AND NOT ("dongfu" ? 'alchemyTrialSlotCount');
--> statement-breakpoint
ALTER TABLE "player_dongfu_plots" ADD COLUMN IF NOT EXISTS "aura" integer NOT NULL DEFAULT 0;
--> statement-breakpoint
ALTER TABLE "player_dongfu_plots" ADD COLUMN IF NOT EXISTS "ancient_at" timestamp with time zone;
--> statement-breakpoint
ALTER TABLE "player_dongfu" ADD COLUMN IF NOT EXISTS "discovered_recipe_slugs" jsonb NOT NULL DEFAULT '[]'::jsonb;
--> statement-breakpoint
ALTER TABLE "player_dongfu" ADD COLUMN IF NOT EXISTS "trial_used_on_day" jsonb;
--> statement-breakpoint
ALTER TABLE "player_dongfu" ADD COLUMN IF NOT EXISTS "alchemy_xp" integer NOT NULL DEFAULT 0;
