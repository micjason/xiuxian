-- 离线/在线结算只在“整段时长 × 每节拍 × (1 + 功法加成)”上取整一次；
-- 不足 1 点的部分（万分之一点，0..9999）存在这里，下次结算接着算，3 秒轮询不会丢小数。
ALTER TABLE "player_states" ADD COLUMN "cultivation_remainder_bp" integer DEFAULT 0 NOT NULL;
