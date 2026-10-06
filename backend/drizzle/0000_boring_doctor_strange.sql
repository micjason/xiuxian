CREATE TYPE "public"."actor_type" AS ENUM('player', 'admin');--> statement-breakpoint
CREATE TYPE "public"."operation_action" AS ENUM('login', 'settle', 'breakthrough', 'publish', 'repair');--> statement-breakpoint
CREATE TYPE "public"."operation_result" AS ENUM('success', 'failure');--> statement-breakpoint
CREATE TYPE "public"."release_status" AS ENUM('draft', 'published', 'archived');--> statement-breakpoint
CREATE TABLE "admins" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"username" text NOT NULL,
	"password_hash" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "admins_username_unique" UNIQUE("username")
);
--> statement-breakpoint
CREATE TABLE "content_releases" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"status" "release_status" NOT NULL,
	"offline_cap_seconds" double precision NOT NULL,
	"published_at" timestamp with time zone,
	"note" text
);
--> statement-breakpoint
CREATE TABLE "items" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"release_id" uuid NOT NULL,
	"slug" text NOT NULL,
	"display_name" text NOT NULL,
	"description" text NOT NULL,
	"kind" text NOT NULL,
	"quality" text NOT NULL,
	"slot" text,
	"attack" double precision NOT NULL,
	"defense" double precision NOT NULL,
	"hp" double precision NOT NULL,
	"speed" double precision NOT NULL,
	CONSTRAINT "items_release_slug" UNIQUE("release_id","slug")
);
--> statement-breakpoint
CREATE TABLE "operation_records" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"at" timestamp with time zone NOT NULL,
	"actor_type" "actor_type" NOT NULL,
	"actor_id" uuid,
	"actor_name" text NOT NULL,
	"action" "operation_action" NOT NULL,
	"result" "operation_result" NOT NULL,
	"reason" text,
	"content_release_id" uuid,
	"summary" jsonb NOT NULL
);
--> statement-breakpoint
CREATE TABLE "player_states" (
	"player_id" uuid PRIMARY KEY NOT NULL,
	"cultivation" double precision NOT NULL,
	"realm_slug" text NOT NULL,
	"last_settled_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "players" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"username" text NOT NULL,
	"password_hash" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "players_username_unique" UNIQUE("username")
);
--> statement-breakpoint
CREATE TABLE "realms" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"release_id" uuid NOT NULL,
	"slug" text NOT NULL,
	"display_name" text NOT NULL,
	"sort_order" double precision NOT NULL,
	"gain_per_second" double precision NOT NULL,
	"breakthrough_cost" double precision NOT NULL,
	"next_slug" text,
	"attack" double precision NOT NULL,
	"defense" double precision NOT NULL,
	"hp" double precision NOT NULL,
	"speed" double precision NOT NULL,
	CONSTRAINT "realms_release_slug" UNIQUE("release_id","slug")
);
--> statement-breakpoint
CREATE TABLE "repair_applications" (
	"repair_name" text NOT NULL,
	"player_id" uuid NOT NULL,
	"preview_id" uuid NOT NULL,
	"applied_at" timestamp with time zone NOT NULL,
	CONSTRAINT "repair_applications_name_player" UNIQUE("repair_name","player_id")
);
--> statement-breakpoint
CREATE TABLE "repair_previews" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"repair_name" text NOT NULL,
	"entries" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"state_token" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "sessions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"token_hash" text NOT NULL,
	"actor_type" "actor_type" NOT NULL,
	"actor_id" uuid NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	CONSTRAINT "sessions_token_hash_unique" UNIQUE("token_hash")
);
--> statement-breakpoint
CREATE TABLE "skills" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"release_id" uuid NOT NULL,
	"slug" text NOT NULL,
	"display_name" text NOT NULL,
	"description" text NOT NULL,
	"role" text NOT NULL,
	"attack" double precision NOT NULL,
	"defense" double precision NOT NULL,
	"hp" double precision NOT NULL,
	"speed" double precision NOT NULL,
	"cultivate_bonus" double precision NOT NULL,
	"min_realm_order" double precision NOT NULL,
	CONSTRAINT "skills_release_slug" UNIQUE("release_id","slug")
);
--> statement-breakpoint
ALTER TABLE "items" ADD CONSTRAINT "items_release_id_content_releases_id_fk" FOREIGN KEY ("release_id") REFERENCES "public"."content_releases"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "player_states" ADD CONSTRAINT "player_states_player_id_players_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "realms" ADD CONSTRAINT "realms_release_id_content_releases_id_fk" FOREIGN KEY ("release_id") REFERENCES "public"."content_releases"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "repair_applications" ADD CONSTRAINT "repair_applications_player_id_players_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "repair_applications" ADD CONSTRAINT "repair_applications_preview_id_repair_previews_id_fk" FOREIGN KEY ("preview_id") REFERENCES "public"."repair_previews"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "skills" ADD CONSTRAINT "skills_release_id_content_releases_id_fk" FOREIGN KEY ("release_id") REFERENCES "public"."content_releases"("id") ON DELETE no action ON UPDATE no action;