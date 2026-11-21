-- 后台战斗预览草稿。与 animation_packs、内容草稿、发布快照无关。游戏不读。

CREATE TABLE IF NOT EXISTS "battle_preview_drafts" (
  "id" text PRIMARY KEY,
  "document" jsonb NOT NULL,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now()
);
