# 换装整图与技能默认内容

分支：`proto/outfit-skill-defaults`  
迁移：`0062_outfit_skill_defaults`（journal `when: 1800200000000`，晚于 0061）  
设计：`docs/superpowers/specs/2026-10-29-outfit-skill-defaults-design.md`

## 决定

- `content_skills` 加 `fx_type`、`fx`、`cast_mode`。不新建技能表，不做技能树。
- 释放只有 `auto` / `passive`。不播种手动释放或大招技能。
- 九条默认技能的 `fx_type` 写资源真名。缺资源降级只在客户端。
- 换装按装备品质换整图：战斗 `preview_*`、打坐 `meditate_*`、头像 `avatar_*` 与圆图 `avatar_*_round`。五档白绿蓝紫橙都有图。分层 PNG 不接入。
- 技能图标优先用与 `fx_type` 同名的文件。界面「功法」改为「技能」，底栏仍是「洞府」。

## 还没做

- 战斗施法播放和 `anim_q/skill_fx` 归另一条分支。
- 分层 / Spine 换装未做。
- 本轮不部署、不灌线上库。
