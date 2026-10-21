-- 批次②：手动装备、套装、每关指定掉落、功法栏位、统一品质表（去掉红）、删过时字段。
-- 1) 装备来源 / 套装 / 参与随机掉落。公式装备 origin = formula、参与随机；手动装备（gear_m_0001…）由后台新建，默认不参与随机。
ALTER TABLE "content_items" ADD COLUMN IF NOT EXISTS "origin" text DEFAULT 'formula' NOT NULL;
--> statement-breakpoint
ALTER TABLE "content_items" ADD COLUMN IF NOT EXISTS "set_slug" text;
--> statement-breakpoint
ALTER TABLE "content_items" ADD COLUMN IF NOT EXISTS "random_drop" boolean DEFAULT true NOT NULL;
--> statement-breakpoint
-- 2) 套装：件数档位加成 tiers = [{pieces, stats:[{stat, mode:'pct'|'flat', value}]}]；成员 = content_items.set_slug。
CREATE TABLE IF NOT EXISTS "content_gear_sets" (
  "slug" text PRIMARY KEY NOT NULL,
  "display_name" text NOT NULL,
  "description" text DEFAULT '' NOT NULL,
  "tiers" jsonb DEFAULT '[]'::jsonb NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_by" uuid
);
--> statement-breakpoint
-- 3) 每关指定掉落 [{itemSlug, trigger:'monster'|'boss_first'|'boss_repeat', chanceBp, count}]，和随机掉落同时生效。
ALTER TABLE "content_stages" ADD COLUMN IF NOT EXISTS "designated_drops" jsonb DEFAULT '[]'::jsonb NOT NULL;
--> statement-breakpoint
-- 4) 去掉红（仙品）：强化规则里的红删掉；万一有红色物品 / 掉落权重，并到橙（线上没有）。
UPDATE "content_globals" SET "enhance" = "enhance" #- '{qualities,red}' WHERE "enhance" IS NOT NULL AND ("enhance"->'qualities') ? 'red';
--> statement-breakpoint
-- 红色装备的强化等级先压到橙的上限以内（并到橙以后不会超上限），再把品质改成橙。
UPDATE "player_items" pi
SET "enhance_level" = LEAST(pi."enhance_level", COALESCE((SELECT ("enhance"->'qualities'->'orange'->>'cap')::int FROM "content_globals" WHERE "id" = 1), 15))
FROM "content_items" ci
WHERE ci."slug" = pi."item_slug" AND ci."quality" = 'red';
--> statement-breakpoint
UPDATE "content_items" SET "quality" = 'orange', "updated_at" = now() WHERE "quality" = 'red';
--> statement-breakpoint
UPDATE "content_stages"
SET "monster_drop" = jsonb_set("monster_drop", '{qualityWeights}', ("monster_drop"->'qualityWeights') - 'red')
WHERE "monster_drop" IS NOT NULL AND ("monster_drop"->'qualityWeights') ? 'red';
--> statement-breakpoint
-- 5) 功法栏位：通用 N 个，按境界开放（后台配置概览可改）。没配过的给默认：炼气一层 1 个、筑基一层 2 个、金丹一层 3 个（按大境界第一层的排序号）。
UPDATE "content_globals" g
SET "art_slot_rules" = COALESCE((
  SELECT jsonb_agg(jsonb_build_object('minRealmOrder', r.first_order, 'slots', r.n) ORDER BY r.first_order)
  FROM (
    SELECT m.first_order, row_number() OVER (ORDER BY m.first_order) AS n
    FROM (SELECT min("sort_order") AS first_order FROM "content_realms" GROUP BY COALESCE("major_key", "slug")) m
    ORDER BY m.first_order
    LIMIT 3
  ) r
), '[{"minRealmOrder": 1, "slots": 1}]'::jsonb)
WHERE g."art_slot_rules" IS NULL OR jsonb_array_length(g."art_slot_rules") = 0;
--> statement-breakpoint
-- 6) 删掉没用的字段：挂机击杀上限（离线不打怪）、最低客户端版本号（强制更新统一走发布中心）、突破成功率 6 列（突破必定成功）。
ALTER TABLE "content_globals" DROP COLUMN IF EXISTS "idle_kill_cap";
--> statement-breakpoint
ALTER TABLE "content_globals" DROP COLUMN IF EXISTS "min_client_version_code";
--> statement-breakpoint
ALTER TABLE "content_realms" DROP COLUMN IF EXISTS "base_rate_bp";
--> statement-breakpoint
ALTER TABLE "content_realms" DROP COLUMN IF EXISTS "power_factor_bp";
--> statement-breakpoint
ALTER TABLE "content_realms" DROP COLUMN IF EXISTS "min_rate_bp";
--> statement-breakpoint
ALTER TABLE "content_realms" DROP COLUMN IF EXISTS "max_rate_bp";
--> statement-breakpoint
ALTER TABLE "content_realms" DROP COLUMN IF EXISTS "fail_loss_bp";
--> statement-breakpoint
ALTER TABLE "content_realms" DROP COLUMN IF EXISTS "pity_step_bp";
