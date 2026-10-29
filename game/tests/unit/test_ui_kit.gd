extends GutTest
## 通用组件和页面：触控尺寸、格子状态、网格补位与多选、弹层、页面能用真实/演示数据搭起来。

const MIN_TOUCH := 128


func _flags() -> ItemFlags:
	var flags := ItemFlags.new()
	flags.path = "user://test_kit_flags.json"
	return flags


func test_item_slot_is_at_least_a_touch_target() -> void:
	var slot := ItemSlot.new()
	add_child_autofree(slot)
	assert_gte(slot.custom_minimum_size.x, MIN_TOUCH)
	assert_gte(slot.custom_minimum_size.y, MIN_TOUCH)


func test_item_slot_shows_count_enhance_new_and_equipped_markers() -> void:
	var slot := ItemSlot.new()
	add_child_autofree(slot)
	slot.set_item({"id": "x", "name": "铁剑", "rarity": 3, "qty": 12, "enhance": 5, "is_new": true, "equipped": true, "slot_id": "weapon"})
	assert_eq(slot._count.text, "×12")
	assert_eq(slot._enhance.text, "+5")
	assert_true(slot._new.visible)
	assert_true(slot._equipped.visible)
	assert_false(slot._glow.visible, "Q 版靠品质底色区分，不再叠光晕")
	assert_not_null(slot._icon_tex.texture, "装备显示部位图标")
	slot.set_item({"id": "y", "name": "铁剑", "rarity": 0, "qty": 1, "enhance": 0, "is_new": true, "equipped": false})
	assert_false(slot._glow.visible)
	assert_eq(slot._count.text, "")
	assert_eq(slot._enhance.text, "")
	assert_true(slot._new.visible)
	slot.set_empty()
	assert_true(slot.is_empty_slot())
	assert_true(slot.disabled)


func test_item_slot_frame_follows_rarity() -> void:
	var slot := ItemSlot.new()
	add_child_autofree(slot)
	for rarity in 6:
		slot.set_item({"id": "r%d" % rarity, "name": "物", "rarity": rarity, "qty": 1})
		var box := slot.get_theme_stylebox("normal") as StyleBoxTexture
		assert_not_null(box, "品质框是美术切图")
		assert_eq(box.texture, ArtLib.qui(str(QKit.SLOT_CUTS[rarity])), "Q 版品质格 slot_white…slot_red")
	slot.set_empty()
	assert_eq((slot.get_theme_stylebox("normal") as StyleBoxTexture).texture, ArtLib.qui("slot_empty"))


func test_item_slot_icon_follows_slot_then_category() -> void:
	assert_eq(KitStyle.icon_for({"slot_id": "gloves", "category": "equip"}).texture.resource_path, "res://assets/art/q/items/gear_gloves.png", "有物品图就用物品图（Q 版）")
	assert_not_null(KitStyle.icon_for({"category": "material"}).texture, "材料有图（物品图或类别图）")
	assert_eq(KitStyle.icon_for({"category": "other", "kind": "skill_book"}).texture.resource_path, "res://assets/art/q/items/book_other.png")
	assert_false(KitStyle.icon_for({"slot_id": "weapon", "category": "equip"}).tint, "彩色物品图不染色（剪影占位图才按品质染色）")


func test_grid_pads_with_empty_slots_and_keeps_capacity_cap() -> void:
	var grid := ItemGrid.new()
	add_child_autofree(grid)
	var items: Array[Dictionary] = []
	for i in 7:
		items.append({"id": "i%d" % i, "name": "物%d" % i, "rarity": 0, "qty": 1})
	grid.set_items(items, 5, 0)
	assert_eq(grid.slot_count(), 25)
	assert_eq(grid.filled_count(), 7)
	grid.set_items(items, 5, 10)
	assert_eq(grid.slot_count(), 10, "补位不超过容量（按整行取整）")
	var many: Array[Dictionary] = []
	for i in 12:
		many.append({"id": "m%d" % i, "name": "物", "rarity": 0, "qty": 1})
	grid.set_items(many, 1, 5)
	assert_eq(grid.slot_count(), 12, "物品比容量多时全部显示")
	await wait_frames(2)


