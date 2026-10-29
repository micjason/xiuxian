# 技能特效模板 v2（可复用 · 九套）

对齐：`/workspace/q_design/SKILL_FX_PALETTE.md` + `q_skill_vfx_style_board.png`  
引擎：Godot 4 内置（`_process` 时间轴、CPUParticles2D、Sprite2D、CanvasItem additive）。无 Spine。  
输出目录：本目录。**未改** `xiuxian-ui` / 任何 worktree。

## 九套模板

| 文件 | 时长 | 主色 | 辅色 | 造型 / 挂点 |
|---|---|---|---|---|
| `slash_fx.tscn` | 0.55s | `#F5FBFF` | `#A8E8E0` | 1～2 道弧斩 + 短拖尾；目标身前 |
| `thunder_fx.tscn` | 0.75s | `#E8D6FF` | `#7B4DFF` | 1 主雷 + 2 枝叉 + 地面小圆闪；天顶→脚底 |
| `fire_fx.tscn` | 0.70s | `#FF9F43` | `#FF5A5F` | 亮芯 + 爆点 + 短火柱；默认 `heavy=true`；目标中心 |
| `heal_circle_fx.tscn` | 1.00s | `#5EE1C5` | `#FFE27A` | 脚底圆环 + 浅金描边 + 上升微粒；己方脚底 |
| `ice_fx.tscn` | 0.70s | `#D6F3FF` | `#7EC8FF` | 霜晶飞溅 + 淡蓝白闪 + 地面霜环；目标中心 |
| `wind_fx.tscn` | 0.60s | `#C8FFE8` | `#3DDC97` | 青绿弧斩 + 叶旋；目标身前 |
| `poison_fx.tscn` | 0.80s | `#B8FF6A` | `#7A4DFF` | 紫绿毒雾爆 + 上升气泡；目标中心 |
| `gold_light_fx.tscn` | 0.65s | `#FFF2C8` | `#FFD45C` | 金色径向爆开（增益/圣击）；目标中心 |
| `shield_fx.tscn` | 0.90s | `#A8E8E0` | `#FFD45C` | 青金穹顶气泡；**己方自身**（`target_offset≈0`） |

统一 API：

```gdscript
signal finished
@export var primary_color: Color
@export var secondary_color: Color
@export var fx_scale: float = 1.0
@export var target_offset: Vector2 = Vector2.ZERO
func play(at := Vector2.INF) -> void
func stop() -> void
func duration() -> float
func is_playing() -> bool
```

攻击法阵扩色：同一 `heal_circle_fx`，设  
`primary_color = Color("FFD45C")`、`secondary_color = Color("5AAEFF")`、`show_pillar = true`。

## 薄封装 `skill_fx_root.gd`

```gdscript
var n = SkillFxRoot.spawn("ice", parent, hit_pos)
n.primary_color = Color("D6F3FF")   # 可改
n.play()
await n.finished

SkillFxRoot.play_once("护盾", parent, hero_center)
SkillFxRoot.play_once("毒", parent, hit_pos)
```

支持中英别名：  
`slash/斩击/刀光`、`thunder/雷`、`fire/火`、`heal_circle/治疗/法阵`、`攻击法阵`、  
`ice/冰`、`wind/风`、`poison/毒`、`gold_light/金/金光/gold`、`shield/护盾`。  
规范名是 `gold_light`。九套 `*_fx.tscn` 都在时直接播真类型；缺文件才降级（ice→thunder、wind→slash、poison→fire、gold_light→slash、shield→heal_circle）。

## 全自动战斗怎么接

1. 把整个 `skill_fx/` 拷到客户端 `anim_q/skill_fx/`（含 `fx/` 贴图与 `.gd/.tscn`）。
2. 战斗页在**技能事件**到来时直接 `play`，**不要等按钮**。
3. 挂点建议：
   - 斩/风：目标身中偏前
   - 火/冰/毒/金光：目标中心
   - 雷：目标脚底，雷身向上
   - 治疗：己方脚底
   - 护盾：己方身中（`target_offset = Vector2.ZERO`）
4. 飘字仍走现有 float；本模板**不显示「暴击」**。
5. 低端机：`fx_scale = 0.85`。

批量扩技能：只换 `primary_color` / `secondary_color` / `fx_scale`。

## 预览与截图

| 用途 | 路径 |
|---|---|
| 九套同框（战斗页） | **`screenshot_board.jpg`** |
| 新五套同框 | **`screenshot_board_new.jpg`** |
| 单套峰值 | `screenshot_{slash,thunder,fire,heal,ice,wind,poison,gold_light,shield}.jpg`（均 <500KB） |
| 小图 | `small/*.jpg` |
| 另存 | `/workspace/skill_fx_shots_v2/` · `/workspace/anim_out_q/preview/stills/skill_fx_*.jpg` |

## 性能

- 节点：斩 7 / 雷 10 / 火 10 / 治疗 9 / 冰 9 / 风 7 / 毒 7 / 金光 7 / 护盾 7
- 粒子中低密度，`one_shot` / 用完即停
- 无 Spine；纹理 ≤420px；可池化

## 校验

```bash
Godot --headless --path /workspace/anim_out_q/_preview_project \
  --script res://tools/skill_fx_load_check.gd
# → SKILL_FX_LOAD_OK kinds=9
```

重建：`Godot --headless --path . --script res://tools/build_skill_fx.gd`  
录屏：`bash tools/render.sh skill_fx_board_new 2.0` / `skill_fx_board_all 2.0`

## 已知注意

- 火默认 `heavy=true`（赤炎）；非红底可 `heavy=false`。
- 色板修订优先改各脚本 `PRIMARY`/`SECONDARY` 与 `skill_fx_root.DEFAULTS`，再重渲截图。
