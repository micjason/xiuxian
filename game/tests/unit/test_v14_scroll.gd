extends GutTest
## v14 滚动：所有 ScrollContainer 不显示滚动条；历练列表、背包格子在按钮上拖也能滚、跟手、拖动不触发点击；
## 心跳刷新内容没变时不重建（原来每次心跳都整页重建，滚动被打断、卡一下）。


func before_all() -> void:
	TouchSim.mute_gut_gui(self)


func after_all() -> void:
	TouchSim.restore_gut_gui()


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


func _boot(scenario: String = "full") -> Node:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	OS.set_environment("XIUXIAN_MOCK_SCENARIO", scenario)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(scene)
	for i in 4:
		await get_tree().process_frame
	OS.unset_environment("XIUXIAN_UI_MOCK")
	OS.unset_environment("XIUXIAN_MOCK_SCENARIO")
	(scene.get("_offline_popup") as Control).hide()
	return scene


func _scrolls(root: Node) -> Array[ScrollContainer]:
	var out: Array[ScrollContainer] = []
	for node in root.find_children("*", "ScrollContainer", true, false):
		out.append(node as ScrollContainer)
	return out


func _assert_no_bars(root: Node, label: String) -> void:
	var list := _scrolls(root)
	assert_gt(list.size(), 0, label)
	for scroll in list:
		var path := str(root.get_path_to(scroll))
		assert_false(scroll.get_v_scroll_bar().visible, "%s %s 竖滚动条不显示" % [label, path])
		assert_false(scroll.get_h_scroll_bar().visible, "%s %s 横滚动条不显示" % [label, path])
		for mode in [scroll.vertical_scroll_mode, scroll.horizontal_scroll_mode]:
			assert_true(mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER or mode == ScrollContainer.SCROLL_MODE_DISABLED, "%s %s 模式是 SHOW_NEVER / DISABLED" % [label, path])
		assert_not_null(ScrollKit.of(scroll), "%s %s 有 ScrollKit（手指拖动 + 惯性）" % [label, path])


func test_every_scroll_container_in_the_game_hides_its_bars() -> void:
	var scene := await _boot()
	for page in ["cultivate", "adventure", "bag", "skill", "cave"]:
		scene.call("_show_page", page)
		await get_tree().process_frame
		await get_tree().process_frame
	_assert_no_bars(scene, "各页")
	# 弹窗里的滚动区（物品详情）也一样
	var bag := scene.get("_bag_page") as BagPage
	scene.call("_show_page", "bag")
	await get_tree().process_frame
	var first := bag.model.visible_items("all")[0]
	bag.call("_on_slot", first)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_no_bars(scene, "弹窗打开后")
	var theme := scene.get("theme") as Theme
	for bar in ["VScrollBar", "HScrollBar"]:
		for box in ["scroll", "grabber"]:
			assert_true(theme.get_stylebox(box, bar) is StyleBoxEmpty, "主题里 %s/%s 是空样式" % [bar, box])


func test_bag_grid_drag_on_slots_scrolls_and_does_not_open_the_popup() -> void:
	var scene := await _boot("full")
	scene.call("_show_page", "bag")
	await get_tree().process_frame
	await get_tree().process_frame
	var bag := scene.get("_bag_page") as BagPage
	var grid := bag.find_child("BagGrid", true, false) as ItemGrid
	var kit := ScrollKit.of(grid)
	assert_gt(kit.max_scroll(), 50.0, "满背包时格子超出可视区（要能滚）")
	var rect := grid.get_global_rect()
	# 从一个物品格的正中开始拖（原来这里按在 Button 上，事件到不了 ScrollContainer → 滚不动）
	var slot := grid.find_children("*", "ItemSlot", true, false)[6] as Control
	var from := slot.get_global_rect().get_center()
	assert_true(rect.has_point(from))
	var to := from - Vector2(0, minf(kit.max_scroll(), 160.0) + ScrollKit.DEADZONE + 4.0)
	await TouchSim.drag(get_tree(), get_viewport(), from, to, 10, true)
	assert_gt(grid.scroll_vertical, 40, "格子跟手滚动")
	assert_false((scene.get("_item_popup") as ItemDetailPopup).visible, "拖动后松手不弹物品详情")
	assert_false((scene.get("_popup") as GamePopup).visible, "也不弹通用弹层")


