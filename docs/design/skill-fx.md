# 技能施法特效

资源在 `game/anim_q/skill_fx/`。播放用 `SkillFxRoot.spawn` / `play_once`，挂在目标点上，不要平移主角。

本变更不改 `battle_idle`、`battle_boss`。挂机和首领战的事件接线由另一分支接入；这里提供统一解析和可加载资源。

## 配置

`content_skills.fx_type`（接口字段 `fxType`）取值：

`slash` | `thunder` | `fire` | `heal_circle` | `ice` | `wind` | `poison` | `gold_light` | `shield`

金光的规范名是 `gold_light`。写入 `gold`、`金`、`金光` 都会收成 `gold_light`。其余中文别名（斩击、雷、火、治疗、冰、风、毒、盾 / 护盾）收成对应英文。不认识的值收成 `slash`。

可选 `fx`（jsonb）：`{ "type", "primary", "secondary", "scale" }`。`type` 同一套枚举；`primary` / `secondary` 是 `#RRGGBB`；`scale` 为 0–4 的正数。有覆盖时优先用 `fx.type`。

迁移 `0062_skill_fx_type`（`when` 1800200000000）。不改玩家进度。默认特效种子由另一分支写入，本变更不灌具体技能。

## 客户端怎么播

`SkillFxRoot.normalize_kind` 得到要存的类型。`SkillFxRoot.resolve_kind` 得到要实例化的场景：

| 配置 | 已有独立场景时 | 目前没有独立场景时 |
| --- | --- | --- |
| slash / thunder / fire / heal_circle | 自己 | 自己 |
| ice | `ice_fx.tscn` | thunder |
| wind | `wind_fx.tscn` | slash |
| poison | `poison_fx.tscn` | fire |
| gold_light | `gold_light_fx.tscn` | slash |
| shield | `shield_fx.tscn` | heal_circle |

`SkillFxCast.resolve(event, skills, running)` / `resolve_auto(skills, running)` 给出 `{stored, playable, alias, anchor, primary, secondary, scale}`。

挂点：斩、火、风、毒、金光在目标身中偏前；雷、冰在目标脚底；治疗、盾在己方脚底。

建议接法（战斗包自己调用，不要整个人平移）：

```gdscript
var spec := SkillFxCast.resolve(event, content_skills, running_skills)
var n := SkillFxRoot.spawn(str(spec.alias), fx_layer, anchor_pos, float(spec.scale))
n.primary_color = spec.primary
n.secondary_color = spec.secondary
n.play()
```

普攻默认斩。大招用正在运转的攻击技能（`role = attack`）的 `fxType`，没有则斩。事件上的 `fx` / `fxType` / `skillSlug` 优先。`resolve_auto` 给历练自动出手：有运转中的攻击技能就用它，否则斩。治疗、丹药事件播治疗圈。伤害飘字仍走原来的数字。
