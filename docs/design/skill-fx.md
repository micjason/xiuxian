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
