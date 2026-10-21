extends GutTest
## v13 动画特效（2026-10-20 成鹏确认的 5 个动画，game/anim_q/，说明 /workspace/anim_out_q/README.md）
## 以及美术补充（提示条、开箱宝箱、头像、幽冥古道 / 赤炎火山 8 只怪物）。
## 数字都来自 ProtoMock（与服务器同结构、同配置算出来的演示数据），不写死。


func _boot(scenario: String) -> Node:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	OS.set_environment("XIUXIAN_MOCK_SCENARIO", scenario)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	OS.unset_environment("XIUXIAN_UI_MOCK")
	OS.unset_environment("XIUXIAN_MOCK_SCENARIO")
	return scene


func _static_hero_rects(root: Node, out: Array[Node] = []) -> Array[Node]:
	if root is TextureRect and (root as TextureRect).texture != null and (root as TextureRect).texture.resource_path.ends_with("sprites/hero_meditate.png"):
		out.append(root)
	for child in root.get_children():
		_static_hero_rects(child, out)
	return out


func test_all_five_animation_scenes_are_installed() -> void:
	for path in [QFx.HERO, QFx.BREAK_ORB, QFx.BUTTON_BOUNCE, QFx.POPUP, QFx.FLOAT_NUMBER, QFx.DROP_FLY, QFx.BAG_PULSE, QFx.BREAKTHROUGH, QFx.CHEST]:
		assert_true(QFx.has(path), path)


func test_the_layered_hero_replaces_the_static_one_everywhere() -> void:
	var scene := await _boot("ready")
	for page_key in ["cultivate", "adventure", "bag"]:
		scene.call("_show_page", page_key)
	var names := {"_home_page": "HeroSprite", "_stage_page": "StageHero", "_bag_page": "DollHero"}
	for owner in names:
		var hero := (scene.get(owner) as Node).find_child(names[owner], true, false) as QHero
		assert_not_null(hero, "%s 用动画主角" % owner)
		if hero != null:
			assert_true(hero.is_animated(), owner)
			assert_eq(hero.current_animation(), "idle", "打坐待机自动循环")
	scene.call("_open_battle", str(((scene.get("_state") as Dictionary).breakthrough.requiredStage as Dictionary).slug))
	# 第四批：战斗页用主角战斗姿势立绘（sprites/player_fight，SPEC_Q §17.8），不再是打坐的动画主角
	var pose := (scene.get("_battle_page") as Node).find_child("HeroArt", true, false) as TextureRect
	assert_not_null(pose, "战斗页是战斗姿势")
	if pose != null:
		assert_eq(pose.texture.resource_path.get_file(), "player_fight.png")
	# 突破弹窗：主角放在莲台上，坐垫隐藏
	var page := scene.get("_breakthrough_page") as BreakthroughPage
	var slot_hero := page.break_fx().get_node("HeroSlot/Hero") as Node2D
	assert_false((slot_hero.get_node("Rig/Cushion") as CanvasItem).visible)
	assert_eq(_static_hero_rects(scene).size(), 0, "没有地方再用旧的静态主角图")


func test_home_hero_sits_in_the_design_frame() -> void:
	var scene := await _boot("ready")
	scene.call("_show_page", "cultivate")
	await get_tree().process_frame
	var hero := (scene.get("_home_page") as Node).find_child("HeroSprite", true, false) as QHero
	# README 1：锚点 = 角色框底边中点 (540, 1070)，1 倍设计尺寸
	var anchor := hero.hero.get_global_transform().origin
	assert_almost_eq(anchor.x, 540.0, 2.0)
	assert_almost_eq(hero.hero.scale.x, 1.0, 0.01)


func test_top_bar_avatar_uses_the_new_player_avatar() -> void:
	var scene := await _boot("ready")
	var face := (scene.get("_top_bar") as Node).find_child("Face", true, false) as TextureRect
	assert_not_null(face)
	assert_eq(face.texture.resource_path, "res://assets/art/q/ui/avatar_player_round@2x.png")


func test_break_orb_glows_only_when_ready() -> void:
	var scene := await _boot("ready")
	var orb := (scene.get("_tab_bar") as TabBarView).button_of("breakthrough") as QBreakButton
	assert_true(orb.uses_orb_fx())
	orb.set_state("ready")
	assert_eq(orb.orb_animation(), "idle", "可突破：呼吸光 + 星光")
	orb.set_state("hint")
	assert_ne(orb.orb_animation(), "idle", "不能突破时不闪")
	orb.set_state("ready")


