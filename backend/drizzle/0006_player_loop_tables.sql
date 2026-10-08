CREATE TABLE "idempotency_keys" (
	"player_id" uuid NOT NULL,
	"key" text NOT NULL,
	"endpoint" text NOT NULL,
	"response" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "idempotency_keys_player_id_key_pk" PRIMARY KEY("player_id","key")
);
--> statement-breakpoint
CREATE TABLE "player_items" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"player_id" uuid NOT NULL,
	"item_slug" text NOT NULL,
	"is_stack" boolean DEFAULT false NOT NULL,
	"quantity" bigint DEFAULT 1 NOT NULL,
	"equipped_slot" text,
	"acquired_at" timestamp with time zone DEFAULT now() NOT NULL,
	"source" text DEFAULT 'drop' NOT NULL
);
--> statement-breakpoint
CREATE TABLE "player_skills" (
	"player_id" uuid NOT NULL,
	"skill_slug" text NOT NULL,
	"learned_at" timestamp with time zone DEFAULT now() NOT NULL,
	"running_slot" text,
	CONSTRAINT "player_skills_player_id_skill_slug_pk" PRIMARY KEY("player_id","skill_slug")
);
--> statement-breakpoint
CREATE TABLE "player_stage_progress" (
	"player_id" uuid NOT NULL,
	"stage_slug" text NOT NULL,
	"unlocked_at" timestamp with time zone DEFAULT now() NOT NULL,
	"first_cleared_at" timestamp with time zone,
	"clear_count" integer DEFAULT 0 NOT NULL,
	"best_clear_seconds" double precision,
	CONSTRAINT "player_stage_progress_player_id_stage_slug_pk" PRIMARY KEY("player_id","stage_slug")
);
--> statement-breakpoint
ALTER TABLE "content_drop_tables" ADD COLUMN "updated_by" uuid;--> statement-breakpoint
ALTER TABLE "content_globals" ADD COLUMN "updated_by" uuid;--> statement-breakpoint
ALTER TABLE "content_items" ADD COLUMN "updated_by" uuid;--> statement-breakpoint
ALTER TABLE "content_realms" ADD COLUMN "updated_by" uuid;--> statement-breakpoint
ALTER TABLE "content_skills" ADD COLUMN "updated_by" uuid;--> statement-breakpoint
ALTER TABLE "content_stages" ADD COLUMN "updated_by" uuid;--> statement-breakpoint
ALTER TABLE "player_states" ADD COLUMN "spirit_stones" bigint DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "player_states" ADD COLUMN "breakthrough_fail_streak" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "player_states" ADD COLUMN "idle_stage_slug" text;--> statement-breakpoint
ALTER TABLE "player_states" ADD COLUMN "last_challenge_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "player_states" ADD COLUMN "state_version" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "idempotency_keys" ADD CONSTRAINT "idempotency_keys_player_id_players_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "player_items" ADD CONSTRAINT "player_items_player_id_players_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "player_skills" ADD CONSTRAINT "player_skills_player_id_players_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "player_stage_progress" ADD CONSTRAINT "player_stage_progress_player_id_players_id_fk" FOREIGN KEY ("player_id") REFERENCES "public"."players"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "player_items_player_idx" ON "player_items" USING btree ("player_id");--> statement-breakpoint
CREATE UNIQUE INDEX "player_items_equipped_slot" ON "player_items" USING btree ("player_id","equipped_slot") WHERE "player_items"."equipped_slot" is not null;--> statement-breakpoint
CREATE UNIQUE INDEX "player_items_stack" ON "player_items" USING btree ("player_id","item_slug") WHERE "player_items"."is_stack" = true;--> statement-breakpoint
CREATE UNIQUE INDEX "player_skills_running_slot" ON "player_skills" USING btree ("player_id","running_slot") WHERE "player_skills"."running_slot" is not null;