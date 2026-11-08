extends GutTest

func test_fog_entry_is_available_without_cave_facilities() -> void:
	var page := CavePage.new()
	add_child_autofree(page)
	page.bind({}, {})
	await get_tree().process_frame
	assert_false(bool(page.get("_view").get("available", false)))
	var entry := page.find_child("Enter_fog", true, false) as Button
	assert_not_null(entry, "独立迷雾入口不依赖洞府开放")
	if entry == null:
		return
	assert_false(entry.disabled)
	assert_eq(CavePage.HS_FOG, Rect2(48, 1480, 984, 200))
	assert_lt(CavePage.HS_FOG.end.y, CavePage.HS_ALLOC.position.y)
	assert_eq(entry.text, "迷雾秘境\n探索问心谷")
	watch_signals(page)
	entry.pressed.emit()
	assert_signal_emitted(page, "fog_requested")
	assert_eq(page.mode(), "overview", "不进入洞府设施")
	assert_null(page.find_child("Enter_array", true, false), "不开放阵法")

func test_cave_fog_navigation_and_back_select_cave() -> void:
	var screen: Control = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(screen)
	await get_tree().create_timer(0.2).timeout
	screen.call("_show_page", "cave")
	var cave: CavePage = screen.get("_cave_page")
	var entry := cave.find_child("Enter_fog", true, false) as Button
	assert_not_null(entry)
	if entry == null:
		return
	assert_false(entry.disabled)
	# 此用例没有真实 API；只验证页签与返回，不用即时切页冒充加载成功。
	screen.call("_show_page", "fog")
	assert_eq(screen.TAB_OF.get("fog"), "cave")
	var fog: Control = screen.get("_fog_page")
	fog.emit_signal("back_requested")
	assert_eq(str(screen.get("_page")), "cave")
	assert_true(cave.is_visible_in_tree())

func test_both_fog_entries_await_loading_before_showing_map() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/play_screen.gd")
	assert_true(source.contains("_stage_page.fog_requested.connect(func() -> void: await _open_fog())"))
	assert_true(source.contains("_cave_page.fog_requested.connect(func() -> void: await _open_fog())"))
	var show_page := source.get_slice("func _show_page(", 1).get_slice("\nfunc ", 0)
	assert_false(show_page.contains("_ensure_fog_loaded"), "切页不重复 GET；加载由 _open_fog 完成")
	assert_true(source.contains("func _ensure_fog_loaded()"), "保留旧函数本身")

func test_exit_is_distinct_and_locked_until_exploration_full() -> void:
	var page := FogMapPage.new()
	add_child_autofree(page)
	var payload := {"fog": {"rows": 3, "cols": 3, "pos": {"x": 1, "y": 2}, "revealed": ["1,1", "1,2"], "exploreRevealed": 2, "exploreTotal": 9, "exploreFull": false, "travelPoints": 0, "objects": [{"id": "m_guard", "kind": "exit", "x": 1, "y": 1, "name": "谷口护卫", "passed": false}]}}
	page.bind_fog(payload)
	await get_tree().process_frame
	assert_not_null(page.find_child("Exit_m_guard", true, false), "出口不是普通狼图")
	var exploration := page.find_child("FogExplore", true, false) as Label
	assert_not_null(exploration)
	if exploration != null:
		assert_eq(exploration.text, "探索 2/9")
	watch_signals(page)
	page.call("_on_cell", 1, 1)
	assert_signal_emitted(page, "toast_requested")
	assert_false((page.get("_confirm") as Control).visible)
	assert_signal_not_emitted(page, "battle_requested")
	payload.fog.exploreFull = true
	payload.fog.exploreRevealed = 9
	page.bind_fog(payload)
	page.call("_on_cell", 1, 1)
	assert_true((page.get("_confirm") as Control).visible)
	assert_true((page.get("_confirm_label") as Label).text.contains("出口"))

func test_fog_loot_refresh_wraps_raw_state_for_action_renderer() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/play_screen.gd")
	var refresh := source.get_slice("func _refresh_state_soft()", 1).get_slice("\nfunc ", 0)
	assert_true(refresh.contains('_apply_action_state({"state": state})'), "GET state是裸DTO，不能当action wrapper传入清空背包")

func test_fog_confirm_and_event_dialogs_fit_phone_width() -> void:
	var page := FogMapPage.new()
	page.size = Vector2(1000, 1900)
	add_child_autofree(page)
	for key in ["_confirm", "_event_panel"]:
		var dialog: Control = page.get(key)
		dialog.show()
		await get_tree().process_frame
		assert_gte(dialog.position.x, 0.0)
		assert_lte(dialog.get_rect().end.x, page.size.x, "战斗/事件按钮不能被手机右边裁掉")
