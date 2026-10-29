# 历练页 挂机打小怪特效（战斗特效第一部分）

首领战特效是第二部分，后面单独交付。这一部分**只管挂机刷小怪**。
全部用 Godot 4 自带功能（Sprite2D、CPUParticles2D、一个很小的着色器、GDScript），**不用插件**，兼容 Compatibility 渲染器。

- 预览视频：`../preview/battle.mp4` / `battle.gif`（也可 `preview/battle.mp4` 软链；1080×2340，叠在历练页上，Godot 实际录制）
- 截图（Godot 实际渲染，不是拼图）：
  - `screenshot.jpg` / `screenshot.png` 总览（命中瞬间）
  - `screenshot_hit.jpg` 命中：闪白 + 击退压扁 + 火花 + 伤害数字
  - `screenshot_death.jpg` 死亡：溶解成灵气
  - `screenshot_death_peak.jpg` 溶解峰值特写：灵气正飞向主角（负责人验收）
  - `screenshot_spawn.jpg` / `screenshot_spawn_smoke.jpg` 刷出：白剪影淡入 + **脚下烟圈**

## 效果内容
1. **怪物待机**：上下轻浮 + 呼吸缩放，脚下影子跟着变大变小（任何单张怪图都能用，不需要拆层）。
2. **主角出手**：主角身体前倾，飞剑从身边飞出、拖青色剑气，命中后弹回原位继续悬浮。
3. **命中**：十字斩光 + 星芒 + 一圈光环 + 10 粒火花；怪物**整只闪白**、往后击退、压扁一下；伤害数字（美术的 digits_dmg 位图字体，橙色底影）弹出上飘。
4. **怪物反击**（默认每 4 刀一次）：怪物往前一扑，主角发亮、往后一晃。**挂机没有主角血量，所以不飘数字。**
5. **击杀**：最后一刀补齐剩余血量 → 怪物闪白 → 从头往下溶解成青色灵气（发光边）→ 12 颗灵气球沿弧线飞进主角 → 主角头上「+N 修为」→ 地面一圈光环。
6. **掉落**：掉落物从怪物身上弹出、落地弹两下，再沿弧线飞进底栏背包，到达时发出 `drop_arrived` 信号。
7. **下一只刷出**：白色剪影放大淡入，变回正常颜色；**脚下烟圈 + 轻烟粒子**（`SpawnRing` + `SpawnSmoke`，约 0.45s）。

**规则（负责人要求）：**
- **伤害数字加起来正好等于怪物的配置气血**：每一刀的数字 = 血条掉下去的那一段 × 配置气血，最后一刀补齐余数。已用 5 种速度测试（每只 0.5～6 秒、气血 7～99999、含服务器进度回跳），全部一致，测试脚本 `_preview_project/tools/test_battle.gd`。
- 为了不飘「-3」这种碎数字，血条至少掉 5% 才出一刀（等满两个间隔就有多少打多少）。
- **没有暴击**：任何地方都不会出现「暴击」两个字，也不用大号数字（大号样式留给首领战大招）。
- **不挡怪物名牌和血条**：名牌和血条在设计稿 y 432–484；伤害数字的上沿被限制在 y ≥ 500（`number_top_limit`），火花、灵气、粒子也都在这条线下面。建议把特效节点加在名牌和血条**之前**（见下面第 2 步），这样即使有东西经过，名牌和血条也画在最上面。

## 文件
| 文件 | 说明 |
|---|---|
| `idle_battle.tscn` + `idle_battle.gd` | **主场景**：挂机战斗特效总控（飞剑、火花、伤害数字、灵气、掉落、修为飘字），里面包含一只怪物模板 |
| `monster_rig.tscn` + `monster_rig.gd` | **通用怪物模板**：任意 `mon_*.png` 都能用；首领战以后也用它 |
| `monster_fx.gdshader` | 怪物闪白 + 溶解的着色器 |
| `art/` | 飞剑 `sword.png`（= icons/icon_sword）、伤害数字字体 `digits_dmg.fnt/png`、修为字体 `digits_xiuwei.fnt/png`、`float_word_xiuwei.png`；`icon_stone.png`、`it_bone.png` 只给预览用 |
| `fx/` | 特效小图（光点、斩光、星芒、光环、影子、噪声图、**烟 `fx_smoke.png`**），程序生成，可以让美术同名替换 |

整个 `battle_idle/` 文件夹拷到游戏工程 `res://anim_q/battle_idle/`（和第一批动画一样放在 `anim_q/` 下面，场景里的路径就是这个）。

## 接进历练页（StagePage，`game/scripts/ui/pages/stage_page.gd`）
下面是按仓库现在的代码写的，**我没有改仓库**，都由开发来接。

**第 1 步：加变量**
```gdscript
const IdleBattle := preload("res://anim_q/battle_idle/idle_battle.tscn")
var _battle_fx: Node2D
```