func test_bag_tap_on_slot_opens_detail_popup() -> void:
	var scene := await _boot("full")
	scene.call("_show_page", "bag")
	await get_tree().process_frame
	await get_tree().process_frame
	var grid := (scene.get("_bag_page") as BagPage).find_child("BagGrid", true, false) as ItemGrid
	var slot := grid.find_children("*", "ItemSlot", true, false)[0] as Control
	await TouchSim.tap(get_tree(), get_viewport(), slot.get_global_rect().get_center())
	await get_tree().process_frame
	assert_true((scene.get("_item_popup") as ItemDetailPopup).visible, "点一下格子打开物品详情")


func test_stage_list_drag_on_cards_scrolls_without_selecting() -> void:
	var scene := await _boot("full")
	scene.call("_show_page", "adventure")
	await get_tree().process_frame
	await get_tree().process_frame
	var page := scene.get("_stage_page") as StagePage
	var view := page.get("_stage_view") as ScrollContainer
	var kit := ScrollKit.of(view)
	assert_gt(kit.max_scroll(), 50.0, "关卡区内容超出可视区")
	var before_selected := page.selected
	var card := page.find_child("StageCards", true, false) as Control
	var from := card.get_global_rect().get_center()
	var to := from - Vector2(0, kit.max_scroll() + 40.0)
	await TouchSim.drag(get_tree(), get_viewport(), from, to, 10, true)
	assert_gt(view.scroll_vertical, 40, "按在关卡卡上竖着拖，列表滚动")
	assert_eq(page.selected, before_selected, "拖动不会选中关卡")
	assert_false((scene.get("_battle_page") as Control).visible, "也不会进战斗")


func test_heartbeat_with_unchanged_state_does_not_rebuild_lists() -> void:
	var scene := await _boot("full")
	scene.call("_show_page", "bag")
	await get_tree().process_frame
	var bag := scene.get("_bag_page") as BagPage
	var grid := bag.find_child("BagGrid", true, false) as ItemGrid
	var stage := scene.get("_stage_page") as StagePage
	var refreshes := bag.refresh_count
	var rebuilds := grid.rebuilds
	var detail := stage.find_child("StageDetailCard", true, false)
	var first_slot := grid.find_children("*", "ItemSlot", true, false)[0]
	for i in 3:
		scene.call("_render", true)
		await get_tree().process_frame
	assert_eq(bag.refresh_count, refreshes, "背包没变就不刷新")
	assert_eq(grid.rebuilds, rebuilds, "格子不重建")
	assert_same(grid.find_children("*", "ItemSlot", true, false)[0], first_slot, "格子节点还是原来那个（按住的格子不会消失）")
	assert_same(stage.find_child("StageDetailCard", true, false), detail, "历练列表不重建")


func test_bag_refreshes_when_items_change_and_reuses_slots() -> void:
	var scene := await _boot("full")
	var bag := scene.get("_bag_page") as BagPage
	var grid := bag.find_child("BagGrid", true, false) as ItemGrid
	var first_slot := grid.find_children("*", "ItemSlot", true, false)[0]
	var state: Dictionary = scene.get("_state")
	var items: Array = state.get("items", [])
	var unequipped := items.filter(func(r: Dictionary) -> bool: return r.get("equippedSlot", null) == null)
	items.erase(unequipped[0])
	scene.call("_render", true)
	await get_tree().process_frame
	assert_eq(grid.filled_count(), bag.model.visible_items(bag.category).size(), "物品变了照常刷新")
	assert_same(grid.find_children("*", "ItemSlot", true, false)[0], first_slot, "复用格子，不全删全建")
