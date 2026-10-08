ALTER TABLE "skills" ADD COLUMN "prerequisite_slugs" jsonb DEFAULT '[]'::jsonb NOT NULL;
--> statement-breakpoint
ALTER TABLE "items" ADD COLUMN "grantable" boolean DEFAULT false NOT NULL;
--> statement-breakpoint
ALTER TABLE "items" ADD COLUMN "skill_slug" text;
--> statement-breakpoint
CREATE TABLE "popup_types" (
	"slug" text PRIMARY KEY NOT NULL,
	"priority" integer NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"template" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "announcements" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"title" text NOT NULL,
	"body" text NOT NULL,
	"enabled" boolean DEFAULT false NOT NULL,
	"enabled_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "notice_dismissals" (
	"player_id" uuid NOT NULL,
	"notice_id" text NOT NULL,
	"dismissed_at" timestamp with time zone NOT NULL,
	CONSTRAINT "notice_dismissals_player_id_notice_id_pk" PRIMARY KEY("player_id","notice_id")
);
--> statement-breakpoint
CREATE TABLE "player_notices" (
	"player_id" uuid NOT NULL,
	"notice_id" text NOT NULL,
	"type" text NOT NULL,
	"priority" integer NOT NULL,
	"template" text NOT NULL,
	"triggered_at" timestamp with time zone NOT NULL,
	"payload" jsonb NOT NULL,
	CONSTRAINT "player_notices_player_id_notice_id_pk" PRIMARY KEY("player_id","notice_id")
);
--> statement-breakpoint
ALTER TABLE "notice_dismissals" ADD CONSTRAINT "notice_dismissals_player_id_players_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE no action ON UPDATE no action;
--> statement-breakpoint
ALTER TABLE "player_notices" ADD CONSTRAINT "player_notices_player_id_players_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE no action ON UPDATE no action;
