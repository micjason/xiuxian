-- 第三批（2026-10-21）：首领规则默认值写进 content_globals.tuning.bossRules（配置概览「首领规则」两列）。
-- 小首领（精英）：属性 = 本关小怪 × 气血5 / 攻1.3 / 防1.2；允许重打、不给重打奖励；品质 0/70/25/5/0；允许自动挑战（战力 ≥ 推荐 × 100%）。
-- 大首领（章末）：手填属性；允许重打、重打给奖励，每日次数沿用原来的「首领每日奖励次数」（combat.bossDailyRewardCount，没有就 5）；
--   品质 0/50/35/13/2（橙 2%）；手动挑战。两列都是「击败本关首领 + 达到下一关境界」才解锁下一关。
-- 已经有 bossRules 的不动（可以重复执行）。
UPDATE "content_globals"
SET "tuning" = COALESCE("tuning", '{}'::jsonb) || jsonb_build_object('bossRules', jsonb_build_object(
  'elite', jsonb_build_object(
    'statMode', 'auto',
    'statMul', jsonb_build_object('hp', 5, 'attack', 1.3, 'defense', 1.2),
    'allowRepeat', true,
    'repeatRewards', false,
    'dailyRewardLimit', 0,
    'gearQualityPct', jsonb_build_object('white', 0, 'green', 70, 'blue', 25, 'purple', 5, 'orange', 0),
    'autoChallenge', true,
    'autoChallengePowerPct', 100,
    'autoChallengeRetrySeconds', 60,
    'unlockNeedsBossWin', true,
    'unlockNeedsRealm', true
  ),
  'chief', jsonb_build_object(
    'statMode', 'manual',
    'statMul', jsonb_build_object('hp', 8.5, 'attack', 1.15, 'defense', 1.2),
    'allowRepeat', true,
    'repeatRewards', true,
    'dailyRewardLimit', COALESCE(("combat" ->> 'bossDailyRewardCount')::int, 5),
    'gearQualityPct', jsonb_build_object('white', 0, 'green', 50, 'blue', 35, 'purple', 13, 'orange', 2),
    'autoChallenge', false,
    'autoChallengePowerPct', 100,
    'autoChallengeRetrySeconds', 60,
    'unlockNeedsBossWin', true,
    'unlockNeedsRealm', true
  )
)),
"updated_at" = now()
WHERE "tuning" IS NULL OR NOT ("tuning" ? 'bossRules');