func test_breakthrough_banner_does_not_cover_the_title_rows() -> void:
	var scene := await _boot("ready")
	scene.call("_show_page", "cultivate")
	scene.call("_open_breakthrough")
	await wait_seconds(0.5)
	var page := scene.get("_breakthrough_page") as BreakthroughPage
	var banner := page.success_title_rect()
	assert_gt(banner.size.x, 0.0)
	for name in ["RealmRow", "PowerGain", "RateRing"]:
		var node := page.find_child(name, true, false) as Control
		assert_not_null(node, name)
		if node != null:
			assert_false(banner.intersects(node.get_global_rect()), "「突破成功」横幅不压 %s：%s vs %s" % [name, banner, node.get_global_rect()])
	var stage := page.find_child("Stage", true, false) as Control
	assert_true(stage.get_global_rect().grow(2).encloses(banner), "横幅在舞台里")


func test_breakthrough_plays_charge_then_success_then_the_result_popup() -> void:
	var scene := await _boot("ready")
	scene.call("_show_page", "cultivate")
	scene.call("_open_breakthrough")
	var page := scene.get("_breakthrough_page") as BreakthroughPage
	if not bool(page.view().get("can_start", false)):
		pending("演示数据不能突破")
		return
	scene.call("_on_breakthrough")
	await get_tree().process_frame
	assert_eq(QFx.player(page.break_fx()).current_animation, "charge")
	var success := scene.get("_success_popup") as BreakthroughSuccess
	assert_false(success.visible, "特效播完前不出结算")
	await wait_until(func() -> bool: return success.visible, 8.0)
	assert_true(success.visible)
	var title := success.title_label()
	assert_not_null(title)
	assert_eq(title.text, "突破成功")
	await wait_seconds(0.5)
	var to_name := success.find_child("ToName", true, false) as Control
	assert_false(title.get_global_rect().intersects(to_name.get_global_rect()), "结算弹窗的标题不压境界名")


func test_offline_chest_opens_and_the_total_rolls_to_the_real_value() -> void:
	var scene := await _boot("ready")
	var popup := scene.get("_offline_popup") as OfflinePopup
	assert_true(popup.visible)
	var fx := popup.chest_fx()
	assert_not_null(fx)
	var expected := str(popup.current_view().total_text)
	assert_eq(expected, "+33,120")
	await wait_seconds(4.0)
	assert_eq(QFx.player(fx).current_animation, "idle_open")
	assert_eq(popup.total_text(), expected, "滚完停在真实总数")
	assert_false((fx.get_node("Number") as CanvasItem).visible, "场景自带的示例数字不显示")


func test_gain_floats_show_the_real_settle_numbers() -> void:
	var scene := await _boot("ready")
	scene.call("_show_page", "cultivate")
	var state: Dictionary = scene.get("_state")
	state["lastSettle"] = {"online": true, "seconds": 12, "passiveGained": 36, "kills": 4, "deaths": 0, "killCultivation": 20,
		"drops": [{"itemSlug": "gear_major1_helmet_green", "quantity": 1, "quality": "green"}], "bagFull": false}
	scene.call("_render", true)
	await get_tree().process_frame
	var floats := (scene.get("_home_page") as HomePage).gain_floats()
	assert_eq(floats.size(), 2, "挂机修为 + 击杀修为各一个")
	var values := floats.map(func(n: Node) -> int: return int(n.get("value")))
	assert_true(values.has(36) and values.has(20), str(values))
	await wait_seconds(2.5)
	assert_eq((scene.get("_home_page") as HomePage).gain_floats().size(), 0, "飘完就清掉")


func test_drops_fly_into_the_bag_and_the_bag_pulses() -> void:
	var scene := await _boot("ready")
	scene.call("_show_page", "cultivate")
	var state: Dictionary = scene.get("_state")
	scene.set("_state", ProtoMock.tick(state, scene.get("_content"), 25.0))
	var drops: Array = ((scene.get("_state") as Dictionary).get("lastSettle", {}) as Dictionary).get("drops", [])
	if drops.is_empty():
		pending("这次结算没有掉落")
		return
	scene.call("_render", true)
	await get_tree().process_frame
	var layer := scene.find_child("FxLayer", true, false) as Control
	assert_gt(layer.get_children().filter(func(n: Node) -> bool: return str(n.name).contains("DropFly")).size(), 0, "掉落物飞向背包")
	var bar := scene.get("_tab_bar") as TabBarView
	await wait_until(func() -> bool: return bar.pulse_count("bag") > 0, 4.0)
	assert_gt(bar.pulse_count("bag"), 0, "飞到后背包图标弹一下")


