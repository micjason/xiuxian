-- 玩家战斗动画包。开发阶段一份即生效，没有草稿列。

CREATE TABLE IF NOT EXISTS "animation_packs" (
  "id" text PRIMARY KEY,
  "name" text NOT NULL,
  "subject" text NOT NULL,
  "manifest" jsonb NOT NULL,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now()
);
