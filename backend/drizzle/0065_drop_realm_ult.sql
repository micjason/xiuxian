-- 删除境界表手动大招列（产品已下线境界大招，只留技能自动技能）。迁移号 0065。可重复执行。
ALTER TABLE "content_realms" DROP COLUMN IF EXISTS "ult_name";
--> statement-breakpoint
ALTER TABLE "content_realms" DROP COLUMN IF EXISTS "ult_damage_mult_bp";
--> statement-breakpoint
ALTER TABLE "content_realms" DROP COLUMN IF EXISTS "ult_cooldown_seconds";
--> statement-breakpoint
ALTER TABLE "content_realms" DROP COLUMN IF EXISTS "ult_first_cooldown_seconds";
