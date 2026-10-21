-- 第四批（2026-10-21）：首领玩法改版——每关一个首领、一套规则（不再分精英 / 章末两档）。
-- 1) 单关覆盖（bosses[0].rules）换成新的一套：去掉每关每日次数 dailyRewardLimit（改成全局的每日首领挑战总次数）；
--    原章末关（含没有章节的关）：首领是手填数值的，补一项「属性 = 手填」（新默认是按普通怪自动算）；
--    原章末关单独改过的装备品质，改记到「重复奖励装备品质」（整组 5 档写全）。只在 tuning.bossRules 还是老格式时执行。
-- 2) tuning.bossRules 从两列 { elite, chief } 换成一套：底子是原小首领那列；重复奖励装备品质 = 原章末那列的品质；
--    每日首领挑战总次数 = 原章末每日次数（没有 / 0 就 5）；重复奖励打开；挂机刷首领：开、每 1000 波一次、不算每日次数；一次结算最多 20 只。
-- 3) 没配重复奖励的首领（原精英）补上：1 件装备（按重复奖励品质抽）+ 70% 突破石·下品 ×1（有这个物品时）。后台可改。
-- 4) player_states.boss_daily_count / boss_daily_day：全局每日首领挑战次数（从 0 开始；原来每关的每日次数不再用）。
-- 5) player_stage_progress.idle_waves：首领已击败后在本关挂机累计的小怪波数（从 0 开始）。
-- 玩家已有的首通记录（不管原来是精英还是章末）照算「已击败」，不用改。可以重复执行。
WITH legacy AS (
  SELECT COALESCE("tuning" -> 'bossRules' -> 'chief', '{}'::jsonb) AS chief,
         COALESCE("tuning" -> 'bossRules' -> 'elite', '{}'::jsonb) AS elite
  FROM "content_globals"
  WHERE "id" = 1 AND ("tuning" -> 'bossRules' ? 'elite' OR "tuning" -> 'bossRules' ? 'chief')
),
chief_stage AS (
  SELECT COALESCE(c."chief_stage_slug", (
    SELECT s2."slug" FROM "content_stages" s2
    WHERE s2."chapter_slug" = c."slug" AND s2."enabled"
    ORDER BY s2."sort_order" DESC, s2."required_realm_order" DESC, s2."slug" DESC LIMIT 1
  )) AS stage_slug
  FROM "content_chapters" c
),
mapped AS (
  SELECT
    s."slug",
    (s."chapter_slug" IS NULL OR s."slug" IN (SELECT stage_slug FROM chief_stage WHERE stage_slug IS NOT NULL)) AS was_chief,
    COALESCE(s."bosses" -> 0 -> 'rules', '{}'::jsonb) - 'dailyRewardLimit' AS base_rules
  FROM "content_stages" s
  WHERE jsonb_typeof(s."bosses") = 'array' AND jsonb_array_length(s."bosses") > 0
),
next_rules AS (
  SELECT
    m."slug",
    CASE WHEN NOT m.was_chief THEN m.base_rules ELSE
      (m.base_rules - 'gearQualityPct')
      || CASE WHEN m.base_rules ? 'statMode' OR COALESCE(l.chief ->> 'statMode', 'manual') = COALESCE(l.elite ->> 'statMode', 'auto') THEN '{}'::jsonb
              ELSE jsonb_build_object('statMode', COALESCE(l.chief ->> 'statMode', 'manual')) END
      || CASE WHEN m.base_rules ? 'gearQualityPct'
              THEN jsonb_build_object('repeatGearQualityPct',
                     COALESCE(l.chief -> 'gearQualityPct', '{"white":0,"green":50,"blue":35,"purple":13,"orange":2}'::jsonb) || (m.base_rules -> 'gearQualityPct'))
              ELSE '{}'::jsonb END
    END AS rules
  FROM mapped m CROSS JOIN legacy l
)
UPDATE "content_stages" AS s
SET "bosses" = jsonb_set(
      s."bosses",
      '{0}',
      CASE WHEN n.rules = '{}'::jsonb THEN (s."bosses" -> 0) - 'rules' ELSE (s."bosses" -> 0) || jsonb_build_object('rules', n.rules) END
    ),
    "updated_at" = now()
