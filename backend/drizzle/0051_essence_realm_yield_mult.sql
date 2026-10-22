-- 精粹按装备大境界分档：essence.realmYieldMult 默认炼气 0.25 / 筑基 0.45 / 金丹 1.0。
-- 一口价 yields 仍是金丹基准；旧存档缺 realmYieldMult 时写入默认（可重复执行）。
UPDATE "content_globals"
SET "enhance" = jsonb_set(
  "enhance",
  '{essence,realmYieldMult}',
  '{"qi": 0.25, "foundation": 0.45, "core": 1.0}'::jsonb,
  true
), "updated_at" = now()
WHERE jsonb_typeof("enhance") = 'object'
  AND jsonb_typeof("enhance"->'essence') = 'object'
  AND NOT (("enhance"->'essence') ? 'realmYieldMult');
