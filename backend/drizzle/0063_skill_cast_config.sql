-- 自动技能施法节奏与伤害倍率可配。迁移号 0063。可重复执行。
-- 默认 cast_every_attacks=4、damage_mult_bp=10000，与原先硬编码行为一致。
ALTER TABLE "content_skills" ADD COLUMN IF NOT EXISTS "cast_every_attacks" integer DEFAULT 4;
--> statement-breakpoint
ALTER TABLE "content_skills" ADD COLUMN IF NOT EXISTS "damage_mult_bp" integer DEFAULT 10000;
--> statement-breakpoint
UPDATE "content_skills" SET "cast_every_attacks" = 4 WHERE "cast_every_attacks" IS NULL;
--> statement-breakpoint
UPDATE "content_skills" SET "damage_mult_bp" = 10000 WHERE "damage_mult_bp" IS NULL;
--> statement-breakpoint
ALTER TABLE "content_skills" ALTER COLUMN "cast_every_attacks" SET DEFAULT 4;
--> statement-breakpoint
ALTER TABLE "content_skills" ALTER COLUMN "damage_mult_bp" SET DEFAULT 10000;
--> statement-breakpoint
ALTER TABLE "content_skills" ALTER COLUMN "cast_every_attacks" SET NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_skills" ALTER COLUMN "damage_mult_bp" SET NOT NULL;
