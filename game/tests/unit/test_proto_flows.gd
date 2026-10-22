extends GutTest
## 三条主线在整个界面壳里走通（演示数据 ProtoMock，不连服务器）：
## 1) 首领战 + 大招  2) 离线收益弹窗  3) 境界突破；外加背包满提示。
## 无头模式下字体缓存会往日志里报引擎错误（已知，和逻辑无关），这里不把引擎错误算失败，只看断言。

const PlayScreen := preload("res://scripts/ui/play_screen.gd")


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


func _gate_slug(scene: Node) -> String:
	return str(((scene.get("_state") as Dictionary).breakthrough.requiredStage as Dictionary).slug)


func _run_fight(scene: Node, _unused: bool = false) -> void:
	var page := scene.get("_battle_page") as BattlePage
	page._on_start()
	assert_eq(page.phase, BattlePage.Phase.RUNNING)
	var guard := 0
	while page.phase == BattlePage.Phase.RUNNING and guard < 400:
		page.step(0.25)
		guard += 1
	await wait_frames(3)


func test_chain1_boss_fight_submits_and_shows_the_server_result() -> void:
	var scene := await _boot("ready")
	var slug := _gate_slug(scene)
	scene.call("_open_battle", slug)
	var page := scene.get("_battle_page") as BattlePage
	assert_eq(page.phase, BattlePage.Phase.READY)
	assert_eq(page.fight.time_limit, 45.0, "限时 45 秒来自 content.globals.combat")
	watch_signals(page)
	await _run_fight(scene, true)
	assert_signal_emitted(page, "submit_requested")
	assert_eq(get_signal_parameters(page, "submit_requested"), [slug], "第四批：只带关卡，不再上报大招点击")
	assert_eq(page.phase, BattlePage.Phase.RESULT, "结果以服务器（这里是 ProtoMock）返回为准")
	var view := page.last_view()
	assert_true(["挑战成功", "挑战失败"].has(str(view.title)))
	assert_string_contains(page.report_text(), "释放「")
	if bool(view.win):
		assert_true(bool(((scene.get("_state") as Dictionary).breakthrough.requiredStage as Dictionary).cleared), "打赢首领 → 突破关卡条件满足")


func test_chain1_without_taps_the_ultimate_still_auto_casts() -> void:
	var scene := await _boot("ready")
	scene.call("_open_battle", _gate_slug(scene))
	var page := scene.get("_battle_page") as BattlePage
	watch_signals(page)
	await _run_fight(scene, false)
	assert_eq((get_signal_parameters(page, "submit_requested") as Array).size(), 1)
	assert_eq(page.phase, BattlePage.Phase.RESULT)
	assert_gt(page.fight.casts.size(), 0, "冷却完毕自动释放")


func test_chain2_offline_popup_shows_once_and_ack_clears_the_report() -> void:
	var scene := await _boot("ready")
	var popup := scene.get("_offline_popup") as OfflinePopup
	assert_true(popup.visible, "有未确认的离线报告就弹窗")
	var view := popup.current_view()
	assert_eq(str(view.total_text), "+33,120", "28,800 + 4,320 = 33,120")
	assert_not_null(popup.claim_button())
	var report_id := str((scene.get("_state") as Dictionary).offlineReport.id)
	popup.claim_button().pressed.emit()
	await wait_seconds(0.35)  # 先播关闭动画（0.22s）再隐藏
	assert_false(popup.visible)
	assert_null((scene.get("_state") as Dictionary).get("offlineReport"))
	scene.call("_maybe_show_offline")
	assert_false(popup.visible, "确认过的不再弹：%s" % report_id)


func test_chain3_breakthrough_needs_the_gate_boss_then_succeeds_and_shows_before_after() -> void:
	var scene := await _boot("gate")
	var page := scene.get("_breakthrough_page") as BreakthroughPage
	scene.call("_open_breakthrough")
	var blocked := page.view()
	assert_false(bool(blocked.can_start), "修为够但没打过首领不能突破")
	var before_power := int((scene.get("_state") as Dictionary).power)
	scene.call("_open_battle", _gate_slug(scene))
	await _run_fight(scene, true)
	var battle := scene.get("_battle_page") as BattlePage
	if not bool(battle.last_view().win):
		pending("首领战没打赢，演示数据下未触发突破")
		return
	scene.call("_open_breakthrough")
	assert_true(bool(page.view().can_start))
	scene.call("_on_breakthrough")
	var success := scene.get("_success_popup") as BreakthroughSuccess
	# 天雷渡劫约 10 秒，播完才出结算弹窗（不再加旧 success 的 2.4s）
	await wait_until(func() -> bool: return success.visible, 14.0)
	assert_true(success.visible)
	var summary := success.summary()
	assert_eq(int(summary.power_before), before_power)
	assert_gt(int(summary.power_after), before_power)
	assert_eq(int((scene.get("_state") as Dictionary).power), int(summary.power_after))


func test_bag_full_does_not_block_the_fight_and_the_result_shows_the_prompt() -> void:
	var scene := await _boot("full")
	var state: Dictionary = scene.get("_state")
	scene.call("_render")
	scene.call("_open_battle", _gate_slug(scene))
	var page := scene.get("_battle_page") as BattlePage
	assert_true(bool((page.get("_gate") as Dictionary).full))
	page._on_start()
	assert_eq(page.phase, BattlePage.Phase.RUNNING, "背包满也照常开战")
	assert_eq(BagFullPrompt.texts(20, 20), ["背包已满（20/20）", "新掉落的装备没能入包"] as Array[String])
	await _run_fight(scene, true)
	assert_eq(page.phase, BattlePage.Phase.RESULT)
	var view: Dictionary = page.last_view()
	assert_true(bool(view.win))
	assert_true((view.notes as Array).any(func(n: String) -> bool: return n.begins_with("行囊已满")))
	assert_true((view.loot as Array).any(func(l: Dictionary) -> bool: return str(l.text).contains("背包已满，没有掉落")))
	assert_false((scene.get("_popup") as GamePopup).visible, "第五批 §17.5：不再弹背包已满提示（改为历练页提示条 + 底栏已满角标）")
	assert_true((scene.get("_tab_bar") as TabBarView).is_full("bag"), "底栏背包换成 badge_full")


func test_four_tabs_and_heartbeat_interval_follow_server_window() -> void:
	var scene := await _boot("ready")
	assert_eq((scene.get("_tab_bar") as TabBarView)._buttons.size(), 5, "修炼/历练/突破/功法/背包")
	assert_eq(PlayScreen.heartbeat_seconds({"wave": {"onlineGapSeconds": 15}}), 12.0)
	assert_eq(PlayScreen.heartbeat_seconds({}), PlayScreen.HEARTBEAT_DEFAULT)
	assert_eq(PlayScreen.heartbeat_seconds({"wave": {"onlineGapSeconds": 2}}), 1.0)