func test_grid_multi_select_toggles_and_respects_selectable() -> void:
	var grid := ItemGrid.new()
	add_child_autofree(grid)
	grid.selectable = func(item: Dictionary) -> bool: return not bool(item.get("equipped", false))
	var items: Array[Dictionary] = [
		{"id": "a", "name": "甲", "rarity": 1, "qty": 1},
		{"id": "b", "name": "乙", "rarity": 1, "qty": 1, "equipped": true},
	]
	grid.set_items(items)
	grid.set_multi_select(true)
	watch_signals(grid)
	grid._on_slot(items[0])
	assert_eq(grid.selected_ids(), ["a"])
	grid._on_slot(items[1])
	assert_eq(grid.selected_ids(), ["a"], "已穿戴的不能被选")
	assert_signal_emitted(grid, "slot_pressed")
	grid._on_slot(items[0])
	assert_eq(grid.selected_ids().size(), 0)
	grid.select_all()
	assert_eq(grid.selected_ids(), ["a"])
	grid.set_multi_select(false)
	assert_eq(grid.selected_ids().size(), 0)


func test_equip_slot_cell_states() -> void:
	var cell := EquipSlotCell.new()
	add_child_autofree(cell)
	assert_gte(cell.custom_minimum_size.y, MIN_TOUCH)
	cell.setup(SlotConfig.find("weapon"), {})
	assert_eq(cell._item_label.text, "空")
	cell.setup(SlotConfig.find("weapon"), {"name": "青锋剑", "rarity": 2, "enhance": 3, "slot_id": "weapon"})
	assert_eq(cell._item_label.text, "青锋剑")
	assert_eq(cell._badge.text, "+3")
	cell.setup(SlotConfig.find("gloves"), {})
	assert_eq(cell._item_label.text, "空", "手部是第六个核心部位，可以穿戴")
	assert_eq((cell.get_theme_stylebox("normal") as StyleBoxTexture).texture, ArtLib.ui("slot_empty"))
	cell.setup(SlotConfig.find("pet"), {})
	assert_eq(cell._item_label.text, "第三期开放")
	assert_eq((cell.get_theme_stylebox("normal") as StyleBoxTexture).texture, ArtLib.ui("slot_locked"))
	watch_signals(cell)
	cell.pressed.emit()
	assert_signal_emitted_with_parameters(cell, "slot_pressed", ["pet"])


func test_seg_tabs_select_and_emit() -> void:
	var tabs := SegTabs.new()
	add_child_autofree(tabs)
	tabs.set_tabs([{"id": "a", "name": "甲", "badge": "3"}, {"id": "b", "name": "乙"}], "a")
	assert_eq(tabs.current, "a")
	assert_eq((tabs._buttons["a"] as Button).text, "甲 3")
	watch_signals(tabs)
	tabs.select("b", true)
	assert_eq(tabs.current, "b")
	assert_signal_emitted_with_parameters(tabs, "tab_changed", ["b"])
	for button in tabs._buttons.values():
		assert_gte((button as Button).custom_minimum_size.y, MIN_TOUCH)


func test_popup_opens_closes_and_runs_action_once() -> void:
	var popup := GamePopup.new()
	add_child_autofree(popup)
	var clicked := [0]
	popup.clear_content()
	popup.body.add_child(Label.new())
	popup.set_actions([{"text": "好", "callback": func() -> void: clicked[0] += 1}])
	watch_signals(popup)
	popup.open_popup("标题")
	assert_true(popup.visible)
	assert_eq(popup.title_label.text, "标题")
	var button := popup.actions.get_child(0) as Button
	assert_gte(button.custom_minimum_size.y, MIN_TOUCH)
	button.pressed.emit()
	assert_eq(clicked[0], 1)
	assert_false(popup.visible)
	assert_signal_emitted(popup, "closed")


func _bag_page(scene: String = "ready") -> BagPage:
	var page := BagPage.new()
	add_child_autofree(page)
	page.popup = GamePopup.new()
	add_child_autofree(page.popup)
	page.bind(ProtoMock.state(scene), ProtoMock.content(), _flags())
	return page


