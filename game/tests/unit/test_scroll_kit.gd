extends GutTest
## ScrollKit：滚动条隐藏、手指拖动跟手 + 惯性、拖动不触发点击、点击照常、嵌套横竖各管各的。

var _root: Control
var _scroll: ScrollContainer
var _taps: Array = []


func before_all() -> void:
	TouchSim.mute_gut_gui(self)


func after_all() -> void:
	TouchSim.restore_gut_gui()


func before_each() -> void:
	_taps.clear()
	_root = Control.new()
	_root.position = Vector2.ZERO
	_root.size = Vector2(1080, 2340)
	add_child_autofree(_root)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.position = Vector2(100, 200)
	_scroll.size = Vector2(600, 800)
	_root.add_child(_scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(box)
	for i in 30:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 100)
		b.text = "row %d" % i
		b.pressed.connect(func() -> void: _taps.append(i))
		box.add_child(b)
	ScrollKit.install(_root)
	await get_tree().process_frame
	await get_tree().process_frame


func test_install_hides_both_bars_and_keeps_scrolling() -> void:
	assert_eq(_scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_SHOW_NEVER)
	assert_eq(_scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "禁用的方向保持禁用")
	assert_false(_scroll.get_v_scroll_bar().visible)
	assert_false(_scroll.get_h_scroll_bar().visible)
	assert_not_null(ScrollKit.of(_scroll))
	assert_gt(ScrollKit.of(_scroll).max_scroll(), 1000.0)
	# 之后有人改回 AUTO 也会被压回去
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(_scroll.get_v_scroll_bar().visible, "改回 AUTO 后滚动条仍不显示")


func test_new_scroll_containers_are_taken_over_automatically() -> void:
	var late := ScrollContainer.new()
	_root.add_child(late)
	assert_not_null(ScrollKit.of(late))
	assert_eq(late.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_SHOW_NEVER)
	assert_eq(late.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_SHOW_NEVER)


func test_touch_drag_on_buttons_scrolls_and_never_taps() -> void:
	var vp := get_viewport()
	await TouchSim.drag(get_tree(), vp, Vector2(400, 900), Vector2(400, 400), 10, false)
	var mid := float(_scroll.scroll_vertical)
	assert_almost_eq(mid, 500.0 - ScrollKit.DEADZONE, 40.0, "跟手：内容跟着手指走（扣掉死区）")
	assert_true(ScrollKit.of(_scroll).is_dragging())
	TouchSim.up(vp, Vector2(400, 400))
	await get_tree().process_frame
	assert_eq(_taps, [], "拖动后松手不触发按钮")
	assert_false(ScrollKit.tap_blocked(), "松手那一帧过后清掉，不影响之后的点击")


func test_fling_keeps_scrolling_after_release_then_stops() -> void:
	var vp := get_viewport()
	await TouchSim.drag(get_tree(), vp, Vector2(400, 900), Vector2(400, 500), 4, true)
	var at_release := float(_scroll.scroll_vertical)
	var kit := ScrollKit.of(_scroll)
	assert_true(kit.is_flinging(), "快速划动松手后有惯性")
	for i in 20:
		await get_tree().process_frame
	assert_gt(float(_scroll.scroll_vertical), at_release + 20.0, "松手后继续滑")
	await wait_seconds(2.5)
	assert_false(kit.is_flinging(), "惯性会停下")


func test_press_during_fling_stops_it_and_does_not_tap() -> void:
	var vp := get_viewport()
	await TouchSim.drag(get_tree(), vp, Vector2(400, 900), Vector2(400, 500), 4, true)
	assert_true(ScrollKit.of(_scroll).is_flinging())
	await TouchSim.tap(get_tree(), vp, Vector2(400, 600))
	assert_false(ScrollKit.of(_scroll).is_flinging(), "按住就停")
	assert_eq(_taps, [], "停住列表的那一下不算点击")


func test_tap_still_works() -> void:
	await TouchSim.tap(get_tree(), get_viewport(), Vector2(400, 250))
	assert_eq(_taps, [0], "原地点一下照常触发")
	assert_false(ScrollKit.tap_blocked())


func test_small_jitter_within_deadzone_is_still_a_tap() -> void:
	var vp := get_viewport()
	await TouchSim.drag(get_tree(), vp, Vector2(400, 360), Vector2(404, 368), 3, true)
	assert_eq(_taps, [1], "手指抖动在死区内仍算点击")
	assert_eq(_scroll.scroll_vertical, 0)


func test_nested_horizontal_row_scrolls_sideways_and_parent_vertically() -> void:
	var box := _scroll.get_child(0) as VBoxContainer
	var row_scroll := ScrollContainer.new()
	row_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row_scroll.custom_minimum_size = Vector2(0, 200)
	var row := HBoxContainer.new()
	for i in 10:
		var card := Button.new()
		card.custom_minimum_size = Vector2(250, 180)
		card.pressed.connect(func() -> void: _taps.append("card%d" % i))
		row.add_child(card)
	row_scroll.add_child(row)
	box.add_child(row_scroll)
	box.move_child(row_scroll, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport()
	await TouchSim.drag(get_tree(), vp, Vector2(600, 300), Vector2(200, 300), 10, false)
	assert_gt(row_scroll.scroll_horizontal, 300, "横向拖 → 关卡卡那一排横滚")
	assert_eq(_scroll.scroll_vertical, 0, "外层不动")
	TouchSim.up(vp, Vector2(200, 300))
	await wait_seconds(1.5)
	await TouchSim.drag(get_tree(), vp, Vector2(400, 350), Vector2(400, 150), 10, true)
	assert_gt(_scroll.scroll_vertical, 100, "在横排上竖着拖 → 外层竖滚")
	assert_eq(_taps, [], "都没有触发点击")


func test_drag_over_a_covering_popup_does_not_scroll_the_list_below() -> void:
	var cover := ColorRect.new()
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	cover.position = Vector2(0, 0)
	cover.size = Vector2(1080, 2340)
	_root.add_child(cover)
	await get_tree().process_frame
	await TouchSim.drag(get_tree(), get_viewport(), Vector2(400, 900), Vector2(400, 400), 10, true)
	assert_eq(_scroll.scroll_vertical, 0, "上面盖着弹窗时不滚下面的列表")
