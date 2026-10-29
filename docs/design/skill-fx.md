# 技能施法特效

九套场景都在 `game/anim_q/skill_fx/`。`SkillFxRoot.spawn` / `play_once` 按真名播对应场景，不平移主角。

不改 `battle_idle`、`battle_boss`，也不改换装。战斗包自己在施法事件里调用下面的解析。

## 配置

`content_skills.fx_type`（接口字段 `fxType`）九个真名：

`slash` | `thunder` | `fire` | `heal_circle` | `ice` | `wind` | `poison` | `gold_light` | `shield`

金光的规范名是 `gold_light`。`gold`、`金`、`金光` 都收成 `gold_light`。不认识的值收成 `slash`。

可选 `fx`：`{ type, primary, secondary, scale }`，`type` 与 `fxType` 一致。种子写在迁移 `0062_outfit_skill_defaults`，写的是真名，不写降级名。

## 播放

`normalize_kind` 得到要保存的类型。`resolve_kind` 在 `*_fx.tscn` 存在时返回同一真名。缺文件时才降级：ice→thunder、wind→slash、poison→fire、gold_light→slash、shield→heal_circle。九套都在仓库里，正常播放不会走到降级。

挂点：斩、风在目标身前；火、冰、毒、金光在目标中心；雷在目标脚底；治疗在己方脚底；盾在己方身中。

战斗只自动放技能，没有技能按钮、充能条或「自动战斗」开关。`SkillFxCast.play` 在施法点实例化对应场景，不平移角色。

- 首领战：`boss_battle.on_event` 里，玩家自动技能事件（协议字段仍可能叫 `kind:ult`）、治疗/丹药，或事件自带 `fx` / `fxType` / `skillSlug` 时，用内容技能的 `fxType` 播一次。普通普攻仍走飞剑，不另播九套。
- 挂机：飞剑命中时 `resolve_auto`，有运转中的攻击技能就播它的 `fxType`，否则斩。
- 页面只把 `content.skills` 和 `state.skills` 交给特效层。换配置即换特效，不写死技能 id。未知 kind 收成斩；缺场景则静默，不把英文 kind 画到界面。
