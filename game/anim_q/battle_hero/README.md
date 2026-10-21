# 主角战斗动画 `battle_hero/`（10/21 晚交付）

美术的战斗姿势 `sprites/player_fight.png` 只有一帧（朝右，636×635，脚底约在图内 x318、y600，SPEC_Q §17.8），没有分层。
所有动作都用 Godot 自带节点 + 两个 shader 在这一帧上做出来，不需要新美术。

预览：`../preview/hero_battle.mp4` / `hero_battle.gif`（真实首领战页面、演示数据黑风岭·三，首领血量 ×0.42 缩短，完整一场：登场 → 普攻 → 受击 → 蓄力 → 自动大招 → 胜利）。
截图（真实页面，Godot opengl3 渲染，png 原图 + <1MB jpg）：
- `screenshot_attack_hit.jpg`：普攻飞剑命中（主角前冲停在最前，首领闪白，飘 -53）
- `screenshot_ult_charge.jpg`：大招蓄力 95%（脚下聚气环快满、金色，身体青色外光，灵气上升，剑尖闪光）
- `screenshot_ult_release.jpg`：自动释放（主角蓄势结束，剑扇飞向首领）
- `screenshot_ult_impact.jpg`：剑扇打中（月牙剑气 + 大号数字）

## 动作一览
| 动作 | 怎么触发 | 表现 |
|---|---|---|
| 待机 | 自动循环 | 2.4 秒一次呼吸（以脚底为轴竖向 ±2% 挤压）+ 轻微起伏；上身慢慢左右摆；衣袖、衣摆、发梢按离身体中线的距离飘动（剑身区域不飘） |
| 普攻 | `play_attack()` | 0.09 秒前冲 + 前倾（`attack_release` 信号），停到 0.2 秒等飞剑命中，0.4 秒回位；飞剑由 `boss_battle` 发出，命中后**弧线飞回主角手边** |
| 蓄力 | `set_ult_charge(v)`（0..1） | 脚下聚气环（前后两半，前半圈盖在脚上）从后方 12 点顺时针填满，青 → 金；身后青光变亮；灵气粒子上升；>55% 身体出青色外光；≥88% 整环脉动 + 剑尖闪光 |
| 大招 | `play_ult()`（返回蓄势秒数 0.32） | 后仰压低蓄势（环闪亮、气往剑上收、身体微闪）→ `ult_released` 信号 + 猛地前送 + 地面冲击环 → 聚气环 0.35 秒清空。`boss_battle` 收到 ult 事件时自动调用，剑扇推迟 0.32 秒出现 |
| 受击 | `play_hit(heavy)` | 闪白 + 往后击退（18 / 预警重击 26 像素）+ 后坐挤压回弹，0.32 秒 |
| 失败 | `play_defeat()` | 变灰、后仰下沉、聚气环和粒子停掉 |
| 胜利 | `play_victory()` | 小跳 + 落地挤压 + 剑尖闪光 |
| 复位 | `reset()` | 回到待机、蓄力清零 |

信号：`attack_release`（出剑那一刻）、`ult_released`（蓄势结束、大招放出）、`hit_finished`。
导出属性：`box`（显示框，默认 440×440，图等比缩放）、`face`（1 = 朝右）、`breathe` / `bob_px` / `sway_amount`（待机幅度）、`ring_width`、`charge_color` / `full_color`、`body_glow`（蓄力身体外光，特别低端的机器可关）。

## 开发怎么接（首领战斗页）
**不用自己摆主角动画。** `boss_battle.attach(_arena, 主角节点, _boss_art)` 时，如果主角节点是贴图为 `player_fight*.png` 的 TextureRect（现在的 `HeroArt`，`HERO_POSE_HOOK = "player_fight"`），
特效会自动在同一位置换成 `hero_battle.tscn`（原 TextureRect 变透明，只用它的框定位：脚底 = 框底边中点），之后普攻 / 受击 / 大招 / 胜负都由特效驱动。
也可以直接把 `hero_battle.tscn` 实例当主角节点传进去。不想用动画就把 `_fx.use_hero_rig = false`（退回原来的整体位移 + 染色）。

页面要加的只有大招蓄力（`integration_hero.patch`，2 处，已对 `proto/batch4-boss` 工作区当前的 battle_page.gd 检查过能打上）：
```gdscript
# _refresh_ult() 里，和 _ult_disc.set_charge 一起：
_fx.set_ult_charge(fight.ult_charge() if phase == Phase.RUNNING else 0.0, true)
# 没有大招时：
_fx.set_ult_charge(0.0, false)
```
蓄满由 BossFight 自动施放（ult 事件），页面照旧把事件交给 `_fx.on_event(event)`，**不需要也不应该**自己调 `play_ult()`。

建议同时打 `integration_hero_optional.patch`（血条和剑同步）：大招事件一到页面就扣首领血条，但剑扇要约 1.2 秒后才打中（蓄势 0.32 + 剑扇停留 0.48 + 依次射出 + 飞行），
看起来血先掉了。补丁记下未落地的大招伤害 `_ult_pending`，等特效新信号 `ult_landed(damage)` 再扣；开打 / 撤退时清零。`_fx.ult_impact_delay()` 返回这段时间。

