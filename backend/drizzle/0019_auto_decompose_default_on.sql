-- 设计表 3.7：满包自动分解默认开启（只分解没强化的白/绿装备，玩家可在背包里关闭）。
-- 旧语义是“新装备不如身上同部位的就分解”，语义已变，所以把旧账号的开关也重置为开。
ALTER TABLE "player_states" ALTER COLUMN "auto_decompose" SET DEFAULT true;
UPDATE "player_states" SET "auto_decompose" = true WHERE "auto_decompose" = false;
