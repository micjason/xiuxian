ALTER TABLE "content_globals" ADD COLUMN "enhance" jsonb;
--> statement-breakpoint
ALTER TABLE "player_items" ADD COLUMN "enhance_level" integer DEFAULT 0 NOT NULL;
--> statement-breakpoint
ALTER TABLE "player_states" ADD COLUMN "enhance_exp" bigint DEFAULT 0 NOT NULL;
--> statement-breakpoint
ALTER TABLE "player_states" ADD COLUMN "bag_bonus" integer DEFAULT 0 NOT NULL;
--> statement-breakpoint
-- 强化规则起始值（可在后台修改；数值见 docs/design/enhance_rules_proposal.md，均为起始值，待与客户确认）
UPDATE "content_globals"
SET "enhance" = '{"expBase":60,"expGrowth":1.25,"statGrowthBp":600,"refundBp":8000,"qualities":{"white":{"cap":5,"costMult":1,"decomposeExp":30},"green":{"cap":8,"costMult":1.1,"decomposeExp":60},"blue":{"cap":10,"costMult":1.25,"decomposeExp":120},"purple":{"cap":12,"costMult":1.4,"decomposeExp":240},"orange":{"cap":15,"costMult":1.6,"decomposeExp":480}}}'::jsonb
WHERE "enhance" IS NULL;
