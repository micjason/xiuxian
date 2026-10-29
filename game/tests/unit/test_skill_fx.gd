extends GutTest
## 九套技能特效真名。资源在时直接播自己的场景；gold / 金 / 金光 收成 gold_light。


const SkillFxRoot := preload("res://anim_q/skill_fx/skill_fx_root.gd")
const REAL := ["slash", "thunder", "fire", "heal_circle", "ice", "wind", "poison", "gold_light", "shield"]


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


func test_nine_real_scenes_play_themselves() -> void:
	for kind in REAL:
		assert_true(SkillFxRoot.has_scene(kind), kind)
		assert_eq(SkillFxRoot.resolve_kind(kind), kind, kind)
		assert_true(SkillFxRoot.scene_path(kind).ends_with(kind + "_fx.tscn"), kind)
	assert_eq(SkillFxRoot.normalize_kind("金"), "gold_light")
	assert_eq(SkillFxRoot.normalize_kind("金光"), "gold_light")
	assert_eq(SkillFxRoot.normalize_kind("gold"), "gold_light")
	assert_eq(SkillFxRoot.normalize_kind("GOLD_LIGHT"), "gold_light")
	assert_eq(SkillFxRoot.resolve_kind("金"), "gold_light")
	assert_eq(SkillFxRoot.normalize_kind("meteor"), "slash")
	assert_eq(SkillFxRoot.fallback_kind("ice"), "thunder")
	assert_eq(SkillFxRoot.fallback_kind("gold_light"), "slash")
	assert_eq(SkillFxRoot.fallback_kind("shield"), "heal_circle")
	var cast: Dictionary = SkillFxCast.resolve({"fxType": "gold_light"}, [], [])
	assert_eq(cast.stored, "gold_light")
	assert_eq(cast.playable, "gold_light")
	assert_eq(cast.anchor, SkillFxCast.ANCHOR_TARGET_CENTER)
	var ice: Dictionary = SkillFxCast.resolve({"kind": "ult", "fxType": "ice"}, [], [])
	assert_eq(ice.playable, "ice")
	assert_eq(ice.anchor, SkillFxCast.ANCHOR_TARGET_CENTER)
	var shield: Dictionary = SkillFxCast.resolve({"fxType": "shield"}, [], [])
	assert_eq(shield.playable, "shield")
	assert_eq(shield.anchor, SkillFxCast.ANCHOR_SELF_BODY)


func test_play_once_uses_the_gold_light_scene() -> void:
	var layer := Node2D.new()
	layer.position = Vector2(12, 34)
	add_child_autofree(layer)
	await get_tree().process_frame
	var n := SkillFxRoot.play_once("金光", layer, Vector2(80, 120), 1.0)
	assert_not_null(n)
	assert_true(str(n.get_script().resource_path).ends_with("gold_light_fx.gd"))
	assert_eq(n.position, Vector2(80, 120))
	assert_eq(layer.position, Vector2(12, 34), "播放不挪动挂载层")
	assert_false(n.has_meta("fx_fallback_from"))
	assert_true(n.is_playing())
