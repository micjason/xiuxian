# battle_runtime · 统一时间轴的 combat_slots 动画表现

## 当前实战接线（2026-11-08，基于 origin/dev2 5b1e3ea1）

此前单独改写 FogBattlePage 的方案已撤销。`game/scripts/ui/pages/fog_battle_page.gd` 与上游逐字相同：`extends TimelineBattlePage`，`open_battle(result)` 只做兼容包装并调用 `open_session`。不引入本地伤害/胜负模拟，不用演示替换缺失的服务器战报。

没有 `actor.tscn` 时，仍回落到 #68 的 `scripts/combat_cast.gd`（角色表动作 + 怪物关节网格）以及原有逐槽场景 / BossBattleFx。有统一 actor 时不会同时创建 CombatCast，避免双重角色。

真正的主场景使用同一个 `TimelineBattlePage` 同时承接历练与迷雾：`main.tscn → PlayScreen._on_fog_battle(session) → _battle_page.open_session`。兼容包装器路径另有回归验证。服务端 `/combat/start`、`BattleTimeline`、结算/跳过/撤退/状态/怒气仍由 #65 原系统负责；`BattlePage` 的 #66 确认稿 HUD、背景、首领名牌、战报 chips、返回和倍速版式没有改写。

### 表现层接口

- `CombatAnimationSlots` 优先查找 `res://anim_q/combat_slots/{player,boss}/actor.tscn`，每方只实例化一次，所有 slot 都发给该实例，保留呼吸和位移连续性。没有统一 actor 时，原 `{side}/{idle,attack,skill,ult,hit,win,lose}.tscn` 及 BossBattleFx 兜底分支保持可用。
- 两个 actor.tscn 都使用 `scripts/slot_actor.gd`，复用 `fighter_actor.gd` 与既有动作切片。idle 是单张定姿加代码呼吸；初速度、弹簧加速度、阻尼与受击短暂停顿提供动作质感，不慢放移动帧充当待机。
- attack → 普通攻击 + 小幅前探；skill/ult → 技能施放 → 技能攻击 → 加速飞行的独立剑气（玩家），怪物用可读的蓄势/前探。skill 飞行在每次触发时重新读取 `_fx.skill_impact_delay()`，与官方命中延迟对齐。
- hit 只由官方目标 hit slot 触发：受击、后坐、脚边半透明小爆炸；零伤害/闪避不捏造反应。命中通道不修改或重播攻击日志；没有 HP/胜负逻辑。动作结束自己收回站定并恢复呼吸，时间轴无需逐次补发 idle。
- win → 胜利，lose → 倒地；保留官方 `_fx.play_result()` 横幅及等待契约，避免 base page 立即隐藏 arena 导致胜负动作看不到。
- 倍速从适配器实时传给既有实例，×1/×2/×3 都影响帧采样、呼吸、惯性、受击和飞行。隐藏页面不推进 actor。

### 布局与去重

布局只使用实际 `_arena` 中段 flex 尺寸，左右 x 为宽度的 25% / 75%，共同脚底为高度的 66%；显示倍率取 `min(width/1080, height/800, 1)`，人物约280/怪物约300参考高度，不用旧全屏的 FEET_Y=1280。主场景实录 arena 为 1032×1182，最终显示高约268/287，保留宽技能间隔；小前探不冲过屏幕。

actor 接管本方时隐藏 HeroArt/BattleHero/BossArt 及 `_fx.hero_rig` / `_fx.boss` 的整个角色子树，保留 `_fx` 本身。其 intro/reset 可能重新显示旧角色，因此 actor 用较晚的 process_priority=100 在绘制前持续抑制旧本体；实录与回归确认恰好一名主角和一只怪物。适配器暴露真实 body_rect；TimelineBattlePage 只小改状态/HP条的定位数据源与新场景 idle 重置，旧 HUD 布局不动。

`fog_stage.gd` / `battle_director.gd` 是保留的独立参考 helper，实战不加载它们；不能用其 sample_result 替代线上权威时间轴。独立 `battle_demo.tscn` 保持原样可运行。

### 真实录制与验证

```bash
GODOT=/workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64
GAME=/workspace/xiuxian-ui/game
HOME=/tmp/gdhome_fog_slots "$GODOT" --headless --path "$GAME" \
  --script res://anim_q/battle_runtime/tests/verify_fog.gd
HOME=/tmp/gdhome_fog_capture FOG_CAPTURE_DIR=/tmp/fog_unified_frames \
  xvfb-run -a -s '-screen 0 1120x2400x24' "$GODOT" --path "$GAME" \
  --rendering-driver opengl3 --resolution 1080x2340 --fixed-fps 30 \
  --script res://anim_q/battle_runtime/scripts/capture_fog.gd
ffmpeg -y -framerate 30 -i /tmp/fog_unified_frames/%04d.jpg \
  -vf 'scale=in_range=full:out_range=limited,format=yuv420p' -color_range tv \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -movflags +faststart \
  "$GAME/anim_q/battle_runtime/preview/fog_battle.mp4"
```

录制先进入主场景现有 fog 导航，再将合法 `{playback, battle:{log}}` fixture 传给生产入口。完整使用官方 BattleTimeline、延迟命中、mock 结算链路（不联网），不是直接驱动参考导演。输出1080×2340、30fps、360帧/12秒；`fog_idle/attack/cast/skill/impact/hit/recover/finished.png` 与 `fog_validation.json` 更新为此真实路径；视频仅本地。旧 `layout_1080x2340.png` / `demo_anim.mp4` 不覆盖。

