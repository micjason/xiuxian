-- 阵法每日小游戏（灵脉接引）最小切片：物品 array_shard + globals.dongfu.arrayDaily + 玩家 array_xp/日清。
-- 迁移号 0069；when 1800900000000。可重复执行。
INSERT INTO "content_items" ("slug", "display_name", "description", "kind", "quality", "stackable", "icon_key")
VALUES
  ('array_shard', '阵纹残片', '阵法日游产出。本切片仅入包，阵室升级后消耗。', 'material', 'blue', true, 'array_shard')
ON CONFLICT ("slug") DO NOTHING;
--> statement-breakpoint
UPDATE "content_globals"
SET "dongfu" = "dongfu" || '{
  "arrayDaily": {
    "enabled": true,
    "gridSize": 3,
    "rewardXp": 10,
    "rewardShardItemSlug": "array_shard",
    "rewardShardQty": 2,
    "puzzles": [
      {
        "puzzleId": "vein_01",
        "source": {"r": 0, "c": 0, "open": "E"},
        "sink": {"r": 2, "c": 2, "open": "W"},
        "tiles": [
          {"r": 0, "c": 1, "shape": "I", "rot": 0},
          {"r": 0, "c": 2, "shape": "L", "rot": 1},
          {"r": 1, "c": 0, "shape": "L", "rot": 0},
          {"r": 1, "c": 1, "shape": "I", "rot": 1},
          {"r": 1, "c": 2, "shape": "L", "rot": 2},
          {"r": 2, "c": 0, "shape": "L", "rot": 3},
          {"r": 2, "c": 1, "shape": "I", "rot": 0}
        ]
      },
      {
        "puzzleId": "vein_02",
        "source": {"r": 0, "c": 2, "open": "S"},
        "sink": {"r": 2, "c": 0, "open": "E"},
        "tiles": [
          {"r": 0, "c": 0, "shape": "I", "rot": 1},
          {"r": 0, "c": 1, "shape": "L", "rot": 0},
          {"r": 1, "c": 0, "shape": "L", "rot": 3},
          {"r": 1, "c": 1, "shape": "L", "rot": 3},
          {"r": 1, "c": 2, "shape": "I", "rot": 1},
          {"r": 2, "c": 1, "shape": "I", "rot": 3},
          {"r": 2, "c": 2, "shape": "L", "rot": 2}
        ]
      },
      {
        "puzzleId": "vein_03",
        "source": {"r": 1, "c": 0, "open": "E"},
        "sink": {"r": 1, "c": 2, "open": "W"},
        "tiles": [
          {"r": 0, "c": 0, "shape": "L", "rot": 2},
          {"r": 0, "c": 1, "shape": "I", "rot": 3},
          {"r": 0, "c": 2, "shape": "L", "rot": 1},
          {"r": 1, "c": 1, "shape": "I", "rot": 0},
          {"r": 2, "c": 0, "shape": "I", "rot": 1},
          {"r": 2, "c": 1, "shape": "L", "rot": 2},
          {"r": 2, "c": 2, "shape": "L", "rot": 2}
        ]
      }
    ]
  }
}'::jsonb,
"updated_at" = now()
WHERE "dongfu" IS NOT NULL
  AND jsonb_typeof("dongfu") = 'object'
  AND NOT ("dongfu" ? 'arrayDaily');
--> statement-breakpoint
ALTER TABLE "player_dongfu" ADD COLUMN IF NOT EXISTS "array_xp" integer NOT NULL DEFAULT 0;
--> statement-breakpoint
ALTER TABLE "player_dongfu" ADD COLUMN IF NOT EXISTS "last_clear_day" text;
--> statement-breakpoint
ALTER TABLE "player_dongfu" ADD COLUMN IF NOT EXISTS "last_puzzle_id" text;
