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


func test_auto_cast_plays_each_real_kind_on_its_anchor() -> void:
	var points := {
		SkillFxCast.ANCHOR_TARGET_BODY: Vector2(10, 20),
		SkillFxCast.ANCHOR_TARGET_CENTER: Vector2(30, 40),
		SkillFxCast.ANCHOR_TARGET_FEET: Vector2(50, 60),
		SkillFxCast.ANCHOR_SELF_FEET: Vector2(70, 80),
		SkillFxCast.ANCHOR_SELF_BODY: Vector2(90, 100),
	}
	var layer := Node2D.new()
	layer.position = Vector2(3, 4)
	add_child_autofree(layer)
	await get_tree().process_frame
	for kind in REAL:
		var cast: Dictionary = SkillFxCast.resolve({"fxType": kind, "fx": {"type": kind, "scale": 1.25}}, [], [])
		var n := SkillFxCast.play(layer, cast, points)
		assert_not_null(n, kind)
		assert_eq(n.position, points[cast.anchor], kind)
		assert_true(str(n.get_script().resource_path).ends_with(kind + "_fx.gd"), kind)
		assert_almost_eq(float(n.get("fx_scale")), 1.25, 0.0001, kind)
		assert_eq(layer.position, Vector2(3, 4), "播放不挪动挂载层")
		assert_false(_shows_kind_slug(n, kind), kind)
		n.queue_free()
	var unknown: Dictionary = SkillFxCast.resolve({"fxType": "meteor"}, [], [])
	assert_eq(unknown.playable, "slash")
	var fallback := SkillFxCast.play(layer, unknown, points)
	assert_not_null(fallback)
	assert_true(str(fallback.get_script().resource_path).ends_with("slash_fx.gd"))
	assert_false(_shows_kind_slug(fallback, "meteor"))
	var tinted: Dictionary = SkillFxCast.resolve({"fx": {"type": "gold_light", "primary": "#112233", "secondary": "#445566"}}, [], [])
	var gold := SkillFxCast.play(layer, tinted, points)
	assert_eq(gold.get("primary_color"), Color.html("112233"))
	assert_eq(gold.get("secondary_color"), Color.html("445566"))
	assert_false(SkillFxCast.is_auto_cast({"side": "player", "damage": 4}))
	assert_false(SkillFxCast.is_auto_cast({"side": "boss", "kind": "ult", "damage": 4}))
	assert_true(SkillFxCast.is_auto_cast({"side": "player", "kind": "ult", "damage": 4}))
	assert_true(SkillFxCast.is_auto_cast({"side": "player", "kind": "heal"}))
	var line: Dictionary = BattleReportBuilder.live_line({"side": "player", "kind": "ult", "damage": 12}, "黑风狼王", "大招")
	assert_false(str(line.text).contains("大招"))
	assert_string_contains(str(line.text), "自动技能")
	var named: Dictionary = BattleReportBuilder.live_line({"side": "player", "kind": "ult", "damage": 12}, "黑风狼王", "裂空斩")
	assert_string_contains(str(named.text), "裂空斩")
	assert_false(str(named.text).contains("大招"))
	var from_event: Dictionary = BattleReportBuilder.live_line({"side": "player", "kind": "ult", "damage": 12, "name": "寒冰刺"}, "黑风狼王", "大招")
	assert_string_contains(str(from_event.text), "寒冰刺")
	assert_false(str(from_event.text).contains("大招"))
	var blocked: Dictionary = BattleReportBuilder.live_line({"side": "player", "kind": "ult", "damage": 12, "name": "大招"}, "黑风狼王", "裂空斩")
	assert_string_contains(str(blocked.text), "自动技能")
	assert_false(str(blocked.text).contains("大招"))


