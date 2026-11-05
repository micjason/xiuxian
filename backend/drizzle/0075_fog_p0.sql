-- 迷雾秘境 P0：player_fog_runs + content_globals.fog 问心谷（对齐 FOG_LEVEL_DESIGN / level_objects.json）。
-- 迁移号 0075；when 1801500000000。
-- 坐标：pos_c=x，pos_r=y；左上 (0,0)。

CREATE TABLE IF NOT EXISTS "player_fog_runs" (
  "player_id" uuid NOT NULL REFERENCES "players"("id") ON DELETE CASCADE,
  "map_id" text NOT NULL,
  "pos_r" integer NOT NULL DEFAULT 0,
  "pos_c" integer NOT NULL DEFAULT 0,
  "revealed" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "objects" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "travel_points" integer NOT NULL DEFAULT 0,
  "travel_day" text,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "player_fog_runs_pk" PRIMARY KEY ("player_id", "map_id"),
  CONSTRAINT "player_fog_runs_travel_nonneg" CHECK ("travel_points" >= 0)
);
--> statement-breakpoint

ALTER TABLE "content_globals" ADD COLUMN IF NOT EXISTS "fog" jsonb;
--> statement-breakpoint

UPDATE "content_globals"
SET "fog" = COALESCE("fog", '{
  "travelPointsMax": 20,
  "travelCostPerStep": 1,
  "revealRadius": 1,
  "initialReveal": 1,
  "defaultMapId": "fog_wenxin_valley",
  "maps": [{
    "id": "fog_wenxin_valley",
    "displayName": "问心谷",
    "rows": 12,
    "cols": 8,
    "spawn": {"x": 3, "y": 10},
    "blocks": [
      {"x": 0, "y": 2}, {"x": 0, "y": 3}, {"x": 0, "y": 4}, {"x": 0, "y": 5}, {"x": 1, "y": 3}, {"x": 1, "y": 4},
      {"x": 2, "y": 0}, {"x": 3, "y": 0}, {"x": 5, "y": 0}, {"x": 6, "y": 0},
      {"x": 2, "y": 5}, {"x": 5, "y": 4},
      {"x": 6, "y": 6}, {"x": 6, "y": 8}, {"x": 7, "y": 5}, {"x": 7, "y": 6}, {"x": 7, "y": 7}
    ],
    "objects": [
      {"id": "m_slime", "kind": "monster", "x": 2, "y": 8, "name": "浊气小妖", "attack": 6, "defense": 1, "hp": 30, "interval": 1.6, "loot": [{"itemSlug": "herb_lingcao", "quantity": 1}]},
      {"id": "m_wolf", "kind": "monster", "x": 5, "y": 6, "name": "影狼", "attack": 12, "defense": 4, "hp": 70, "interval": 1.4, "loot": [{"itemSlug": "herb_qingxin", "quantity": 1}]},
      {"id": "m_guard", "kind": "monster", "x": 4, "y": 1, "name": "谷口护卫", "attack": 18, "defense": 6, "hp": 100, "interval": 1.3, "loot": [{"itemSlug": "herb_lingcao", "quantity": 2}, {"itemSlug": "herb_qingxin", "quantity": 1}]},
      {"id": "c_near", "kind": "chest", "x": 4, "y": 9, "loot": [{"itemSlug": "herb_lingcao", "quantity": 3}]},
      {"id": "c_mid", "kind": "chest", "x": 1, "y": 6, "loot": [{"itemSlug": "herb_lingcao", "quantity": 5}]},
      {"id": "c_high", "kind": "chest", "x": 6, "y": 3, "loot": [], "grantSkillBook": true},
      {"id": "e_herb", "kind": "event", "x": 3, "y": 4, "title": "仙草争执", "options": [{"id": "A", "label": "上前理论", "effect": "battle", "enemyId": "temp_herbalist"}, {"id": "B", "label": "转身离开", "effect": "none"}], "battleEnemy": {"name": "采药修士", "attack": 10, "defense": 3, "hp": 50, "interval": 1.5, "loot": [{"itemSlug": "herb_qingxin", "quantity": 2}]}}
    ]
  }]
}'::jsonb)
WHERE "id" = 1;