func test_monster_lookup_covers_the_two_new_maps() -> void:
	var expected := {
		"游魂": "mon_ghost", "骨傀": "mon_bone_golem", "血蝠": "mon_bat", "噬魂老鬼": "mon_ghost_elder",
		"炎鳞蜥": "mon_lava_lizard", "火鸦": "mon_fire_crow", "熔岩傀": "mon_lava_golem", "赤焰蛟": "mon_fire_jiao",
		"毒牙蟒": "mon_snake", "黑风狼": "mon_wolf",
	}
	for name in expected:
		assert_eq(ArtLib.monster_sprite_id(name), expected[name], name)
	for id in ["mon_fire_crow", "mon_lava_lizard", "mon_fire_jiao"]:
		assert_false(ArtLib.monster_needs_flip(id), "%s 原图朝左，不翻转" % id)
	assert_true(ArtLib.monster_needs_flip("mon_wolf"))
	var source := FileAccess.get_file_as_string("res://scripts/ui/pages/stage_page.gd")
	assert_false(source.contains("\"sprites/mon_snake\""), "历练场景不再写死蛇")


func test_every_configured_monster_has_q_art() -> void:
	var scene := await _boot("ready")
	var names := {}
	_monster_names(scene.get("_content"), names)
	assert_gt(names.size(), 8, "配置里的小怪（黑风岭 + 幽冥古道 + 赤炎火山）")
	for n in names:
		assert_ne(ArtLib.monster_sprite_id(str(n)), "", "「%s」有 Q 版立绘" % n)


func _monster_names(value: Variant, out: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if str(key) == "monsters" and typeof(value[key]) == TYPE_ARRAY:
				for row in value[key]:
					if typeof(row) == TYPE_DICTIONARY and (row as Dictionary).has("name"):
						out[str((row as Dictionary).name)] = true
			else:
				_monster_names(value[key], out)
	elif typeof(value) == TYPE_ARRAY:
		for item in value:
			_monster_names(item, out)


func test_every_new_file_has_a_licence_row() -> void:
	var listed := {}
	var text := FileAccess.get_file_as_string("res://assets/art_q_license_list.csv")
	for line in text.split("\n"):
		listed[line.get_slice(",", 0)] = true
	var missing: Array[String] = []
	for path in _files("res://anim_q"):
		if not listed.has(path.trim_prefix("res://")):
			missing.append(path)
	for rel in ["sprites/chest_open.png", "sprites/chest_closed_hd.png", "ui/toast_bg.png", "ui/toast_bg_lock.png",
			"ui/avatar_player.png", "ui/avatar_player@2x.png", "ui/avatar_player_round.png", "ui/avatar_player_round@2x.png",
			"sprites/mon_ghost.png", "sprites/mon_bone_golem.png", "sprites/mon_bat.png", "sprites/mon_ghost_elder.png",
			"sprites/mon_lava_lizard.png", "sprites/mon_fire_crow.png", "sprites/mon_lava_golem.png", "sprites/mon_fire_jiao.png"]:
		if not listed.has(rel):
			missing.append(rel)
	if not listed.has("assets/fonts/ZCOOLQingKeHuangYou-Regular.subset.woff2"):
		missing.append("QingKe font")
	assert_eq(missing, [] as Array[String], "授权表缺：%s" % [missing])
	assert_true(FileAccess.file_exists("res://assets/fonts/OFL-ZCOOLQingKeHuangYou.txt"))


func _files(dir: String, out: Array[String] = []) -> Array[String]:
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".import") and not f.ends_with(".uid"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_files(dir + "/" + d, out)
	return out


## 0.13.0 上线后发现：外壳抬了 z 以后，登录页（z 0）被顶 / 底栏和主角盖住。登录页必须在主界面所有层之上、弹窗之下。
func test_login_page_covers_the_whole_main_ui() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var login := scene.get("_login") as Control
	assert_not_null(login)
	for owner in ["_top_bar", "_tab_bar", "_fx_layer", "_break_layer"]:
		assert_gt(login.z_index, (scene.get(owner) as CanvasItem).z_index, "登录页在 %s 之上" % owner)
	# 主角部件最高 z 20（相对页面 0）
	assert_gt(login.z_index, 20 + 1)
	for owner in ["_popup", "_toast"]:
		assert_lt(login.z_index, (scene.get(owner) as CanvasItem).z_index, "%s 在登录页之上（更新弹窗、提示）" % owner)