**第 2 步：在 `_build_scene()` 里创建**：加在 `_monster = _sprite(...)` 这一行**之后**、`name_chip`（怪物名牌）**之前**，这样名牌和血条画在特效上面：
```gdscript
_battle_fx = IdleBattle.instantiate()
_battle_fx.position = -ORIGIN          # 场景里全部用设计稿坐标，减掉页面原点就对齐了
_scene.add_child(_battle_fx)
_monster.visible = false                # 目标怪改由特效里的怪物模板来画（TextureRect 留着，只用来取贴图）
```
- 同时把 `_build_scene()` 里那把装饰飞剑（`sword` 那个 TextureRect，位置 470,600）去掉或隐藏，因为特效里自带会飞的剑。
- 主角绑定：把 `var hero := QHero.new(false, false)` 那段里放好位置后加一行 `_battle_fx.bind_hero(hero)`（要在 `_at(hero, ...)` 之后调用，出手时会让主角前倾、被反击时发亮）。

**第 3 步：在 `_render_scene()` 末尾设置当前怪物**（每次换关、换怪时都会走到这里）：
```gdscript
var mon: Dictionary = _wave().get("monster", {}) if typeof(_wave().get("monster", null)) == TYPE_DICTIONARY else {}
_battle_fx.set_monster(_monster.texture, _monster.flip_h, int(mon.get("hp", 0)), float(shown.get("kill_cultivation", 0)))
_monster.visible = false
```
- 气血用 `wave.monster.hp`（配置值，例如毒牙蟒 520），伤害数字加起来就等于它。
- 第 4 个参数是每只击杀修为，大于 0 时，灵气飞到主角时会飘「+N 修为」。贴图或气血变了才会重新刷怪，重复调用没关系。

**第 4 步：在 `_refresh_wave(shown)` 里每帧同步**（这个函数已经每帧被 `_process` 调用）：
在 `_monster_hp.set_ratio(...)` 那一行后面加：
```gdscript
_battle_fx.sync(1.0 - (progress - floorf(progress)), kills)   # 和血条同一个值、本波击杀数
_monster_hp.visible = _battle_fx.monster_showing() and _monster_chip.get_parent().visible   # 可选：怪物溶解到下一只刷出前先藏血条
```
- **把原来的 `_float_gain(...)` 调用删掉**（或者第 3 步第 4 个参数传 0，二选一）。否则「+N 修为」会飘两次。
- 击杀判断：击杀数变了，或者血条突然回满，都算一只怪死了。击杀很快的时候（一只不到 1.5 秒），特效来不及每只都播完，最多补播 2 只，不影响数值。

**第 5 步（可选）：掉落物飞进背包**
- 服务器结算里有真实掉落时（`lastSettle.drops`，在 `bind()` 拿到新状态的时候），把这些物品的图标传进来：
  `_battle_fx.queue_drops([图标1, 图标2])`（最多 3 个），下一只怪死的时候会弹出来，然后飞进背包。**只传真实掉落**，没有就不传，不会凭空弹东西。
- 背包位置：`_battle_fx.bag_target_global = 背包页签按钮.get_global_rect().get_center()`（默认 (972, 2190) = 1080×2340 画布上底栏背包的中心）。
- 每到一件会发出 `drop_arrived` 信号，可以接第一批的 `float_drop/bag_pulse.tscn` 的 `hit` 动画，让背包图标跳一下。
- 掉落物是 `top_level` 节点，用全局坐标飞。如果飞到底栏时被底栏盖住，把 `Drops` 节点的 `z_index` 调高，或者挪到更上层的 CanvasLayer。

## 可调参数（检查器里直接改 `IdleBattleFx` 节点）
| 参数 | 默认 | 说明 |
|---|---|---|
| `monster_rect` | (560,510,340,370) | 目标怪显示框，和页面 TargetMonster 一样 |
| `hero_chest` | (204,660) | 灵气飞去的位置、主角受击星芒位置 |
| `sword_home` | (400,610) | 飞剑悬浮待机的位置 |
| `hit_interval` | 0.9 | 两刀之间最短间隔（秒） |
| `counter_every` | 4 | 每几刀怪物反击一次，0 = 不反击 |
| `number_top_limit` | 500 | 伤害数字上沿最高到哪（名牌、血条在它上面） |
| `bag_target_global` | (972,2190) | 掉落物飞去的全局坐标 |
| `kill_gain` | 0 | 击杀修为（一般用 `set_monster` 的第 4 个参数设） |

## 方法 / 信号一览
- `set_monster(tex, flip, hp, gain = -1)`：设置当前怪物（贴图、是否翻转、配置气血、每只修为）。
- `sync(hp_ratio, kills)`：**每帧调用**。hp_ratio = 当前这只怪剩余血量比例（1 = 满血），kills = 本波击杀数。
- `bind_hero(node)`：绑定主角节点（QHero）。
- `queue_drops(icons)`：下一只怪死亡时弹出的掉落图标。
- `monster_showing()`：目标怪当前是否显示着。
- 信号：`hit_landed(damage)` 一刀命中、`monster_died` 溶解完毕、`spirit_arrived(gain)` 灵气到达主角、`drop_arrived` 一件掉落到达背包。
- 怪物模板 `monster_rig`（首领战也会用）：`set_texture(tex, flip)`、`spawn()`、`hit(strength)`、`attack()`、`die()`、`is_alive()`、`is_busy()`；信号 `spawned`、`attack_impact`、`died`。

