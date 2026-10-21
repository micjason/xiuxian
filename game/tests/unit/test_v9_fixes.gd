extends GutTest
## v9a 验收意见的回归测试：离线弹窗文案/提示位置、修炼页不重复、飘字不叠成一串、战报整行显示、
## 背包满提示是居中小弹窗、安全区调试覆盖解析。无头模式字体缓存的引擎错误不算失败。


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


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


func _labels(root: Node, out: Array[String] = []) -> Array[String]:
	if root is Label:
		out.append((root as Label).text)
	elif root is Button:
		out.append((root as Button).text)
	for child in root.get_children():
		_labels(child, out)
	return out


## Q 版设计稿（10-20 成鹏确认）：「领取」（真的确认已读）+「双倍领取」（广告，没有：提示功能暂未开放）。
func test_offline_popup_has_claim_and_locked_double_and_hint_is_outside_the_frame() -> void:
	var scene := await _boot("ready")
	var popup := scene.get("_offline_popup") as OfflinePopup
	assert_true(popup.visible)
	assert_eq(popup.claim_text().replace(" ", ""), "领取")  # 动画按钮上写「领 取」
	assert_eq(popup.double_button().text, "双倍领取")
	assert_true(LockedFeature.is_locked(popup.double_button()))
	assert_false(LockedFeature.is_locked(popup.claim_button()))
	var texts := _labels(popup)
	assert_eq(texts.count("离线收益"), 1)
	assert_false(texts.has("知道了"))
	var foot := popup.find_child("FootHint", true, false) as Label
	assert_not_null(foot)
	assert_false(popup.get("_panel").is_ancestor_of(foot), "提示在卷轴外面，不压在下轴上")


func test_home_page_shows_the_cultivation_bar_and_kill_feed_once() -> void:
	var scene := await _boot("ready")
	scene.call("_show_page", "cultivate")
	var state: Dictionary = scene.get("_state")
	state["lastSettle"] = {"online": true, "seconds": 12, "passiveGained": 36, "kills": 4, "deaths": 0, "killCultivation": 20,
		"drops": [{"itemSlug": "gear_major1_helmet_green", "quantity": 1, "quality": "green"}], "bagFull": false}
	scene.call("_render", true)
	await get_tree().process_frame
	var home := scene.get("_home_page") as HomePage
	var texts := _labels(home)
	assert_eq(texts.filter(func(t: String) -> bool: return t.begins_with("击败怪物")).size(), 1, "击杀信息只出现一次")
	assert_eq(texts.filter(func(t: String) -> bool: return t.begins_with("修为 ")).size(), 0, "修为条只在顶栏")
	assert_null(home.find_child("FloatLayer", true, false), "莲台上不再飘字")
	var top_texts := _labels(scene.get("_top_bar") as Node)
	assert_eq(top_texts.filter(func(t: String) -> bool: return t.contains("/ 1,800")).size(), 1)


func test_battle_floats_use_separate_lanes_and_are_capped_per_side() -> void:
	var scene := await _boot("ready")
	var page := scene.get("_battle_page") as BattlePage
	var layer := page.get("_float_layer") as Control
	for i in 10:
		page._float_damage({"side": "boss", "damage": 16, "kind": "hit"})
	var hero: Array[Node] = []
	for child in layer.get_children():
		if not child.is_queued_for_deletion() and str(child.get_meta("side", "")) == "boss":
			hero.append(child)
	assert_lte(hero.size(), BattlePage.FLOAT_MAX_PER_SIDE, "同一边同时最多 4 条")
	var tops := {}
	for label in hero:
		tops[snappedf((label as Control).offset_top, 1.0)] = true
	assert_eq(tops.size(), hero.size(), "每条飘字在不同的高度")


func test_battle_report_view_height_is_a_whole_number_of_lines() -> void:
	var report := BattleReport.new()
	report.custom_minimum_size = Vector2(900, 237)
	add_child_autofree(report)
	await get_tree().process_frame
	await get_tree().process_frame
	var pitch := report.line_pitch()
	assert_gt(pitch, 20.0)
	var box := report.get_theme_stylebox("normal") as StyleBoxEmpty
	assert_lt(box.content_margin_bottom, pitch, "零头不超过一行")
	var visible_height := report.size.y - box.content_margin_bottom
	assert_almost_eq(fmod(visible_height, pitch), 0.0, 1.0)


func test_bag_full_prompt_is_a_centered_small_popup_without_close_button() -> void:
	var scene := await _boot("ready")
	# 第五批起外壳不再自动弹（§17.5），组件本身保留
	BagFullPrompt.show_prompt(scene.get("_popup") as GamePopup, 20, 20, func() -> void: pass)
	await get_tree().process_frame
	await get_tree().process_frame
	var popup := scene.get("_popup") as GamePopup
	assert_true(popup.visible)
	assert_true(popup.is_centered())
	assert_false(popup.get("_close_button").visible)
	var panel := popup.get("_panel") as Control
	var vp := scene.get_viewport().get_visible_rect().size
	assert_lt(panel.size.x, vp.x * 0.9)
	assert_lt(panel.size.y, vp.y * 0.4, "不是半屏")
	var center_y := panel.global_position.y + panel.size.y / 2.0
	assert_almost_eq(center_y, vp.y / 2.0, 80.0, "在屏幕正中")
	assert_lt(panel.global_position.y + panel.size.y, vp.y - 260.0, "不盖标签栏")
	# 其他弹层仍然是底部面板
	popup.close_popup()
	popup.open_popup("设置")
	assert_false(popup.is_centered())


func test_safe_area_debug_override_parses_and_clamps() -> void:
	OS.set_environment("XIUXIAN_SAFE_AREA", "0,120,0,66")
	assert_eq(UiSafeArea.debug_override(), Vector4(0, 120, 0, 66))
	OS.set_environment("XIUXIAN_SAFE_AREA", "0,9999,0,66")
	assert_eq((UiSafeArea.debug_override() as Vector4).y, UiSafeArea.MAX_INSET)
	OS.set_environment("XIUXIAN_SAFE_AREA", "bad")
	assert_null(UiSafeArea.debug_override())
	OS.unset_environment("XIUXIAN_SAFE_AREA")
	assert_null(UiSafeArea.debug_override())


func test_stage_page_challenge_button_sits_on_the_selected_card() -> void:
	# 第三批（SPEC_Q §14.5）：底部固定的挑战条拿掉了，按钮在每张关卡卡上（跟着列表滚动），选中的卡上那个就是「挑战」。
	var scene := await _boot("ready")
	scene.call("_show_page", "adventure")
	await get_tree().process_frame
	await get_tree().process_frame
	var stage := scene.get("_stage_page") as StagePage
	var button := stage.challenge_button()
	assert_not_null(button, "选中关卡后就有挑战按钮")
	var card := stage.find_child("Stage_%s" % stage.selected, true, false) as Control
	assert_true(card.is_ancestor_of(button), "按钮在选中的关卡卡上")
	var scroll := stage.get("_stage_view") as ScrollContainer
	assert_true(scroll.is_ancestor_of(button), "跟着列表滚动")
	assert_gte(button.get_global_rect().size.y, 96.0, "触控尺寸")
	assert_null(stage.find_child("ChallengeBar", true, false), "旧的底部挑战条没有了")
	assert_null(stage.find_child("AutoChallengeToggle", true, false), "旧的自动挑战开关没有了")
