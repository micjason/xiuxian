-- 突破关卡：炼气/筑基/金丹共 9 层出厂挂同名关；修正错误的 lianqi_3→lianqi_2。
-- 元婴及以后 required_stage_slug 保持空（不强制清已有手工配置以外的占位——仅清出厂曾挂过的大境三层闸若仍指向自身且无运营意图：这里只写死前九层）。
-- 迁移号 0070；when 1801000000000。可重复执行。
UPDATE "content_realms"
SET "required_stage_slug" = "slug"
WHERE "slug" IN (
  'lianqi_1', 'lianqi_2', 'lianqi_3',
  'zhuji_1', 'zhuji_2', 'zhuji_3',
  'jindan_1', 'jindan_2', 'jindan_3'
);
