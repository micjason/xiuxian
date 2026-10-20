# 首领战特效 `battle_boss/`（10/20 交付，战斗特效第二部分）

接在**真实首领战页面** `scripts/ui/pages/battle_page.gd` 上，用的是页面原有的事件：
BossFight 的事件（我方普攻 / 我方大招 `kind:"ult"` / 首领攻击 `side:"boss"`）、`fight.finished / win / reason`。
复用第一部分的通用怪物模板 `anim_q/battle_idle/monster_rig.tscn`，所以**必须先接好 battle_idle**（已在仓库里）。

预览（真实页面、演示数据、Compatibility 渲染器 1080×2340）：
- `../preview/boss.mp4` / `boss.gif`：登场 → 普攻和首领攻击轮流 → 大招 → 胜利溶解 → 结算面板
- `../preview/boss_lose.mp4` / `boss_lose.gif`：失败（主角变灰下沉 + 「挑战失败」）
- `screenshot.png` / `screenshot.jpg`：游戏实际运行截图，大招打中那一刻

> 预览里为了缩短视频，把首领气血上限乘了 0.55（失败那段还把主角气血乘了 0.22）；**飘的数字全部是事件里的真实伤害**。
> 演示服务器的结算永远返回「挑战成功」，所以失败那段最后弹出的结算面板仍是成功，正式服务器不会这样。

## 效果内容
| 时机 | 表现 |
|---|---|
| 点「开始挑战」 | 战场压暗 + 四周红色暗角；斜 4° 的「首领来袭」横幅从左滑入、停留、从右滑出；主角头顶「!」；首领原地蓄力跳出画面，从上方落到红色虚线落点圈上（中等震屏 9px + 地面冲击环 + 尘土）。共 1.75 秒，**这段时间战斗时钟不走** |
| 我方普攻 | 飞剑从主角前方飞向首领（0.18 秒），命中：首领闪白 + 击退 + 挤压、斩击火花、轻微震屏 5px、伤害数字 |
| 我方大招（只有大招） | 背景压暗 + 主角脚下法阵；六把剑在主角头顶排成扇形 → 依次转向首领射出 + 月牙剑气横扫 + 速度线；最后一把剑打中时：强震屏 16px + 金色爆散 + **大号数字（digits_crit）**。没有任何文字标签 |
| 首领攻击 | 首领扑向主角，扑到时主角闪白 + 后仰 + 红色受击星 + 轻微震屏 + 主角身上红色伤害数字 |
| 首领攻击预警（可选，纯表现） | 每 `telegraph_every` 次首领攻击（默认 3），按实测出手间隔提前约 0.6 秒在主角脚下出红圈、首领身上泛红；打中时稍重一点。设为 0 关闭。不影响任何数值 |
| 双方血条 | 掉血时白色残影先停 0.3 秒再平滑追上（`hp_trail.gd`） |
| 胜利 | 首领连闪三下 → 溶解消失 + 金色爆散 → 「挑战成功」横幅；约 1.9 秒后再弹结算面板 |
| 失败 | 主角变灰（被打倒时再下沉 14px；超时不下沉）→ 「挑战失败」横幅；约 1.9 秒后再弹结算面板 |

- 伤害数字 = `BagModel.shown(event.damage)`（即四舍五入），和战报一致；**每个事件正好飘一次**（2 倍速下连着来也会排队，一个不少）。
- 数字、横幅、特效全部在战场 `_arena` 里面（战场本来就裁剪 `clip_contents`），数字最高只到战场顶部往下 40px，**不会盖住血条和名字**。
- 震屏只移动战场里的主角、首领和特效，页面背景、血条、战报、按钮都不动。
- 「暴击」两个字没有出现在特效里。⚠ 但页面原来的**战报**把大招行写成「★ 暴击 − …」（`scripts/ui/battle_report.gd` 第 13 行），见下面第 4 步。

## 接入步骤（开发）
1. **拷文件**：把本文件夹里的这些拷到 `game/anim_q/battle_boss/`：
   `boss_battle.gd`、`boss_battle.tscn`、`hp_trail.gd`、`art/`、`fx/`、`README.md`。
   （`screenshot.*`、`integration.patch`、`report_no_crit_word.patch`、`license_rows.csv`、`dev/` 不用拷进游戏。）
