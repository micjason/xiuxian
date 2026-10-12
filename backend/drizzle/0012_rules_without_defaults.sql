ALTER TABLE "content_globals" ALTER COLUMN "offline_cap_seconds" DROP NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "offline_cap_seconds" DROP DEFAULT;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "bag_capacity" DROP NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "bag_capacity" DROP DEFAULT;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "power_weights" DROP NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "power_weights" DROP DEFAULT;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "combat" DROP NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "combat" DROP DEFAULT;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "art_slot_rules" DROP NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "art_slot_rules" DROP DEFAULT;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "idle_kill_cap" DROP NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_globals" ALTER COLUMN "idle_kill_cap" DROP DEFAULT;
--> statement-breakpoint
ALTER TABLE "content_realms" ALTER COLUMN "base_interval" DROP NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_realms" ALTER COLUMN "base_interval" DROP DEFAULT;
