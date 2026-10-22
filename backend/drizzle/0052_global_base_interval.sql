-- 基础出手间隔收成全局 combat.baseInterval（默认 1.5）；境界表仍保留 base_interval 列兼容旧数据，结算读全局。
-- 境界自带大招停用：把已有 ult 倍率清零（字段保留，后台不再展示）。
UPDATE "content_globals"
SET "combat" = jsonb_set(
  COALESCE("combat", '{}'::jsonb),
  '{baseInterval}',
  '1.5'::jsonb,
  true
)
WHERE ("combat"->>'baseInterval') IS NULL OR ("combat"->>'baseInterval') = '';

UPDATE "content_realms"
SET "ult_name" = '',
    "ult_damage_mult_bp" = 0,
    "ult_cooldown_seconds" = 0,
    "ult_first_cooldown_seconds" = 0
WHERE "ult_damage_mult_bp" <> 0 OR "ult_name" <> '' OR "ult_cooldown_seconds" <> 0;
