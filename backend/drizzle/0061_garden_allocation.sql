-- 药园分配 v1：灵仆分配 + 设施升级。迁移号 0061（队友用 0062+）。可以重复执行。
-- 1) 灵木物品（已有同编号不覆盖）。
-- 2) content_globals.dongfu 补分配系数 / 升级表（已有 gardenUpgrades 的不覆盖）。
-- 3) 关卡掉落管线追加灵木（tuning.seedDrops 里还没有才追加）。
-- 4) player_dongfu：灵仆总数、分配、药园/炼丹等级。初始灵木由服务端首次进入时按 globals 发放。
INSERT INTO "content_items" ("slug", "display_name", "description", "kind", "quality", "stackable", "icon_key")
VALUES
  ('wood_lingmu', '灵木', '洞府设施升级材料。药园加地块，炼丹加队列。', 'material', 'green', true, 'wood_lingmu')
ON CONFLICT ("slug") DO NOTHING;
--> statement-breakpoint
UPDATE "content_globals"
SET "dongfu" = "dongfu" || '{
  "woodItemSlug": "wood_lingmu",
  "startingWood": 32,
  "startingServants": 4,
  "gardenReducePercent": 5,
  "alchemyReducePercent": 5,
  "minDurationPercent": 20,
  "maxPlotCount": 12,
  "maxAlchemyQueue": 4,
  "gardenUpgrades": [
    {"toLevel": 2, "wood": 8, "spiritStones": 0, "bonus": 1},
    {"toLevel": 3, "wood": 16, "spiritStones": 0, "bonus": 1},
    {"toLevel": 4, "wood": 32, "spiritStones": 20, "bonus": 1}
  ],
  "alchemyUpgrades": [
    {"toLevel": 2, "wood": 8, "spiritStones": 0, "bonus": 1},
    {"toLevel": 3, "wood": 16, "spiritStones": 0, "bonus": 1}
  ]
}'::jsonb,
"updated_at" = now()
WHERE "dongfu" IS NOT NULL
  AND jsonb_typeof("dongfu") = 'object'
  AND NOT ("dongfu" ? 'gardenUpgrades');
--> statement-breakpoint
UPDATE "content_globals"
SET "tuning" = jsonb_set(
  "tuning",
  '{seedDrops}',
  ("tuning"->'seedDrops') || '[{"itemSlug":"wood_lingmu","chanceBp":600,"minCount":1,"maxCount":1}]'::jsonb
),
"updated_at" = now()
WHERE jsonb_typeof("tuning") = 'object'
  AND jsonb_typeof("tuning"->'seedDrops') = 'array'
  AND NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements("tuning"->'seedDrops') AS elem
    WHERE elem->>'itemSlug' = 'wood_lingmu'
  );
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "player_dongfu" (
  "player_id" uuid PRIMARY KEY REFERENCES "players"("id") ON DELETE CASCADE,
  "servant_total" integer NOT NULL,
  "garden_allocation" integer NOT NULL DEFAULT 0,
  "alchemy_allocation" integer NOT NULL DEFAULT 0,
  "garden_level" integer NOT NULL DEFAULT 1,
  "alchemy_level" integer NOT NULL DEFAULT 1,
  "wood_granted" boolean NOT NULL DEFAULT false
);
