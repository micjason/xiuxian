-- 洞府 v1 · 临时属性 buff 表（开发二号）。与洞府经营开发 0060 的 player_active_buffs 完全一致。
-- CREATE IF NOT EXISTS：0060 先跑或本迁移先跑都安全。不插入物品（物品/effect 默认值以 0060 为准；0047 已有占位）。
-- 另：content_items.effect 列若尚无则补上，便于本分支单测与后台编辑。
ALTER TABLE "content_items" ADD COLUMN IF NOT EXISTS "effect" jsonb;
--> statement-breakpoint
UPDATE "content_items"
SET "effect" = '{"buffStat":"attack","buffBp":1000,"durationSeconds":300}'::jsonb
WHERE "slug" = 'pill_atk_temp' AND ("effect" IS NULL OR "effect" = 'null'::jsonb);
--> statement-breakpoint
UPDATE "content_items"
SET "effect" = '{"buffStat":"defense","buffBp":1000,"durationSeconds":300}'::jsonb
WHERE "slug" = 'pill_def_temp' AND ("effect" IS NULL OR "effect" = 'null'::jsonb);
--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "player_active_buffs" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "player_id" uuid NOT NULL REFERENCES "players"("id") ON DELETE CASCADE,
  "buff_stat" text NOT NULL,
  "buff_bp" integer NOT NULL,
  "started_at" timestamp with time zone NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  "source_item_slug" text NOT NULL
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "player_active_buffs_player_idx" ON "player_active_buffs" ("player_id");