func test_bag_page_merges_equipment_slots_and_a_5x4_grid() -> void:
	var page := _bag_page()
	assert_eq(page._tabs._buttons.size(), 4, "全部/装备/丹药/材料")
	assert_eq(page._grid.columns, 6, "设计稿一行 6 格")
	assert_true(LockedFeature.is_locked(page._sell_button), "一键出售还没有：点了提示功能暂未开放")
	assert_eq((page.find_child("Stat_attack", true, false) as Label).text, QKit.grouped(float(ProtoMock.state("ready").get("attack", 0))), "属性取自玩家状态")
	assert_eq(page._cells.size(), SlotConfig.all().size(), "6 个核心部位 + 2 个预留")
	assert_eq(page._grid.slot_count(), 20, "空格补到容量 20（6 列）")
	assert_eq(page._grid.filled_count(), 11, "背包里 11 格（已穿戴的不占格；含炼器精粹一格）")
	assert_string_contains(page._capacity_label.text, "11 / 20")
	assert_false(page._wear_button.disabled, "背包里有更强的装备可一键穿戴")
	page._tabs.select("material", true)
	assert_eq(page._grid.filled_count(), 2, "突破石 + 炼器精粹")


func test_bag_page_has_no_auto_decompose_row_and_salvage_opens_the_dialog() -> void:
	var page := _bag_page()
	assert_null(page.find_child("AutoDecomposeRow", true, false), "第五批：自动分解开关去掉了")
	assert_null(page.find_child("BatchButton", true, false), "背包内批量多选去掉了")
	var full := _bag_page("full")
	assert_string_contains(full._capacity_label.text, "20 / 20")
	watch_signals(page)
	page.salvage_button().pressed.emit()
	assert_signal_emitted_with_parameters(page, "action_requested", ["open_salvage", []])


func test_bag_page_equip_slots_open_a_picker_that_requests_equip() -> void:
	var page := _bag_page()
	assert_eq(page.equip_cell("weapon").item.slug, "gear_major1_weapon_green")
	watch_signals(page)
	page._show_picker("weapon")
	assert_true(page.popup.visible)
	var row := page.popup.body.get_child(page.popup.body.get_child_count() - 1) as Button
	row.pressed.emit()
	assert_signal_emitted(page, "action_requested")
	assert_eq((get_signal_parameters(page, "action_requested") as Array)[0], "equip")


func test_wear_all_requests_every_better_piece() -> void:
	var page := _bag_page()
	watch_signals(page)
	page._on_wear_all()
	var params: Array = get_signal_parameters(page, "action_requested")
	assert_eq(params[0], "equip_many")
	assert_gt((params[1] as Array).size(), 0)


func test_stage_page_power_status_uses_text_and_symbol() -> void:
	assert_eq(StagePage.power_status(1000, 800).level, "ok")
	assert_eq(StagePage.power_status(700, 800).level, "warn")
	assert_eq(StagePage.power_status(100, 800).level, "bad")
	assert_eq(StagePage.power_status(100, 0).level, "none")
	for level in [StagePage.power_status(1000, 800), StagePage.power_status(100, 800)]:
		assert_ne(str(level.symbol), "", "不能只靠颜色表达状态")


const TABS := ["cultivate", "adventure", "skill", "bag"]


func test_main_scene_in_mock_mode_builds_the_five_slot_shell() -> void:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	OS.unset_environment("XIUXIAN_UI_MOCK")
	for page in ["_home_page", "_stage_page", "_battle_page", "_breakthrough_page", "_bag_page", "_skill_page", "_cave_page", "_tab_bar", "_top_bar", "_backdrop", "_toast"]:
		assert_not_null(scene.get(page), page)
	var tab_bar := scene.get("_tab_bar") as TabBarView
	assert_eq(tab_bar._buttons.size(), 5, "修炼/历练/突破（中间大圆钮）/洞府/背包")
	assert_not_null(tab_bar.center_button())
	for id in TABS:
		assert_not_null(tab_bar.button_of(id), id)
		assert_eq(tab_bar.button_of(id).size_flags_vertical, Control.SIZE_EXPAND_FILL, "页签铺满底栏高度")
	assert_gte(TabBarView.HEIGHT, MIN_TOUCH)
	for page in TABS:
		scene.call("_show_page", page)
		await get_tree().process_frame
		assert_true((scene.get("_pages")[page] as Control).visible, page)
		for other in TABS:
			if other != page:
				assert_false((scene.get("_pages")[other] as Control).visible, "%s 只显示当前页" % other)
	assert_false((scene.get_node("%BagPage") as Control).visible, "旧版节点保持隐藏")


