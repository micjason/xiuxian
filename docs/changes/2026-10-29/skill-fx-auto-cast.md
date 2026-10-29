# 2026-10-29 自动施法播放九套 skill_fx

战斗保持全自动。不加重做充能圆盘、冷却条、百分比、技能按钮或「自动战斗」开关。可见蓄力仍只有主角脚下的聚气环，由已有的 `set_skill_charge` 驱动。

- 首领战自动技能出手（事件字段 `kind:ult` 是协议遗留名）和挂机飞剑命中，按该技能的 `fxType` / `fx.type` 调用 `SkillFxCast.play`。
- 九个真名：`slash`、`thunder`、`fire`、`heal_circle`、`ice`、`wind`、`poison`、`gold_light`、`shield`。
- 客户端只读内容配置。换 `fx_type` 就换场景，不写死技能 id。
- 未知 kind 收成斩；缺场景则不播。界面和战报不出现英文 kind，也不写「大招」。
- 战报名用技能中文名；空名或配置写成「大招 / 暴击」时显示「自动技能」。
