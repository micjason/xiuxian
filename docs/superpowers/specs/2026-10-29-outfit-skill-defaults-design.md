# 换装整图与技能默认内容

日期：2026-10-29  
状态：本分支实现。不播放战斗施法，不拷 `anim_q/skill_fx`。

## 目标

- `content_skills` 增加表现字段，后台可改，并播种至少 8 条默认可玩技能。
- 穿戴后按装备品质下发 `appearance`，客户端换战斗立绘、打坐图和圆头像。
- 技能图标按 `fx_type` 同名文件显示。
- 界面文案「功法」改为「技能」。底栏仍是「洞府」。

## 非目标

- 不实现战斗施法播放，不改 `skill_fx` 模板。
- 不把分层 `base_body` / `robe_*` 当作主路径。
- 不提供手动释放，不播种大招技能，不新增点击释放按钮。
- 现有首领战蓄力圆盘仍是自动大招显示，本分支不改它的播放。

## 技能

列加在现有 `content_skills`（迁移 `0062`，journal `when = 1800200000000`）：

| 列 | JSON | 说明 |
| --- | --- | --- |
| `fx_type` | `fxType` | 可空。`slash` `thunder` `fire` `heal_circle` `ice` `wind` `poison` `gold_light` `shield` |
| `fx` | `fx` | 可空 jsonb：`{ "type", "primary?", "secondary?", "scale?" }`，`type` 与 `fxType` 一致 |
| `cast_mode` | `castMode` | `auto` 或 `passive`，默认 `auto`。不接受 `manual` |

`prerequisite_skill_slugs` 保持可空数组，不建技能树。

Seed 写资源真名，不写降级类型。客户端仅在缺资源时：

- ice → thunder，wind → slash，poison → fire，gold_light → slash，shield → heal_circle
- 未知类型 → slash
- `gold` / `holy` 只作 `gold_light` 的别名

九条默认技能：吐纳诀 `heal_circle/passive`、青元诀 `wind/auto`、紫府金章 `gold_light/auto`、裂空斩 `slash/auto`、雷霆诀 `thunder/auto`、赤炎掌 `fire/auto`、寒冰刺 `ice/auto`、毒雾术 `poison/auto`、护体罡气 `shield/passive`。

图标文件与 `fx_type` 同名：`icons/heal_circle.png`、`icons/gold_light.png`。旧 `skill_*` 文件是同图别名。

## 换装

没穿装备时 `state.appearance` 为 `null`，客户端继续用现有战斗立绘、打坐和圆头像。

穿了衣服用衣服品质；没穿衣服用身上最高品质。五档都有整图：

```json
{
  "quality": "blue",
  "previewKey": "preview_blue",
  "meditateKey": "meditate_blue",
  "avatarKey": "avatar_blue",
  "avatarRoundKey": "avatar_blue_round"
}
```

图在 `game/assets/art/q/outfit/`。现网用圆头像的位置换 `avatar_*_round`。缺文件时不替换、不崩溃。

## 验收

- 迁移可重复执行；已改过的 `fx_type` 不会被再次迁移覆盖。
- 后台技能页可改 `fxType` / `fx` / `castMode`，列表显示图标。
- 穿戴白装后 `appearance.quality` 为 `white`，三套 key 一起变。
- 本地看换装：穿上白/绿/蓝/紫/橙装备后打开战斗、修炼、顶栏头像。
