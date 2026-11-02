-- 洞府大改：傀儡产线仓内状态 + 炼器队列；补充灵肉/灵石材物品；grant 来源加 dongfu_forge。
-- 假设可丢弃旧洞府进度；puppet_state 缺省时读 state 按配置初始化。

ALTER TABLE "player_dongfu"
  ADD COLUMN IF NOT EXISTS "puppet_state" jsonb,
  ADD COLUMN IF NOT EXISTS "forge_xp" integer NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS "player_dongfu_forge" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "player_id" uuid NOT NULL REFERENCES "players"("id") ON DELETE CASCADE,
  "blueprint_slug" text NOT NULL,
  "started_at" timestamp with time zone NOT NULL,
  "ready_at" timestamp with time zone NOT NULL,
  "claimed_at" timestamp with time zone,
  "rolled_quality" text,
  "output_item_slug" text
);

CREATE INDEX IF NOT EXISTS "player_dongfu_forge_player_idx" ON "player_dongfu_forge" ("player_id");

INSERT INTO "content_items" ("slug", "display_name", "description", "kind", "quality", "stackable", "icon_key")
VALUES
  ('puppet_meat', '灵肉', '傀儡产线底座资源。仓内结算；可收取入行囊。', 'material', 'white', true, 'puppet_meat'),
  ('puppet_stone', '灵石材', '傀儡石线产出，炼器常用。', 'material', 'white', true, 'puppet_stone')
ON CONFLICT ("slug") DO NOTHING;

-- equipment_grants.source 增加 dongfu_forge
ALTER TABLE "equipment_grants" DROP CONSTRAINT IF EXISTS "equipment_grants_source_check";
ALTER TABLE "equipment_grants"
  ADD CONSTRAINT "equipment_grants_source_check"
  CHECK ("source" IN ('stage_drop', 'boss_first', 'boss_repeat', 'admin_grant', 'event', 'mail', 'dongfu_forge'));
