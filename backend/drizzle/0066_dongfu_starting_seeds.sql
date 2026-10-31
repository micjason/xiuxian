-- 洞府 P0：初始种子包 + 极简兑种配置；player_dongfu.seeds_granted。可重复执行。
ALTER TABLE "player_dongfu" ADD COLUMN IF NOT EXISTS "seeds_granted" boolean NOT NULL DEFAULT false;
--> statement-breakpoint
UPDATE "content_globals"
SET "dongfu" = "dongfu" || '{
  "startingSeeds": [
    {"itemSlug": "seed_lingcao", "quantity": 8},
    {"itemSlug": "seed_qingxin", "quantity": 4}
  ],
  "seedOffers": [
    {"seedSlug": "seed_lingcao", "spiritStones": 10, "quantity": 1},
    {"seedSlug": "seed_qingxin", "spiritStones": 20, "quantity": 1}
  ]
}'::jsonb,
"updated_at" = now()
WHERE "dongfu" IS NOT NULL
  AND jsonb_typeof("dongfu") = 'object'
  AND NOT ("dongfu" ? 'startingSeeds');