FROM next_rules n
WHERE s."slug" = n."slug";
--> statement-breakpoint
UPDATE "content_globals"
SET "tuning" = jsonb_set("tuning", '{bossRules}', jsonb_build_object(
    'statMode', COALESCE("tuning" -> 'bossRules' -> 'elite' -> 'statMode', '"auto"'::jsonb),
    'statMul', COALESCE("tuning" -> 'bossRules' -> 'elite' -> 'statMul', '{"hp":5,"attack":1.3,"defense":1.2}'::jsonb),
    'allowRepeat', COALESCE("tuning" -> 'bossRules' -> 'elite' -> 'allowRepeat', 'true'::jsonb),
    'repeatRewards', 'true'::jsonb,
    'gearQualityPct', COALESCE("tuning" -> 'bossRules' -> 'elite' -> 'gearQualityPct', '{"white":0,"green":70,"blue":25,"purple":5,"orange":0}'::jsonb),
    'repeatGearQualityPct', COALESCE("tuning" -> 'bossRules' -> 'chief' -> 'gearQualityPct', '{"white":0,"green":50,"blue":35,"purple":13,"orange":2}'::jsonb),
    'autoChallenge', COALESCE("tuning" -> 'bossRules' -> 'elite' -> 'autoChallenge', 'true'::jsonb),
    'autoChallengePowerPct', COALESCE("tuning" -> 'bossRules' -> 'elite' -> 'autoChallengePowerPct', '100'::jsonb),
    'autoChallengeRetrySeconds', COALESCE("tuning" -> 'bossRules' -> 'elite' -> 'autoChallengeRetrySeconds', '60'::jsonb),
    'idleSpawn', 'true'::jsonb,
    'idleSpawnWaves', '1000'::jsonb,
    'idleSpawnCountsDaily', 'false'::jsonb,
    'unlockNeedsBossWin', COALESCE("tuning" -> 'bossRules' -> 'elite' -> 'unlockNeedsBossWin', 'true'::jsonb),
    'unlockNeedsRealm', COALESCE("tuning" -> 'bossRules' -> 'elite' -> 'unlockNeedsRealm', 'true'::jsonb),
    'dailyChallengeTotal', to_jsonb(CASE WHEN COALESCE(("tuning" -> 'bossRules' -> 'chief' ->> 'dailyRewardLimit')::int, 0) > 0
                                         THEN ("tuning" -> 'bossRules' -> 'chief' ->> 'dailyRewardLimit')::int ELSE 5 END),
    'idleSpawnMaxPerSettle', '20'::jsonb
  )),
  "updated_at" = now()
WHERE "tuning" IS NOT NULL AND ("tuning" -> 'bossRules' ? 'elite' OR "tuning" -> 'bossRules' ? 'chief');
--> statement-breakpoint
UPDATE "content_stages" AS s
SET "bosses" = jsonb_set(s."bosses", '{0,repeat}', jsonb_build_object(
      'gear', true,
      'extras', CASE WHEN EXISTS (SELECT 1 FROM "content_items" WHERE "slug" = 'enh_stone_low')
                     THEN '[{"itemSlug":"enh_stone_low","chanceBp":7000,"minQty":1,"maxQty":1}]'::jsonb ELSE '[]'::jsonb END
    )),
    "updated_at" = now()
WHERE jsonb_typeof(s."bosses") = 'array' AND jsonb_array_length(s."bosses") > 0
  AND jsonb_typeof(COALESCE(s."bosses" -> 0 -> 'repeat', 'null'::jsonb)) <> 'object';
--> statement-breakpoint
ALTER TABLE "player_states" ADD COLUMN IF NOT EXISTS "boss_daily_count" integer DEFAULT 0 NOT NULL;
--> statement-breakpoint
ALTER TABLE "player_states" ADD COLUMN IF NOT EXISTS "boss_daily_day" text;
--> statement-breakpoint
ALTER TABLE "player_stage_progress" ADD COLUMN IF NOT EXISTS "idle_waves" integer DEFAULT 0 NOT NULL;
