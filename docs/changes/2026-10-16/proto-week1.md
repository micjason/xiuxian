# 原型第 1 周改动（分支 proto/week1）

1. 修为结算：整段时长 × 每节拍 × (1 + 加成) 只取整一次（整数万分比），余数存 `player_states.cultivation_remainder_bp`（迁移 0018）。8 小时 × 1/s × +15% = 33,120；在线 3 秒轮询 15 分钟 = 1,035。默认离线上限统一 28800。
2. 物品图标回退（`ArtLib.item_icon`）：`items/<slug>.png` → `gear_<境界>_<部位>.png` 或类别图 → `gear_<部位>.png` → 剪影占位。文件名清单见 `docs/ui/item_icon_fallback_spec.md`（35 张）。新增 `ArtLib.switch_tex()`（`ui/switch_on|off.png`，160×80，待美术交付）。
3. 首领限时默认 45 秒（全局一个值，后台“战斗公式与参数”可改；游戏读的是当前内容，保存即生效）。
4. `tools/sim/`：数值模拟脚本与第 1 周报告 `sim_report_week1.md`。
