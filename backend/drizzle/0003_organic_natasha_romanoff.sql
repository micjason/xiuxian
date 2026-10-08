CREATE TABLE "content_current" (
	"id" integer PRIMARY KEY DEFAULT 1 NOT NULL,
	"version" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "content_drop_entries" (
	"drop_table_slug" text NOT NULL,
	"item_slug" text NOT NULL,
	"chance_bp" integer NOT NULL,
	"min_qty" integer NOT NULL,
	"max_qty" integer NOT NULL,
	CONSTRAINT "content_drop_entries_drop_table_slug_item_slug_pk" PRIMARY KEY("drop_table_slug","item_slug")
);
--> statement-breakpoint
CREATE TABLE "content_drop_tables" (
	"slug" text PRIMARY KEY NOT NULL,
	"display_name" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "content_globals" (
	"id" integer PRIMARY KEY DEFAULT 1 NOT NULL,
	"starting_realm_slug" text DEFAULT 'mortal' NOT NULL,
	"offline_cap_seconds" integer DEFAULT 28800 NOT NULL,
	"bag_capacity" integer DEFAULT 100 NOT NULL,
	"starter_items" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"power_weights" jsonb DEFAULT '{"attack":1,"defense":0.8,"hp":0.04,"speed":1.5}'::jsonb NOT NULL,
	"combat" jsonb DEFAULT '{"minInterval":0.7,"respawnSeconds":0.8,"challengeCooldownSeconds":3}'::jsonb NOT NULL,
	"art_slot_rules" jsonb DEFAULT '[{"minRealmOrder":0,"slots":1},{"minRealmOrder":4,"slots":2}]'::jsonb NOT NULL,
	"idle_kill_cap" integer DEFAULT 200 NOT NULL,
	"min_client_version_code" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "content_items" (
	"slug" text PRIMARY KEY NOT NULL,
	"display_name" text NOT NULL,
	"description" text DEFAULT '' NOT NULL,
	"kind" text NOT NULL,
	"quality" text DEFAULT 'white' NOT NULL,
	"slot" text,
	"attack" double precision DEFAULT 0 NOT NULL,
	"defense" double precision DEFAULT 0 NOT NULL,
	"hp" double precision DEFAULT 0 NOT NULL,
	"speed" double precision DEFAULT 0 NOT NULL,
	"required_realm_order" integer DEFAULT 0 NOT NULL,
	"skill_slug" text,
	"stackable" boolean DEFAULT false NOT NULL,
	"icon_key" text DEFAULT '' NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "content_known_slugs" (
	"kind" text NOT NULL,
	"slug" text NOT NULL,
	CONSTRAINT "content_known_slugs_kind_slug_pk" PRIMARY KEY("kind","slug")
);
--> statement-breakpoint
CREATE TABLE "content_realms" (
	"slug" text PRIMARY KEY NOT NULL,
	"display_name" text NOT NULL,
	"major_name" text DEFAULT '' NOT NULL,
	"sort_order" integer NOT NULL,
	"next_realm_slug" text,
	"tick_seconds" integer DEFAULT 1 NOT NULL,
	"gain_per_tick" integer DEFAULT 0 NOT NULL,
	"base_attack" double precision DEFAULT 0 NOT NULL,
	"base_defense" double precision DEFAULT 0 NOT NULL,
	"base_hp" double precision DEFAULT 0 NOT NULL,
	"base_speed" double precision DEFAULT 0 NOT NULL,
	"base_interval" double precision DEFAULT 1.5 NOT NULL,
	"breakthrough_cost" integer DEFAULT 0 NOT NULL,
	"required_stage_slug" text,
	"recommended_power" integer DEFAULT 0 NOT NULL,
	"base_rate_bp" integer DEFAULT 9000 NOT NULL,
	"power_factor_bp" integer DEFAULT 3000 NOT NULL,
	"min_rate_bp" integer DEFAULT 2000 NOT NULL,
	"max_rate_bp" integer DEFAULT 9500 NOT NULL,
	"fail_loss_bp" integer DEFAULT 3000 NOT NULL,
	"pity_step_bp" integer DEFAULT 1000 NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "content_skills" (
	"slug" text PRIMARY KEY NOT NULL,
	"display_name" text NOT NULL,
	"description" text DEFAULT '' NOT NULL,
	"role" text NOT NULL,
	"rank" text DEFAULT 'yellow' NOT NULL,
	"attack" double precision DEFAULT 0 NOT NULL,
	"defense" double precision DEFAULT 0 NOT NULL,
	"hp" double precision DEFAULT 0 NOT NULL,
	"speed" double precision DEFAULT 0 NOT NULL,
	"cultivate_bonus_bp" integer DEFAULT 0 NOT NULL,
	"required_realm_order" integer DEFAULT 0 NOT NULL,
	"prerequisite_skill_slugs" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "content_stages" (
	"slug" text PRIMARY KEY NOT NULL,
	"display_name" text NOT NULL,
	"sort_order" integer DEFAULT 0 NOT NULL,
	"next_stage_slug" text,
	"required_realm_order" integer DEFAULT 0 NOT NULL,
	"recommended_power" integer DEFAULT 0 NOT NULL,
	"boss_name" text DEFAULT '' NOT NULL,
	"boss_attack" double precision DEFAULT 1 NOT NULL,
	"boss_defense" double precision DEFAULT 0 NOT NULL,
	"boss_hp" double precision DEFAULT 1 NOT NULL,
	"boss_interval" double precision DEFAULT 1.5 NOT NULL,
	"boss_drop_table_slug" text NOT NULL,
	"idle_drop_table_slug" text NOT NULL,
	"first_clear_drop_table_slug" text NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "content_versions" (
	"version" integer PRIMARY KEY GENERATED ALWAYS AS IDENTITY (sequence name "content_versions_version_seq" INCREMENT BY 1 MINVALUE 1 MAXVALUE 2147483647 START WITH 1 CACHE 1),
	"snapshot" jsonb NOT NULL,
	"checksum" text NOT NULL,
	"note" text NOT NULL,
	"published_by" uuid,
	"published_at" timestamp with time zone NOT NULL,
	"source_version" integer
);
--> statement-breakpoint
ALTER TABLE "admins" ADD COLUMN "role" text DEFAULT 'owner' NOT NULL;--> statement-breakpoint
ALTER TABLE "admins" ADD COLUMN "last_login_at" timestamp with time zone;--> statement-breakpoint


ALTER TABLE "players" ADD COLUMN "username_lower" text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE "players" ADD COLUMN "status" text DEFAULT 'active' NOT NULL;--> statement-breakpoint
ALTER TABLE "players" ADD COLUMN "last_login_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "sessions" ADD COLUMN "last_seen_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "sessions" ADD COLUMN "revoked_at" timestamp with time zone;--> statement-breakpoint

ALTER TABLE "content_drop_entries" ADD CONSTRAINT "content_drop_entries_drop_table_slug_content_drop_tables_slug_fk" FOREIGN KEY ("drop_table_slug") REFERENCES "public"."content_drop_tables"("slug") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
