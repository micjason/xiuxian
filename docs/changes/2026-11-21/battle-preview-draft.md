# 后台战斗预览草稿

战斗动画页改成两段：素材整理、战斗预演。只在后台看一次普通一击，不进游戏。

## 决定

- 草稿单独放在 `battle_preview_drafts`，帧文件放在 `BATTLE_PREVIEW_DIR`。不写 `animation_packs`、内容草稿、发布快照和玩家进度。
- 页面不提供发布、上线或同步到游戏。
- 竖屏比例用游戏画布 1080×2340，站位跟 `game/anim_q/battle_runtime/scripts/combat_cast.gd` 的脚底。检查画布仍是 640×320 棋盘格。
- 开发阶段其它配置仍是保存后即生效。这一页是例外，避免把看表现误写成线上动画。

## 代码

- 迁移 `backend/drizzle/0077_battle_preview_drafts.sql`。
- 接口在 `/admin/battle-preview/`。读不出来的 png 返回 400，不留下半套帧。
- 页面在 `admin/src/views/config/AnimationView.vue`。对拍计算有两份相同文件：`backend/src/modules/battle-preview/strike.ts` 和 `admin/src/battle-preview/strike.ts`，改一边时要同时改另一边。

## 还没做

- 游戏客户端不读这份草稿。
- 没有第二套预演，没有版本对比。