func test_boss_and_idle_auto_cast_play_the_bound_skill_fx() -> void:
	var boss := (load("res://anim_q/battle_boss/boss_battle.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(boss)
	var idle := (load("res://anim_q/battle_idle/idle_battle.tscn") as PackedScene).instantiate() as Node2D
	add_child_autofree(idle)
	await get_tree().process_frame
	boss.set_process(false)
	idle.set_process(false)
	var boss_origin := boss.position
	var idle_origin := idle.position
	var fire := [{"slug": "skill_chiyan", "fxType": "fire", "role": "attack", "enabled": true, "displayName": "赤炎掌"}]
	var running := [{"skillSlug": "skill_chiyan", "runningSlot": "run_1"}]
	boss.call("set_skill_sources", fire, running)
	boss.call("on_event", {"side": "player", "kind": "ult", "damage": 40})
	await get_tree().process_frame
	var flame := _find_script(boss, "fire_fx.gd") as Node2D
	assert_not_null(flame, "首领自动技能按运转中的 fxType 播火")
	assert_eq(flame.position, (boss.call("skill_anchor_points") as Dictionary)[SkillFxCast.ANCHOR_TARGET_CENTER])
	assert_eq(boss.position, boss_origin, "不平移战斗层")
	var before := _count_script(boss, "fire_fx.gd")
	boss.call("on_event", {"side": "player", "damage": 8})
	boss.call("on_event", {"side": "boss", "damage": 3})
	await get_tree().process_frame
	assert_eq(_count_script(boss, "fire_fx.gd"), before, "普攻和首领出手不另播技能特效")
	boss.call("on_event", {"side": "player", "kind": "ult", "fx": {"type": "gold_light"}, "damage": 9})
	await get_tree().process_frame
	var gold := _find_script(boss, "gold_light_fx.gd") as Node2D
	assert_not_null(gold, "事件上的 fx.type 优先于运转技能")
	assert_eq(gold.position, (boss.call("skill_anchor_points") as Dictionary)[SkillFxCast.ANCHOR_TARGET_CENTER])
	assert_null(boss.find_child("UltButton", true, false))
	assert_null(boss.find_child("UltChargeDisc", true, false))
	assert_null(boss.find_child("AutoToggle", true, false))
	var shield := [{"slug": "skill_huti", "fxType": "shield", "role": "body", "enabled": true}]
	boss.call("set_skill_sources", shield, [{"skillSlug": "skill_huti", "runningSlot": "run_2"}])
	boss.call("on_event", {"side": "player", "kind": "ult", "damage": 5})
	await get_tree().process_frame
	var dome := _find_script(boss, "shield_fx.gd") as Node2D
	assert_not_null(dome)
	assert_eq(dome.position, (boss.call("skill_anchor_points") as Dictionary)[SkillFxCast.ANCHOR_SELF_BODY])
	var ice := [{"slug": "skill_hanbing", "fxType": "ice", "role": "attack", "enabled": true}]
	idle.call("set_skill_sources", ice, [{"skillSlug": "skill_hanbing", "runningSlot": "run_1"}])
	idle.call("_on_sword_impact")
	await get_tree().process_frame
	var shard := _find_script(idle, "ice_fx.gd") as Node2D
	assert_not_null(shard, "挂机命中播运转中的攻击技能")
	assert_eq(shard.position, (idle.call("skill_anchor_points") as Dictionary)[SkillFxCast.ANCHOR_TARGET_CENTER])
	assert_eq(idle.position, idle_origin, "不平移挂机层")
	assert_null(idle.find_child("UltChargeDisc", true, false))
	assert_null(idle.find_child("AutoToggle", true, false))
	var boss_src := FileAccess.get_file_as_string("res://anim_q/battle_boss/boss_battle.gd")
	assert_true(boss_src.contains("call(\"play_skill\")"), "自动技能动画走 play_skill")
	var page_src := FileAccess.get_file_as_string("res://scripts/ui/pages/battle_page.gd")
	var stage_src := FileAccess.get_file_as_string("res://scripts/ui/pages/stage_page.gd")
	assert_true(page_src.contains("set_skill_sources"), "首领战把技能配置交给特效层")
	assert_true(stage_src.contains("set_skill_sources"), "挂机把技能配置交给特效层")
	assert_false(page_src.contains("UltChargeDisc"))
	assert_false(page_src.contains("冷却完自动释放"))


func _find_script(root: Node, file_name: String) -> Node:
	if root.get_script() != null and str(root.get_script().resource_path).ends_with(file_name):
		return root
	for child in root.get_children():
		var found := _find_script(child, file_name)
		if found != null:
			return found
	return null


func _count_script(root: Node, file_name: String) -> int:
	var n := 0
	if root.get_script() != null and str(root.get_script().resource_path).ends_with(file_name):
		n += 1
	for child in root.get_children():
		n += _count_script(child, file_name)
	return n


func _shows_kind_slug(root: Node, slug: String) -> bool:
	if root is Label and str((root as Label).text).contains(slug):
		return true
	if root is RichTextLabel and str((root as RichTextLabel).text).contains(slug):
		return true
	for child in root.get_children():
		if _shows_kind_slug(child, slug):
			return true
	return false