## 性能（低端安卓）
- **粒子（全部 CPUParticles2D）**：剑气尾迹 20 + 死亡灵气 14 + 命中火花 10 + 掉落尾迹 3×8 = **最多 68 粒**，实际同屏一般 20～40 粒。另外 12 颗灵气球是预建好的普通图片，不是粒子。
- **绘制调用**（只算特效层，Godot Compatibility 渲染器实测 12 秒，含死亡和 3 件掉落同时飞）：**最多 24、平均 13**；画布对象最多 30 个。
- **脚本耗时**：每帧 sync + 特效逻辑平均 **约 8 微秒**，最多 0.14 毫秒（桌面 CPU 实测；低端手机按 10 倍估算也不到 1.5 毫秒）。
- **没有每帧内存分配**：53 个节点全部在场景里预先建好，伤害数字 4 个、灵气 12 个、掉落 3 个循环复用；运行时不创建也不删除节点，不用 Tween；着色器参数只在数值变化时才设置。
- 着色器只有一次噪声采样和几次混合，只作用在一张怪物图上。没有全屏特效、模糊或后期处理。
- 页面不可见时特效自动暂停（`is_visible_in_tree()` 为 false 时不运行）。
- 图片都很小（特效图 32～256 像素，飞剑 256 像素），显存约 1 MB。

## 已验证
- 两个场景在 Godot 4.7 headless 下加载、实例化无报错（`_preview_project/tools/load_check.gd`）。
- 伤害数字合计 = 配置气血：5 组速度共 80 只怪全部一致（`tools/test_battle.gd`）。
- 性能统计：`tools/perf_battle.gd`（绘制调用）、`tools/bench_battle.gd`（脚本耗时）。
- 预览：`_preview_project` 里用 `bash tools/render.sh battle 10` 重新录。预览里血条、本波圆点由预览脚本模拟 StagePage 每帧传值，主角用和 QHero(false,false) 一样的摆法。
- 重新生成场景：`godot --headless --path _preview_project --script res://tools/build_battle.gd`。

## 注意
- 页面血条是连续往下掉的，特效出刀是一段一段的，所以血条会比数字略早一点掉；最后一刀和死亡之间，血条已经换成下一只的满血（可以用第 4 步的 `monster_showing()` 先把血条藏起来）。
- 远处那只小怪（`_monster_far`）不动，保持原样。
- 主角只有打坐一种姿势，出手是「打坐御剑」，用的是前倾加飞剑，不需要新画攻击动作。

## 10/21 新增：怪物档次 `tier`（精英 / 章末首领）
- `monster_rig` 新增导出属性 `tier`：0 普通（默认，和以前完全一样）/ 1 精英 / 2 章末首领；`use_baked_outline`（默认 true：有 `elite_X.png` / `chief_X.png` 预渲染图就用，没有就用实时描边 shader `monster_tier.gdshader`）；`plate_gap`、`show_plate`（名牌）。
- 详细说明、要拷的文件和授权行见 `../battle_boss/README.md` 的「10/21 新增」一节。
- 10/21 晚：首领统一后，`tier = 2`（首领）优先用统一首领立绘 `boss_<怪>.png`：页面直接给 `boss_*.png` 时原样使用（已带首领描边，不再套 shader）；给 `mon_<怪>.png` 时自动找同目录 `boss_<怪>.png`（放大倍数按尺寸反推 1.2 / 1.0），没有再找旧的 `chief_*`，最后才用实时 shader。`monster_rig.gd` 基于开发工作区的版本（含 `fx_variant`）改的。精英档（tier = 1）不再使用。

## 10/29 补缺：刷出脚下烟圈（相对 PLAN §1）

对照 `battle_plan/PLAN.md` §1 核对后：

| PLAN 项 | 状态 |
|---|---|
| 命中：闪白 / 击退压扁 / 十字斩光+火花 / 伤害数字 | **已有**（idle_battle + monster_rig） |
| 死亡：溶解灵气飞主角 / 掉落弹出 / drop_fly | **已有** |
| 刷出：白剪影淡入 | **已有** |
| 刷出：脚下烟圈 | **本次补上**（`monster_rig` 的 `SpawnSmoke` 12 粒 + `SpawnRing`） |
| 血条白色残影 | 挂机血条在页面侧；组件见 `../battle_boss/hp_trail.gd`（本批不改页面） |
| 远处小怪前移 / 本波圆点亮 | 页面侧，特效层不管 |

未改仓库、未改工作区。重新生成：`godot --headless --path _preview_project --script res://tools/build_battle.gd`；重录：`bash tools/render.sh battle 12`。
