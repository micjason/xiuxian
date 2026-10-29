extends GutTest
## 技能特效解析与播放。不改 battle_idle / battle_boss（那两个战斗包由另一分支接）。

const SkillFxRoot := preload("res://anim_q/skill_fx/skill_fx_root.gd")


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


func test_aliases_and_fallback_use_gold_light() -> void:
	assert_eq(SkillFxRoot.normalize_kind("冰"), "ice")
	assert_eq(SkillFxRoot.normalize_kind("护盾"), "shield")
	assert_eq(SkillFxRoot.normalize_kind("FIRE"), "fire")
	assert_eq(SkillFxRoot.normalize_kind("金光"), "gold_light")
	assert_eq(SkillFxRoot.normalize_kind("gold"), "gold_light")
	assert_eq(SkillFxRoot.normalize_kind("meteor"), "slash")
	assert_eq(SkillFxRoot.resolve_kind("ice"), "thunder")
	assert_eq(SkillFxRoot.resolve_kind("wind"), "slash")
	assert_eq(SkillFxRoot.resolve_kind("poison"), "fire")
	assert_eq(SkillFxRoot.resolve_kind("gold_light"), "slash")
	assert_eq(SkillFxRoot.resolve_kind("shield"), "heal_circle")
	assert_eq(SkillFxRoot.resolve_kind("thunder"), "thunder")
	assert_true(ResourceLoader.exists(SkillFxRoot.scene_path("gold_light")))
	assert_true(SkillFxRoot.scene_path("gold_light").ends_with("slash_fx.tscn"))
	assert_false(ResourceLoader.exists("res://anim_q/skill_fx/gold_light_fx.tscn"))
	var cast: Dictionary = SkillFxCast.resolve({"kind": "ult", "fx": {"type": "金光", "scale": 1.4, "primary": "ffd45c"}}, [], [])
	assert_eq(cast.stored, "gold_light")
	assert_eq(cast.playable, "slash")
	assert_eq(cast.anchor, SkillFxCast.ANCHOR_TARGET_BODY)
	assert_almost_eq(float(cast.scale), 1.4, 0.001)
	var heal: Dictionary = SkillFxCast.resolve({"kind": "pill"}, [], [])
	assert_eq(heal.stored, "heal_circle")
	assert_eq(heal.anchor, SkillFxCast.ANCHOR_SELF_FEET)
	var auto: Dictionary = SkillFxCast.resolve_auto(
		[{"slug": "lei", "role": "attack", "fxType": "ice", "enabled": true}],
		[{"skillSlug": "lei", "runningSlot": "run_1"}],
	)
	assert_eq(auto.stored, "ice")
	assert_eq(auto.playable, "thunder")
	assert_eq(auto.anchor, SkillFxCast.ANCHOR_TARGET_FEET)
	var basic: Dictionary = SkillFxCast.resolve(
		{"side": "player", "damage": 1},
		[{"slug": "lei", "role": "attack", "fxType": "thunder", "enabled": true}],
		[{"skillSlug": "lei", "runningSlot": "run_1"}],
	)
	assert_eq(basic.stored, "slash", "普攻默认斩，不占用攻击技能的特效")


func test_play_once_uses_fallback_scene_at_the_given_point() -> void:
	var layer := Node2D.new()
	layer.position = Vector2(12, 34)
	add_child_autofree(layer)
	await get_tree().process_frame
	var n := SkillFxRoot.play_once("gold_light", layer, Vector2(80, 120), 1.0)
	assert_not_null(n)
	assert_true(str(n.get_script().resource_path).ends_with("slash_fx.gd"))
	assert_eq(n.position, Vector2(80, 120))
	assert_eq(layer.position, Vector2(12, 34), "播放不挪动挂载层")
	assert_true(n.is_playing())
