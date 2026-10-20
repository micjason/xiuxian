extends GutTest
## Q 版界面（2026-10-20 设计稿 q_*）：底栏 5 格 + 中间「突破」大圆钮的三种状态、
## 统一的「功能暂未开放」提示（邮件、葫芦、炼丹、宝箱、双倍领取、功法升级/切换、洞府静室/升级、自动挑战、一键出售），
## 以及离线「领取」仍然真的确认已读。


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


func _toast(scene: Node) -> Toast:
	return scene.get("_toast") as Toast


func test_tab_bar_has_five_slots_in_design_order_with_the_orb_in_the_middle() -> void:
	var scene := await _boot("ready")
	var bar := scene.get("_tab_bar") as TabBarView
	assert_eq(bar._buttons.size(), 5)
	var order: Array = []
	for id in ["cultivate", "adventure", "breakthrough", "skill", "bag"]:
		var button := bar.button_of(id)
		assert_not_null(button, id)
		order.append(button.get_global_rect().get_center().x)
	for i in order.size() - 1:
		assert_lt(float(order[i]), float(order[i + 1]), "从左到右：修炼 历练 突破 功法 背包")
	assert_almost_eq(float(order[2]), 540.0, 4.0, "突破圆钮在正中")
	assert_true(bar.button_of("breakthrough") is QBreakButton)
	assert_eq(bar.center_sub_text(), "筑基一层", "圆钮下面写下一境界（真数据）")
	bar.button_of("bag").pressed.emit()
	await get_tree().process_frame
	assert_true((scene.get("_pages")["bag"] as Control).visible)
	assert_eq(bar.current, "bag")


func test_center_button_ready_opens_the_existing_breakthrough_flow() -> void:
	var scene := await _boot("ready")
	var bar := scene.get("_tab_bar") as TabBarView
	assert_eq(bar.center_state(), "ready", "修为满 + 守关首领已过 → 可突破")
	assert_true(bar.center_button().has_dot())
	assert_false(bar.center_button().disabled)
	bar.center_pressed.emit()
	await get_tree().process_frame
	assert_true(scene.call("breakthrough_open"), "点圆钮打开突破弹窗")
	var page := scene.get("_breakthrough_page") as BreakthroughPage
	assert_false(page.start_button().disabled, "可突破时「突破」按钮可点")


func test_center_button_hint_state_explains_and_still_shows_the_conditions() -> void:
	var scene := await _boot("gate")
	var bar := scene.get("_tab_bar") as TabBarView
	assert_eq(bar.center_state(), "hint", "条件不够：提示态")
	assert_false(bar.center_button().has_dot())
	bar.center_pressed.emit()
	await get_tree().process_frame
	assert_ne(_toast(scene).text(), "", "提示还差什么")
	assert_true(scene.call("breakthrough_open"), "照样打开弹窗看条件")
	assert_true((scene.get("_breakthrough_page") as BreakthroughPage).start_button().disabled)


func test_center_button_max_state_is_disabled() -> void:
	var button := QBreakButton.new()
	add_child_autofree(button)
	button.set_state("max")
	assert_true(button.disabled, "最高境界：圆钮不可点")
	assert_eq(button.title_text(), "已圆满")
	button.set_state("hint")
	assert_false(button.disabled)


func test_locked_buttons_all_say_feature_not_open() -> void:
	var scene := await _boot("ready")
	var toast := _toast(scene)
	var top := scene.get("_top_bar") as Control
	var mail := top.find_child("MailButton", true, false) as BaseButton
	assert_not_null(mail)
	assert_true(LockedFeature.is_locked(mail))
	var before := LockedFeature.count
	mail.pressed.emit()
	assert_eq(LockedFeature.count, before + 1)
	assert_eq(LockedFeature.last_feature, "mail")
	assert_eq(toast.text(), LockedFeature.TEXT)
	var expected := {
		"_top_bar": ["mail", "currency_gourd"],
		"_home_page": ["alchemy", "idle_chest"],
		"_skill_page": ["skill_upgrade"],
		"_cave_page": ["cave_retreat", "cave_upgrade"],
		"_stage_page": ["auto_challenge"],
		"_bag_page": ["bag_sell"],
		"_offline_popup": ["offline_double"],
	}
	for owner in expected:
		var found := {}
		for button in LockedFeature.locked_buttons(scene.get(owner) as Node, [] as Array[BaseButton]):
			found[str(button.get_meta(LockedFeature.META))] = button
		for feature in expected[owner]:
			assert_true(found.has(feature), "%s 里有「%s」且标记为暂未开放" % [owner, feature])
			if found.has(feature):
				(found[feature] as BaseButton).pressed.emit()
				assert_eq(LockedFeature.last_feature, feature)
				assert_eq(toast.text(), LockedFeature.TEXT, feature)


func test_offline_claim_still_acknowledges_but_double_only_toasts() -> void:
	var scene := await _boot("ready")
	var popup := scene.get("_offline_popup") as OfflinePopup
	assert_true(popup.visible)
	watch_signals(popup)
	popup.double_button().pressed.emit()
	assert_signal_not_emitted(popup, "acknowledged", "双倍领取没有：不确认已读")
	assert_true(popup.visible)
	assert_eq(_toast(scene).text(), LockedFeature.TEXT)
	popup.claim_button().pressed.emit()
	assert_signal_emitted(popup, "acknowledged")
	for i in 5:
		await get_tree().process_frame
	assert_false(popup.visible, "领取后关掉弹窗")


func test_offline_popup_shows_opened_chest() -> void:
	var scene := await _boot("ready")
	var popup := scene.get("_offline_popup") as OfflinePopup
	var chest := popup.find_child("Chest", true, false) as TextureRect
	assert_not_null(chest)
	assert_true(ArtLib.has_q("sprites/chest_open.png"), "开箱图已入库")
	assert_eq(chest.texture.resource_path, "res://assets/art/q/sprites/chest_open.png", "离线弹窗用打开的宝箱")


func test_toast_is_one_shared_component() -> void:
	var scene := await _boot("ready")
	assert_eq(get_tree().get_nodes_in_group(LockedFeature.GROUP).size(), 1, "只有一个 Toast 接「功能暂未开放」")
	LockedFeature.notify(scene, "test")
	assert_eq(_toast(scene).text(), "功能暂未开放")
