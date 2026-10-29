extends GutTest
## v14 物品详情弹窗（Q 版，scenes/ui/item_detail_popup.tscn）：点格子按类型打开 4 种版式；对比数值和箭头正确；
## 「穿 戴」走原来的穿戴流程并刷新背包 / 纸娃娃；功法书 / 突破石说明文案（种子数据修正后）。


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
	scene.call("_show_page", "bag")
	await get_tree().process_frame
	return scene


func _pick(bag: BagPage, test: Callable) -> Dictionary:
	for it in bag.model.items:
		if test.call(it):
			return it
	return {}


func _compare_target(bag: BagPage) -> Dictionary:
	return _pick(bag, func(it: Dictionary) -> bool: return it.category == "equip" and not it.equipped and not EquipModel.worn_in(bag.model, str(it.slot_id)).is_empty())


func _open(scene: Node, item: Dictionary) -> ItemDetailPopup:
	var bag := scene.get("_bag_page") as BagPage
	bag.call("_on_slot", item)
	await get_tree().process_frame
	await get_tree().process_frame
	return scene.get("_item_popup") as ItemDetailPopup


func _add_book(scene: Node, name_prefix: String) -> void:
	var state: Dictionary = scene.get("_state")
	var content: Dictionary = scene.get("_content")
	for def in content.get("items", []):
		if str(def.get("kind", "")) == "skill_book" and str(def.get("displayName", "")).begins_with(name_prefix):
			(state.items as Array).append({"id": "t-book", "itemSlug": str(def.slug), "equippedSlot": null, "isStack": false, "quantity": 1, "enhanceLevel": 0, "breakLevel": 0})
			break
	scene.call("_render", false)
	await get_tree().process_frame


func test_popup_is_a_reusable_scene_and_wired_in_play_screen() -> void:
	var popup := (load("res://scenes/ui/item_detail_popup.tscn") as PackedScene).instantiate()
	assert_true(popup is ItemDetailPopup)
	assert_false((popup as Control).visible, "默认隐藏")
	popup.free()
	var scene := await _boot()
	var item_popup := scene.get("_item_popup") as ItemDetailPopup
	assert_not_null(item_popup)
	assert_eq((scene.get("_bag_page") as BagPage).detail_popup, item_popup)


func test_equip_with_worn_counterpart_shows_comparison() -> void:
	var scene := await _boot()
	var bag := scene.get("_bag_page") as BagPage
	var item := _compare_target(bag)
	assert_false(item.is_empty(), "演示背包里有一件同部位已穿戴的装备")
	var popup := await _open(scene, item)
	assert_true(popup.visible)
	assert_eq(str(popup.view.type), "equip")
	assert_eq(str(popup.view.title), "装备详情")
	assert_true(popup.view.has("compare"))
	assert_has(popup.texts(), "属性对比")
	assert_not_null(popup.button_named("穿 戴"))
	assert_not_null(popup.button_named("强 化"))
	assert_not_null(popup.button_named("分 解"))
	assert_null(popup.button_named("卸 下"), "背包里的装备没有卸下")


func test_compare_values_and_arrows_are_correct() -> void:
	var scene := await _boot()
	var bag := scene.get("_bag_page") as BagPage
	var item := _compare_target(bag)
	var worn := EquipModel.worn_in(bag.model, str(item.slot_id))
	var cmp := ItemDetailView.compare_view(item, worn)
	var expected := BagModel.compare(item, worn)
	assert_eq(cmp.rows.size(), expected.size())
	for i in expected.size():
		var row: Dictionary = cmp.rows[i]
		assert_eq(row.value, BagModel.shown(float(expected[i].value)), "%s 本件" % row.label)
		assert_eq(row.other, BagModel.shown(float(expected[i].other)), "%s 身上" % row.label)
		assert_eq(row.delta, row.value - row.other, "%s 变化 = 本件 − 身上（按显示的数算）" % row.label)
	assert_eq(cmp.power.delta, int(item.power) - int(worn.power), "战力差")
	# 手工构造：攻击 +5、防御 −3 → 一个绿色上箭头、一个红色下箭头
	var a := {"stats": {"attack": 15.0, "defense": 2.0}, "power": 50, "name": "甲"}
	var b := {"stats": {"attack": 10.0, "defense": 5.0}, "power": 40, "name": "乙"}
	var view := ItemDetailView.compare_view(a, b)
	var by_key := {}
	for row in view.rows:
		by_key[row.key] = row.delta
	assert_eq(by_key.get("attack"), 5)
	assert_eq(by_key.get("defense"), -3)
	assert_eq(view.power.delta, 10)
	var popup := await _open(scene, item)
	var ups := popup.find_children("ArrowUp", "", true, false).size()
	var downs := popup.find_children("ArrowDown", "", true, false).size()
	var want_up := 0
	var want_down := 0
	for row in popup.view.compare.rows + [popup.view.compare.power]:
		if int(row.delta) > 0:
			want_up += 1
		elif int(row.delta) < 0:
			want_down += 1
	assert_eq(ups, want_up, "上箭头个数 = 变好的项")
	assert_eq(downs, want_down, "下箭头个数 = 变差的项")