2. **授权表**：把 `license_rows.csv` 的 25 行追加到 `game/assets/art_q_license_list.csv`（`test_every_new_file_has_a_licence_row` 会检查）。
3. **改 battle_page.gd**：直接 `git apply anim_out_q/battle_boss/integration.patch`（在仓库根目录；已对当前仓库 dry-run 通过），或手动改这 9 处：
   - 顶部：`const BossBattleFx := preload("res://anim_q/battle_boss/boss_battle.tscn")`、`const HpTrail := preload("res://anim_q/battle_boss/hp_trail.gd")`、`var _fx: Node2D`
   - `_build_arena()`：`_float_layer` 加完之后、开始按钮之前：
     ```gdscript
     _fx = BossBattleFx.instantiate()
     _arena.add_child(_fx)
     _fx.attach(_arena, _arena.get_node_or_null("BattleHero") if _hero_art == null else _hero_art, _boss_art)
     ```
     （`attach` 在 `_init` 里调用也可以，会等进场景树后再挂；它会把背景层挪到战场最底下，首领改由怪物模板来画，`_boss_art` 隐藏、只当取图和定位用。）
   - `open_stage()`：设置完 `_boss_art` 的贴图 / 翻转 / 颜色之后 `_fx.set_boss_from_art()`
   - `_on_start()`：隐藏开始按钮后 `_fx.play_intro()`；`_process()` 开头（判断完 phase 之后）加 `if _fx.is_intro_playing(): return`（登场时不走时钟；`step()` 不受影响，单元测试照常）
   - `_process()` 和 `step()` 里 `fight.finished` 时：`_fx.play_result(fight.win, fight.reason)`
   - `_consume_events()`：`_float_damage(event)` 换成 `_fx.on_event(event)`（原来的 `_float_damage` 可以删掉，也可以留着不用）
   - `_set_bar()`：不要整块 `UiKit.clear(host)`，保留名为 `HpTrail` 的子节点，顺序 血条 → 残影 → 文字，每次 `trail.set_ratio(ratio)`（补丁里有完整写法；比例变大时会自动对齐，所以换关 / 再来一次不用额外重置）
   - `show_submit_error()`：最后加 `_fx.set_boss_from_art()`（首领回到待机）
   - `show_result()`：结算内容照常先建好，`_result_panel.visible = true` 之前加
     ```gdscript
     if _fx.is_result_playing() and is_visible_in_tree():
         await _fx.result_finished
         if phase != Phase.RESULT:
             return
     ```
4. **（建议）战报里去掉「暴击」**：`report_no_crit_word.patch`，把 `Kind.CRIT: "★ 暴击 −"` 改成 `"★ 大招 −"`（`test_ui_theme` 只检查 ★ 和加粗，仍然通过）。预览和截图里已经是改后的样子。改不改由负责人定。

我在仓库的副本里按上面接好后跑了全部 GUT：241 个测试 240 个通过，唯一失败的 `test_idle_battle.gd::test_kill_shows_gain_once_and_hides_hp_during_death` 在**没改过的仓库**上一样失败（无头模式下帧跑得太快，和本次改动无关）。

## 对外接口（`boss_battle.gd`，根节点 `BossBattleFx`）
| 方法 / 信号 | 说明 |
|---|---|
| `attach(arena, hero, boss_art)` | 挂到战场上（一次） |
| `set_boss_from_art()` | 从 `_boss_art` 取首领图、翻转、颜色，首领回到待机（开战前照常站着） |
| `play_intro()` → 信号 `intro_finished` | 登场；`is_intro_playing()` |
| `on_event(event)` | BossFight 的一个事件 |
| `play_result(win, reason)` → 信号 `result_finished` | 胜负表现；`is_result_playing()` |
| 信号 `number_shown(side, damage)` | 每飘一个数字发一次（`"boss"` = 打在首领身上，`"hero"` = 打在主角身上），给测试用 |
| 导出参数 | `shake_light` 5 / `shake_medium` 9 / `shake_strong` 16（px）、`telegraph_every` 3（0 关闭）、`number_top` 40 |

`hp_trail.gd`（Control）：`reset(ratio)`、`set_ratio(ratio)`；导出 `hold` 0.3 秒、`follow_speed` 7、`color` 白色 95%、`inset` 与 `UiKit.ratio_bar` 填充条一致。

## 性能（真实页面，opengl3 / Compatibility，演示数据 黑风岭·三，20 秒战斗）
| | 原页面 | 接入特效后 |
|---|---|---|
| draw call / 帧（平均 / 最多） | 134.4 / 140 | 138.0 / 153 |
| 渲染物体 / 帧（平均 / 最多） | 302.5 / 323 | 310.2 / 351 |
- 特效脚本每帧：平均 13.6 µs，最多 0.13 ms（含首领模板；桌面 CPU 测得，低端机按 5–10 倍估算也在 1.5 ms 以内）。
- 粒子：同时最多 50 个（飞剑拖尾 16 + 命中火花 10 + 爆散 24），全部 CPUParticles2D（Compatibility 渲染器安全）。
- 节点：78 个，全部预先建好循环复用（4 个首领伤害数字、3 个主角伤害数字、1 个大号数字、6 把大招剑、10 条速度线）；运行时不创建 / 释放节点、不用 Tween，`_process` 无内存分配；血条残影只在追赶时运行。原页面每个伤害数字都会新建 Label + Tween，接入后这部分没有了。
- 贴图共约 0.6 MB（PNG），最大的是三条横幅（1240×236）。

## 检查与重新生成
- 场景由 `../_preview_project/tools/build_boss.gd` 生成：`godot --headless --path _preview_project --script res://tools/build_boss.gd`
- 无头加载检查：`godot --headless --path _preview_project --script res://tools/load_check.gd`（battle_idle 两个场景 + boss_battle.tscn 78 个节点 + hp_trail.gd，无报错）
- `dev/`（开发用，拷到 `game/scripts/dev/` 再跑，不进游戏）：
  - `boss_fx_check.gd`：真实页面逐帧打完整场（胜 / 负），核对每个事件都飘了一次数字、数值 = round(damage)。结果：胜 45 个事件（含 2 次大招）、负 18 个事件（含 1 次大招），全部一致，结算面板在表现播完后弹出。
  - `boss_fx_movie.gd`：录预览视频 + 大招截图。
  - `boss_fx_perf.gd`：上面的性能数字（没接特效的原页面也能跑，用来对比）。
