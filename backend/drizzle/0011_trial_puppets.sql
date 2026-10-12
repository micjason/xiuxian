CREATE TABLE "content_trial_puppets" (
	"slug" text PRIMARY KEY NOT NULL,
	"display_name" text NOT NULL,
	"kind" text NOT NULL,
	"realm_code" integer,
	"weapon_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"skill_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"attack" double precision,
	"defense" double precision,
	"hp" double precision,
	"speed" double precision,
	"interval" double precision,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_by" uuid,
	CONSTRAINT "content_trial_puppets_kind" CHECK ("kind" IN ('configured', 'manual'))
);