func test_worn_equip_shows_unequip_and_swap() -> void:
	var scene := await _boot()
	var bag := scene.get("_bag_page") as BagPage
	var worn := _pick(bag, func(it: Dictionary) -> bool: return it.category == "equip" and it.equipped)
	bag.call("_on_equip_slot", str(worn.slot_id))
	await get_tree().process_frame
	var popup := scene.get("_item_popup") as ItemDetailPopup
	assert_true(popup.visible)
	assert_eq(str(popup.view.type), "equip_worn")
	assert_not_null(popup.button_named("卸 下"))
	assert_not_null(popup.button_named("换一件"))
	assert_true(popup.button_named("分 解").disabled, "已穿戴的不能分解")
	assert_has(popup.texts(), "已穿戴")


func test_material_popup_shows_count_description_and_ok() -> void:
	var scene := await _boot()
	var bag := scene.get("_bag_page") as BagPage
	var stone := _pick(bag, func(it: Dictionary) -> bool: return it.category == "material" and str(it.name).begins_with("突破石"))
	assert_false(stone.is_empty())
	var popup := await _open(scene, stone)
	assert_eq(str(popup.view.type), "material")
	assert_eq(str(popup.view.title), "物品详情")
	assert_has(popup.texts(), "持有 %d" % int(stone.qty))
	assert_not_null(popup.button_named("确 定"))
	assert_null(popup.button_named("穿 戴"))
	var desc := str(popup.view.desc)
	assert_false(desc.is_empty(), "突破石有说明")
	assert_false(desc.contains("起始值"), "说明里不再有「（起始值，可在后台修改）」")
	popup.button_named("确 定").pressed.emit()
	assert_false(popup.visible)


func test_skill_book_popup_shows_description_and_use() -> void:
	var scene := await _boot()
	await _add_book(scene, "青元诀")
	var bag := scene.get("_bag_page") as BagPage
	var book := _pick(bag, func(it: Dictionary) -> bool: return it.kind == "skill_book")
	assert_false(book.is_empty())
	var popup := await _open(scene, book)
	assert_eq(str(popup.view.type), "book")
	assert_true(str(popup.view.desc).begins_with("使用后学会技能「青元诀」"), "技能书说明非空")
	assert_not_null(popup.button_named("使 用"))
	var used: Array = []
	popup.show_view(popup.view, {"use": func(id: String) -> void: used.append(id)})
	popup.button_named("使 用").pressed.emit()
	assert_eq(used, [str(book.id)], "「使 用」走 use 回调")


func test_equip_button_equips_and_updates_bag() -> void:
	var scene := await _boot()
	var bag := scene.get("_bag_page") as BagPage
	var item := _compare_target(bag)
	var slot_id := str(item.slot_id)
	var old_worn := str(EquipModel.worn_in(bag.model, slot_id).id)
	var popup := await _open(scene, item)
	popup.button_named("穿 戴").pressed.emit()
	assert_false(popup.visible, "点穿戴后弹窗关闭")
	for i in 30:
		await get_tree().process_frame
		if str(EquipModel.worn_in(bag.model, slot_id).get("id", "")) == str(item.id):
			break
	assert_eq(str(EquipModel.worn_in(bag.model, slot_id).get("id", "")), str(item.id), "身上换成这件")
	var now := bag.model.find(str(item.id))
	assert_true(bool(now.equipped))
	var old := bag.model.find(old_worn)
	assert_false(bool(old.equipped), "原来那件回到背包")
	var in_grid := false
	for it in bag.model.visible_items("all"):
		if str(it.id) == old_worn:
			in_grid = true
	assert_true(in_grid, "背包格子里出现换下来的那件")


func test_popup_body_scroll_has_scroll_kit_and_no_bar() -> void:
	var scene := await _boot()
	var bag := scene.get("_bag_page") as BagPage
	var popup := await _open(scene, _compare_target(bag))
	var scroll := popup.find_child("BodyScroll", true, false) as ScrollContainer
	assert_not_null(scroll)
	assert_false(scroll.get_v_scroll_bar().visible, "弹窗滚动区也不显示滚动条")
	assert_not_null(ScrollKit.of(scroll), "弹窗内容也是手指拖动 + 惯性")
