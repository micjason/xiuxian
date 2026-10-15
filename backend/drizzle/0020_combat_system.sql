-- 战斗系统（设计表 v1.2）：普通怪波次、首领奖励/每日次数、手动大招、离线弹窗记录。
ALTER TABLE "content_realms" ADD COLUMN "ult_name" text DEFAULT '' NOT NULL;
ALTER TABLE "content_realms" ADD COLUMN "ult_damage_mult_bp" integer DEFAULT 0 NOT NULL;
ALTER TABLE "content_realms" ADD COLUMN "ult_cooldown_seconds" double precision DEFAULT 0 NOT NULL;
ALTER TABLE "content_realms" ADD COLUMN "ult_first_cooldown_seconds" double precision DEFAULT 8 NOT NULL;
ALTER TABLE "content_stages" ADD COLUMN "monsters" jsonb DEFAULT '[]'::jsonb NOT NULL;
ALTER TABLE "content_stages" ADD COLUMN "monster_drop" jsonb;
ALTER TABLE "player_states" ADD COLUMN "wave_progress" double precision DEFAULT 0 NOT NULL;
ALTER TABLE "player_states" ADD COLUMN "wave_deaths_in_row" integer DEFAULT 0 NOT NULL;
ALTER TABLE "player_stage_progress" ADD COLUMN "daily_reward_count" integer DEFAULT 0 NOT NULL;
ALTER TABLE "player_stage_progress" ADD COLUMN "daily_reward_day" text;
CREATE TABLE "player_offline_reports" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "player_id" uuid NOT NULL REFERENCES "players"("id"),
  "started_at" timestamp with time zone NOT NULL,
  "ended_at" timestamp with time zone NOT NULL,
  "seconds" integer NOT NULL,
  "counted_seconds" integer NOT NULL,
  "hit_cap" boolean DEFAULT false NOT NULL,
  "gained" bigint DEFAULT 0 NOT NULL,
  "base_gained" bigint DEFAULT 0 NOT NULL,
  "bonus_gained" bigint DEFAULT 0 NOT NULL,
  "realm_slug" text NOT NULL,
  "acknowledged_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE INDEX "player_offline_reports_player_idx" ON "player_offline_reports" ("player_id", "created_at");