### 页面事件对应
| 页面里发生的事 | 调用 | 主角表现 |
|---|---|---|
| `_on_start()` → `_fx.play_intro()` | （不变） | 待机，首领登场 |
| `_consume_events()` → `_fx.on_event(e)`，我方普攻 | （不变） | 前冲出剑，飞剑命中后飞回 |
| 同上，首领攻击 | （不变） | 首领扑击落下那一刻：闪白 + 击退 + 后坐（预警重击更重） |
| 同上，`kind == "ult"` | （不变） | 蓄势 0.32 秒 → 剑扇 → 大号数字 → `ult_landed` |
| `_refresh_ult()` | **新增** `_fx.set_ult_charge(...)` | 聚气环 / 外光 / 粒子跟着圆盘填 |
| `fight.finished` → `_fx.play_result(win, reason)` | （不变） | 赢：首领溶解后主角小跳；输：主角变灰后仰 |
| `abort()` / `show_submit_error()` → `_fx.set_boss_from_art()` | （不变） | 内部 reset，主角回待机、蓄力清零 |

## 要拷的文件
1. `anim_q/battle_hero/` 新目录：`hero_battle.gd`、`hero_battle.tscn`、`hero_fight.gdshader`、`qi_ring.gdshader`、`art/player_fight.png`（场景默认图；接页面时用的是页面自己的 `sprites/player_fight.png`）、`README.md`。
   特效贴图复用 `anim_q/battle_boss/fx/`（fx_glow / fx_shadow / fx_dot / fx_star / fx_ring），不新增。
2. `anim_q/battle_boss/` 覆盖：`boss_battle.gd`（主角动画接管、`set_ult_charge`、`ult_landed`、`ult_impact_delay`、飞剑飞回、首领统一）、`boss_battle.tscn`（未改结构，一起拷）。
3. `anim_q/battle_idle/monster_rig.gd` 覆盖：基于你们工作区的版本（含 `fx_variant` 和直接用 `boss_*.png` 的那一段），另外加了：页面给的是 `mon_X.png` 时也会自动找同目录的 `boss_X.png`（放大倍数按尺寸反推 1.2 / 1.0）。
4. `battle_page.gd`：`integration_hero.patch`（必须）+ `integration_hero_optional.patch`（建议）。
5. 授权表：`license_rows_hero.csv` 的 6 行追加到 `game/assets/art_q_license_list.csv`（5 行自有代码 + `anim_q/battle_hero/art/player_fight.png` 一行，照抄美术 `license_q.csv` 的 A 类：AI 生成，商用条款【尚未确认】）。
   `sprites/player_fight.png`、`sprites/boss_*.png`（9）、`bg/bg_battle_*_1080x1640.webp`（3）这 13 行你们工作区已经加过；合到别的分支时记得一起带上（来源同 `license_q.csv`）。

## 性能（低端安卓）
- 运行时不建节点、不用 Tween、`_process` 不分配内存；shader 参数只在变化时才设。脚本平均约 4 µs / 帧（桌面 CPU，`_preview_project/tools/hero_bench.gd`）。
- 绘制：身后光、阴影、聚气环（后 / 前两半）、身体、灵气粒子（18 个）、蓄势粒子（14 个，只在蓄势 0.32 秒里发）、剑尖闪光、冲击环（各自只在用到时显示）——比原来一张 TextureRect 多约 5–8 个 draw call。
- `hero_fight.gdshader`：平时每像素 1 次采样（摆动只是改 UV）；蓄力 > 55% 时透明像素各 24 次采样做外光（身体内部跳过），440 框约 0.24M 像素。真机掉帧时设 `body_glow = false`，其余效果不变。
- 聚气环 `qi_ring.gdshader` 不采样贴图，纯计算，只覆盖脚下约 420×110 像素。
- GPU 耗时在本机（软件渲染）测不出来，需要真机看一眼。

## 校验（临时副本 = `proto/batch4-boss` 工作区当前代码 + 本交付 + 两个补丁 + 6 行授权，不动原仓库）
- 无头加载：`hero_battle.tscn`（11 节点）、`boss_battle.tscn`（82）、`monster_rig.tscn`（8）、`idle_battle.tscn`（57）无报错；`load_check.gd` 用 player_fight TextureRect 接首领战：自动换成主角动画、tier 恒为 2、`ult_landed` 收到正确伤害（88）。
- 数字核对（`dev/hero_fx_check.gd`，真实页面逐帧打完整场）：黑风岭·三 胜 48 个事件（含 2 次大招）、负 18 个事件（含 1 次大招），每个事件飘一次数字、数值 = round(damage)，结算面板在表现播完后弹出。
- 全量 GUT（`-gdir=res://tests`）：270 / 270 通过。（只单独跑 `test_q_fx.gd` 时 11 条因引擎字体报错「Error loading font ''」失败，未改动的工作区副本单独跑也一样，是单文件运行环境问题，和本交付无关。）
- 整页 draw call（opengl3，演示数据，12.5 秒一场）：平均约 165、最多 189（主角动画 + 首领战特效 + 页面全部）。
- 页面布局：用的是工作区当前的 `HERO_SIZE = 390`、主角框贴着战场下沿；脚下空间不够时聚气环自动往上挪（`ground_room`，boss_battle 自动设），整圈可见，但环会落在小腿附近。设计稿主角脚底离场景下沿约 88 像素，框往上抬一些环会更像在地上。
- 录屏 / 截图脚本：`dev/hero_fx_movie.gd`、`dev/hero_fx_check.gd`（拷到 `game/scripts/dev/` 用，开发工具，不进游戏）。
