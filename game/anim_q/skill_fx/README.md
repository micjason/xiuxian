# 技能特效模板 v1（可复用）

对齐：`/workspace/q_design/SKILL_FX_PALETTE.md` + `q_skill_vfx_style_board.png`  
引擎：Godot 4 内置（AnimationPlayer 时间轴用 `_process`、CPUParticles2D、Sprite2D、CanvasItem additive）。无 Spine。  
输出目录：本目录。**未改** `xiuxian-ui` / 任何 worktree。

## 四套模板

| 文件 | 时长 | 主色 | 辅色 | 造型 / 挂点 |
|---|---|---|---|---|
| `slash_fx.tscn` | 0.55s | `#F5FBFF` | `#A8E8E0` | 1～2 道弧斩 + 短拖尾；目标身前 |
| `thunder_fx.tscn` | 0.75s | `#E8D6FF` | `#7B4DFF` | 1 主雷 + 2 枝叉（不密）+ 地面小圆闪；天顶→脚底 |
| `fire_fx.tscn` | 0.70s | `#FF9F43` | `#FF5A5F` | 亮芯 `#FFF2C8` + 更大爆点 + 短火柱（浅青白描边）；焦痕小；默认 `heavy=true`（赤炎）；目标中心 |
| `heal_circle_fx.tscn` | 1.00s | `#5EE1C5` | `#FFE27A` | 脚底圆环 + 浅金描边 + 上升微粒；己方脚底 |

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
var fx = preload("res://anim_q/skill_fx/skill_fx_root.gd")
# 或把脚本当 static 工具用：
var n = SkillFxRoot.spawn("slash", parent, hit_pos)
n.primary_color = Color("F5FBFF")   # 可改
n.play()
await n.finished

# 更省事（播完 queue_free，池化前）
SkillFxRoot.play_once("雷", parent, feet_pos)
```

支持中英别名：`slash/斩击/刀光`、`thunder/雷`、`fire/火`、`heal_circle/治疗/法阵`、`攻击法阵`，以及可扩展枚举 `ice/冰`、`wind/风`、`poison/毒`、`gold_light/金/金光`（规范名是 `gold_light`）、`shield/盾/护盾`。

`normalize_kind` 得到要保存的类型，不认识的收成 `slash`。`resolve_kind` 得到真正播放的场景：有 `ice_fx.tscn` 这类独立资源就播自己；目前没有时 ice→thunder、wind→slash、poison→fire、gold_light→slash、shield→heal_circle。

## 全自动战斗怎么接

1. 把整个 `skill_fx/` 拷到客户端 `anim_q/skill_fx/`（含 `fx/` 贴图与 `.gd/.tscn`）。
2. 战斗页在**技能事件**到来时（服务器/本地施放确认）直接 `play`，**不要等按钮**。
3. 挂点建议：
   - 斩/火：目标身中（怪/首领中心偏前，避开顶栏血条名字）
   - 雷：目标脚底，雷身向上
   - 治疗：己方脚底
4. 飘字仍走现有 float；本模板**不显示「暴击」**。
5. 低端机：`fx_scale = 0.85`，或关掉雷的局部 `Flash`（可后续加 export）。

批量扩技能：只换 `primary_color` / `secondary_color` / `fx_scale`，一般不必重做场景。

## 预览与截图（给美术过）

| 用途 | 路径 |
|---|---|
| 四套依次播放 | `preview/skill_fx.mp4`（同 `../preview/skill_fx.mp4`） |
| **战斗页合成**（赤炎首领页上四套同框） | **`screenshot_board.jpg`** / `preview/skill_fx_board.mp4` |
| 单套峰值 | `screenshot_slash.jpg` · `screenshot_thunder.jpg` · `screenshot_fire.jpg` · `screenshot_heal.jpg` |

合成图也在：`/workspace/anim_out_q/preview/stills/skill_fx_board.jpg`

## 性能

- 节点：斩 7 / 雷 10 / 火 10 / 治疗 9
- 粒子中低密度（斩 8、雷 10、火 14+8、治疗 12），`one_shot` / 用完即停
- 无 Spine；纹理 ≤420px；可池化实例避免频繁 instantiate

## 校验

```bash
Godot --headless --path /workspace/anim_out_q/_preview_project \
  --script res://tools/skill_fx_load_check.gd
# → SKILL_FX_LOAD_OK
```

重建：`Godot --headless --path . --script res://tools/build_skill_fx.gd`  
录屏：`bash tools/render.sh skill_fx 5.0` / `skill_fx_board 2.0`

## 已知注意

- 刀光弧略加粗并带 `#A8E8E0` 软边；雷纹中等偏粗（Q 可读）。

- 火已默认 `heavy=true`（更大爆点、更亮芯 `#FFF2C8`、火柱抬高 + 浅青白描边）。非红底章节可 `heavy=false`。
- 色板若美术回修订，优先改各脚本顶部 `PRIMARY`/`SECONDARY` 与 `skill_fx_root.DEFAULTS`，再批量重渲截图。
