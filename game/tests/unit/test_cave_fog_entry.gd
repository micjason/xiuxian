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
	entry.pressed.emit()
	assert_eq(str(screen.get("_page")), "fog")
	assert_eq(screen.TAB_OF.get("fog"), "cave")
	var fog: Control = screen.get("_fog_page")
	fog.emit_signal("back_requested")
	assert_eq(str(screen.get("_page")), "cave")
	assert_true(cave.is_visible_in_tree())
