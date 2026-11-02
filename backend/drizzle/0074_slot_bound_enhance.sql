-- 部位强化：强化等级绑格子（武器/衣服等），不绑装备胚子。
-- 换下归 0、不返还该次投入的精粹；空格子保留部位等级。去掉玩法上限与突破材料（只吃炼器精粹、必成功）。
-- 迁移号 0074（避开并行 #60 的 0073）；when 1801400000000。

CREATE TABLE IF NOT EXISTS "player_slot_enhances" (
  "player_id" uuid NOT NULL REFERENCES "players"("id") ON DELETE CASCADE,
  "slot" text NOT NULL,
  "enhance_level" integer NOT NULL DEFAULT 0,
  CONSTRAINT "player_slot_enhances_pk" PRIMARY KEY ("player_id", "slot"),
  CONSTRAINT "player_slot_enhances_level_nonneg" CHECK ("enhance_level" >= 0)
);
--> statement-breakpoint

-- 已穿戴装备的强化等级迁到对应部位；背包里残留强化清零（部位强化后胚子不带等级，避免换装刷返还）。
INSERT INTO "player_slot_enhances" ("player_id", "slot", "enhance_level")
SELECT "player_id", "equipped_slot", "enhance_level"
FROM "player_items"
WHERE "equipped_slot" IS NOT NULL AND "enhance_level" > 0
ON CONFLICT ("player_id", "slot") DO UPDATE
SET "enhance_level" = GREATEST("player_slot_enhances"."enhance_level", EXCLUDED."enhance_level");
--> statement-breakpoint

UPDATE "player_items" SET "enhance_level" = 0, "break_level" = 0;
--> statement-breakpoint

-- 精粹消耗拉陡：costGrowth 1.25 → 1.4；品质突破节点清空；上限抬到 200（玩法侧已无上限，仅防填错）。
UPDATE "content_globals"
SET "enhance" = jsonb_set(
  jsonb_set(
    jsonb_set(
      COALESCE("enhance", '{}'::jsonb),
      '{essence,costGrowth}',
      '1.4'::jsonb,
      true
    ),
    '{slotBound}',
    'true'::jsonb,
    true
  ),
  '{qualities}',
  (
    SELECT COALESCE(jsonb_object_agg(q.key, q.val), '{}'::jsonb)
    FROM (
      SELECT
        key,
        (value - 'breakthroughs')
          || jsonb_build_object('breakthroughs', '[]'::jsonb)
        AS val
      FROM jsonb_each(COALESCE("enhance"->'qualities', '{}'::jsonb))
    ) q
  ),
  true
)
WHERE "id" = 1;