回归覆盖：包装器仍是官方时间轴、每方一个持久 actor、旧本体不可见、idle 不换步、代码呼吸/惯性/停顿、普通/技能/受击/恢复/胜负、当前官方命中延迟、×2/×3即时生效、真实HP/状态锚点、新场景归位、缺失统一 actor 的原兜底契约，以及表现层不更改服务器HP。另运行原 `verify_demo.gd` 和 `tests/unit/test_battle_timeline.gd`。

已知限制：怪物暂复用熊王静图，由代码提供动作，未做所有怪物的独立帧；原主角约130px高，放大较软。沿用确认稿的场景/薄荷底板，不调整背景流水线。主场景退出仍有既有壳层资源释放警告，单独 slot 回归不产生此警告。用户动作原图的商用授权仍需提供者确认。未推送、部署、改版本或做手机构建。

---

## 历史独立参考演示（以下时间轴不用于实战）

## 动作与切片

`art/hero_sheet.png` 是用户提供的 1536×1024 RGBA 动作表。它**已有透明度，不是绿幕**：源 alpha 为 0–254，440547 像素完全透明；可见区域几乎没有绿优先像素。不能把青色衣服/剑气当绿幕抠除。脚本清除 alpha≤10 的杂点、重映射有效 alpha、移除小孤岛和金色标题；保留柔和的青白光效。

执行 `python3 anim_q/battle_runtime/scripts/slice_sheet.py` 可复现切片（依赖 Pillow、NumPy、SciPy）。原图只读。源坐标、帧数、脚底信息在 `frames/manifest.json`，检查图在 `preview/sheet_slices_contact.png`。

|人物动作|帧数|人物动作|帧数|
|---|---:|---|---:|
|移动|7|奔跑|4|
|冲刺|3|跳跃|3|
|普通攻击|5|技能攻击|4|
|技能施放|5|受击|4|
|倒地|5|胜利|3|

独立 FX：特效素材 3、技能特效-剑气 7、技能特效-爆炸 6。合计人物 43、FX 16。文件命名为 `frames/hero/<动作>/00.png`、`frames/fx/<名称>/00.png`。

人物统一 640×320 透明画布，脚底锚点 `(240,280)`，站立参考高 130 源像素，统一缩放到 `HERO_DISPLAY_H=280`，不逐帧等高拉伸。动画资源设为 11 fps；idle 使用更静止的移动帧 `2,3,4,3`，以 0.22 倍速加轻微呼吸伸缩，脚底不漂移。没有从原表的待机标题生成另一组 idle。

## 时间轴（单次 12 秒，结束保持 idle）

- 0–2s：调息；2–2.65s：普通攻击。
- 3.1–4s：施法；4–4.8s：技能攻击。
- 4.35–5.5s：剑气飞向熊王；5.4–6.15s：熊王胸口爆炸。
- 停顿后 7.5–8.55s：熊王方向的反击 FX；8.45–9.2s：剑修受击。
- 9.2s 后：回到 idle，不循环触发攻击。

主角节点是 `AnimatedSprite2D + SpriteFrames`，统一时间采样控制帧。固定脚底 `(260,1280)`，不冲到敌人前。右侧仍为现有熊王 `Sprite2D`，脚底 `(820,1280)`，高度 300；不使用人物图表冒充怪物帧。无技能/大招按钮。战报跟随时间轴更新。

## 运行与真实渲染录制

```bash
GODOT=/workspace/tools_ui/Godot_v4.7.2-stable_linux.x86_64
GAME=/workspace/xiuxian-ui/game
$GODOT --headless --path "$GAME" --rendering-driver opengl3 --editor --import
HOME=/tmp/gdhome_battle_runtime xvfb-run -a -s '-screen 0 1120x2400x24' \
  $GODOT --path "$GAME" --rendering-driver opengl3 --resolution 1080x2340 \
  --fixed-fps 30 --script res://anim_q/battle_runtime/scripts/capture_demo.gd
ffmpeg -y -framerate 30 -i /tmp/battle_runtime_capture_frames/%04d.jpg \
  -vf 'scale=in_range=full:out_range=limited,format=yuv420p' -color_range tv \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -movflags +faststart \
  "$GAME/anim_q/battle_runtime/preview/demo_anim.mp4"
```

`capture_demo.gd` 真实加载此场景并采样 360 帧 / 12s，而非图片拼贴。中间帧默认写入 `/tmp/battle_runtime_capture_frames`（可用 `BATTLE_CAPTURE_DIR` 环境变量更换）。同步导出 `demo_idle.png`、`demo_attack.png`、`demo_skill.png`、`demo_hit.png`。视频无音轨。历史 `preview/layout_1080x2340.png` 保持不变。

## 质量与限制

原表人物仅约 130px 高，放大后比熊王略软；部分技能光圈/烟尘与角色本身烘焙在一起，保留在对应人物帧，飞行剑气与胸口爆炸另用独立 FX 帧。少数相邻光效的源图边缘本身重叠，不能恢复被遮挡的原画。上述历史场景只是独立演出预览；实战接线见本文件顶部。尚未做本次手机构建。用户提供图的权属/商用许可未独立核验，发布前需确认。

回归校验：`$GODOT --headless --path "$GAME" --script res://anim_q/battle_runtime/scripts/verify_demo.gd`。切片脚本另含画布/边界/外来衣袖与剑弧回归断言。中间帧采用高质量 JPEG，四张成品静帧仍直接保存为 PNG。