func test_tab_bar_dots_and_selection() -> void:
	var bar := TabBarView.new()
	add_child_autofree(bar)
	bar.set_tabs([{"id": "a", "name": "甲", "icon": "tab_bag"}, {"id": "b", "name": "乙", "icon": "tab_skill"}] as Array[Dictionary], "a")
	assert_false(bar.has_dot("a"))
	bar.set_dot("b", true)
	assert_true(bar.has_dot("b"))
	bar.set_dot("b", false)
	assert_false(bar.has_dot("b"))
	watch_signals(bar)
	bar.select("b", true)
	assert_eq(bar.current, "b")
	assert_signal_emitted_with_parameters(bar, "page_selected", ["b"])
	assert_gte(TabBarView.HEIGHT, MIN_TOUCH)


func test_ratio_bar_fill_follows_ratio() -> void:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(400, 60)
	holder.size = Vector2(400, 60)
	add_child_autofree(holder)
	var bar := UiKit.ratio_bar(0.25, "bar_fill_jade", 44)
	holder.add_child(bar)
	bar.size = Vector2(400, 44)
	await wait_frames(3)
	var widths: Array = []
	for node in bar.find_children("*", "Control", true, false):
		widths.append((node as Control).size.x)
	assert_true(widths.any(func(w: float) -> bool: return w > 20.0 and w < 300.0), "填充条宽度应约为 25%%：%s" % [widths])


func _popup_texts(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for child in node.get_children():
		_popup_texts(child, out)
	return out


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _detail_for(slug: String, state: Dictionary = {}) -> GamePopup:
	var popup := GamePopup.new()
	add_child_autofree(popup)
	var data := state if not state.is_empty() else UiMock.state()
	var model := BagModel.from_state(data, UiMock.content(), {})
	var item: Dictionary
	for row in model.items:
		if row.slug == slug:
			item = row
	var worn := {} if item.equipped else EquipModel.worn_in(model, str(item.slot_id))
	ItemDetail.show_item(popup, item, worn, {}, model.enhance_exp)
	return popup


func test_enhance_card_on_a_node_shows_materials_and_a_disabled_break_button_when_short() -> void:
	var popup := _detail_for("sword_p")  # 紫 +5：需要下品突破石 ×8，有 6
	var texts := _popup_texts(popup.body)
	assert_true(texts.has("已到突破节点 +5"))
	assert_true(texts.has("突破石·下品"))
	assert_true(texts.has("✗ 6 / 8"))
	var go := _find_button(popup.body, "突破")
	assert_not_null(go)
	assert_true(go.disabled, "材料不足不能突破")
	assert_null(_find_button(popup.body, "一键强化"), "卡在节点上不显示强化按钮")
	assert_gte(go.custom_minimum_size.y, 96.0, "触控尺寸")


func test_enhance_card_break_button_is_enabled_when_materials_are_ready_and_fires_the_handler() -> void:
	var popup := GamePopup.new()
	add_child_autofree(popup)
	var model := BagModel.from_state(UiMock.state(), UiMock.content(), {})
	var item: Dictionary
	for row in model.items:
		if row.slug == "shoe_b":
			item = row
	var fired := []
	ItemDetail.show_item(popup, item, {}, {"breakthrough": func(id: String) -> void: fired.append(id)}, model.enhance_exp)
	assert_true(_popup_texts(popup.body).has("✓ 6 / 5"))
	var go := _find_button(popup.body, "突破")
	assert_false(go.disabled)
	go.pressed.emit()
	assert_eq(fired, [item.id])


func test_enhance_card_before_the_node_shows_the_next_requirement() -> void:
	var popup := _detail_for("acc_o")  # 橙 +4
	var joined := "\n".join(_popup_texts(popup.body))
	assert_string_contains(joined, "下一个突破节点 +5")
	assert_string_contains(joined, "突破石·下品 ×10（有 6）")
	assert_not_null(_find_button(popup.body, "强化"))


func test_decompose_is_disabled_with_a_reason_for_worn_gear() -> void:
	var popup := _detail_for("sword_g")
	var decompose: Button
	for text in _popup_texts(popup.body):
		if str(text).begins_with("分解 +"):
			decompose = _find_button(popup.body, str(text))
	assert_not_null(decompose)
	assert_true(decompose.disabled)
	assert_true(_popup_texts(popup.body).has("已穿戴，无法分解"))
	var spare := _detail_for("sword_w")
	for text in _popup_texts(spare.body):
		if str(text).begins_with("分解 +"):
			assert_false(_find_button(spare.body, str(text)).disabled)
