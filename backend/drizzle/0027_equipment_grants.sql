-- 批次②：「发放指定装备」统一接口（ADMIN_SPEC §14）的发放流水。每次发放一行；request_id 唯一 = 幂等键，重复请求不重复发。
-- 编号 0025 留给批次 3；when 必须大于 0026（1793190000000），drizzle 只跑 when 比库里最后一条大的迁移。
CREATE TABLE IF NOT EXISTS "equipment_grants" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "request_id" text NOT NULL,
  "player_id" uuid NOT NULL REFERENCES "players"("id"),
  "item_slug" text NOT NULL,
  "count" integer NOT NULL,
  "source" text NOT NULL,
  "source_ref" text,
  "operator" text,
  "reason" text,
  "note" text,
  "instance_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "equipment_grants_count_check" CHECK ("count" >= 1),
  CONSTRAINT "equipment_grants_source_check" CHECK ("source" IN ('stage_drop', 'boss_first', 'boss_repeat', 'admin_grant', 'event', 'mail'))
);
--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "equipment_grants_request_id" ON "equipment_grants" ("request_id");
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "equipment_grants_player_idx" ON "equipment_grants" ("player_id", "created_at");
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "equipment_grants_source_idx" ON "equipment_grants" ("source", "created_at");
