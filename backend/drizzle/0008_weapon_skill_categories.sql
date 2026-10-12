CREATE TABLE "content_weapon_categories" (
	"slug" text PRIMARY KEY NOT NULL,
	"display_name" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_by" uuid
);
--> statement-breakpoint
CREATE TABLE "content_skill_categories" (
	"slug" text PRIMARY KEY NOT NULL,
	"display_name" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_by" uuid
);
--> statement-breakpoint
ALTER TABLE "content_items" ADD COLUMN "weapon_category_slug" text;
--> statement-breakpoint
ALTER TABLE "content_skills" ADD COLUMN "skill_category_slug" text;
