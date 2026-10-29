# 主角换装 SPEC（v1 · 整图替换）

日期：2026-10-29  
风格：Q 版 2.5～3 头身 · 可可描边 `#6B4A3A` · 亮色干净

## 定稿（负责人）
1. **v1 = 整图替换** `preview_*.png`（按装备品质）。分层 / Spine 后续，不挡上线。
2. 五品质：**白 / 绿 / 蓝 / 紫 / 橙**
3. 战斗 + 打坐 + 头像同档出齐

## 品质色
| 品质 | Hex 主 | Hex 深 | 战斗预览 |
|------|--------|--------|----------|
| 白 | `#C9CED6`（白+薄荷观感） | — | `preview_white.png` |
| 绿 | `#7ED36A` | `#3C9A4E` | `preview_green.png` |
| 蓝 | `#5AAEFF` | `#2E7FC4` | `preview_blue.png` |
| 紫 | `#B57CFF` | `#8A4FE0` | `preview_purple.png` |
| 橙 | `#FFA43A` | `#E07B24` | `preview_orange.png` |

发深棕、发簪青绿不变；只换袍/腰封宝石色。

## A. 战斗（fight）
目录：`/workspace/art_out_q/outfit/`
- 画布 **1024×1024**，面朝右，脚底锚
- `preview_{white,green,blue,purple,orange}.png`
- 对比条：`preview_strip.png`
- 白品质对齐现网 `sprites/player_fight.png`
- 分层源（可选，非 v1 接入硬依赖）：`base_body.png`、`robe_*.png`、`weapon_sword.png`

### Godot v1
装备套装品质变化 → 单个 `Sprite2D.texture = preview_{quality}.png`

## B. 打坐（meditate）
目录：`outfit/meditate/`
- `meditate_{white,green,blue,purple,orange}.png`（1024²）
- 白 = 现网 `sprites/char_meditate.png` 扩画布
- 对比条：`preview_meditate_strip.png`

## C. 头像（avatar）
目录：`outfit/avatar/`
| 规格 | 文件 |
|------|------|
| 124² 方 | `avatar_{tier}.png` |
| 248² 方 | `avatar_{tier}@2x.png` |
| 124 圆 | `avatar_{tier}_round.png` |
| 248 圆 | `avatar_{tier}_round@2x.png` |

白档 = 现网 `ui/avatar_player*` 复制。对比条：`preview_avatar_strip.png`

## 预览给负责人
1. `outfit/preview_strip.png` — 战斗五档  
2. `outfit/meditate/preview_meditate_strip.png` — 打坐五档  
3. `outfit/avatar/preview_avatar_strip.png` — 头像五档  
