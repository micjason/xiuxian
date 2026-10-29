# 2026-10-29 挂机刷出烟圈与首领自动技能表现

同步动画交付到 `game/anim_q/battle_idle/`、`game/anim_q/battle_boss/`、`game/anim_q/battle_hero/`。不改 skill_fx 九套、换装和技能 seed。

- 挂机：`monster_rig` 刷出时播放 `SpawnSmoke`（`fx/fx_smoke.png`）和 `SpawnRing`。历练页已接 `IdleBattle`，只更新资源。
- 首领：登场落地使用 `shake_strong`。`hp_trail` 在比例低于 30% 时闪红。页面刷新首领血量时调用 `_fx.set_boss_hp_ratio`。
- 蓄力：页面调用 `_fx.set_skill_charge`。`set_ult_charge` / `play_ult` 仍留在特效里作遗留名。剑扇只在自动事件 `kind:ult` 进入 `on_event` 时播放。
- 战斗页右侧圆盘只显示充能，文案是「冷却完自动释放」，`mouse_filter` 为忽略，没有点击释放。
- 战报前缀是「★ 自动技能 −」。玩家可见文案不用「大招」「暴击」当技能名；配置里的技能显示名仍可用。
