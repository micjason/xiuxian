ALTER TABLE "content_globals" ADD COLUMN "gear_quality_factors" jsonb;
--> statement-breakpoint
ALTER TABLE "content_realms" ADD COLUMN "major_key" text;
--> statement-breakpoint
UPDATE "content_globals"
SET "gear_quality_factors" = '{"white":1,"green":1.15,"blue":1.3,"purple":1.5,"orange":1.8}'::jsonb
WHERE "gear_quality_factors" IS NULL;
--> statement-breakpoint
UPDATE "content_realms"
SET "major_key" = split_part("slug", '_', 1)
WHERE "slug" ~ '^(qi|foundation|core|infant|spirit)_(early|mid|late)$'
  AND "major_key" IS NULL;
