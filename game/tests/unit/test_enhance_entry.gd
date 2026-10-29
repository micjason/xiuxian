extends GutTest
## 洞府强化入口：只负责挑一件已穿戴、还能强化的装备，并切到背包打开现有物品详情。
## 不新增强化规则；分解仍走背包的 SalvageDialog。


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


func _gear(id: String, slot_id: String, enhance: int, cap: int, equipped: bool, pending: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"category": "equip",
		"equipped": equipped,
		"equipped_slot_id": slot_id if equipped else "",
		"slot_id": slot_id,
		"enhance": enhance,
		"enhance_cap": cap,
		"break_pending": pending,
	}


func _bag(rows: Array) -> BagModel:
	var model := BagModel.new()
	for row in rows:
		model.items.append(row)
	return model


func test_worn_enhance_target_prefers_weapon_then_later_slots() -> void:
	var bag := _bag([
		_gear("loose", "weapon", 0, 15, false),
		_gear("acc", "accessory", 0, 15, true),
		_gear("sword", "weapon", 1, 15, true),
		_gear("helm", "helmet", 0, 15, true),
	])
	assert_eq(EquipModel.worn_enhance_target(bag), "sword", "多件可强化时按部位顺序，武器优先；背包里的不预选")


func test_worn_enhance_target_skips_cap_and_breakthrough_node() -> void:
	var bag := _bag([
		_gear("sword", "weapon", 15, 15, true),
		_gear("helm", "helmet", 5, 15, true, {"level": 5}),
		_gear("robe", "clothes", 2, 15, true),
	])
	assert_eq(EquipModel.worn_enhance_target(bag), "robe")


func test_worn_enhance_target_is_empty_when_nothing_worn_can_enhance() -> void:
	var bag := _bag([
		_gear("loose", "weapon", 0, 15, false),
		{"id": "mat", "category": "material", "equipped": true, "equipped_slot_id": "weapon", "enhance": 0, "enhance_cap": 0, "break_pending": {}},
	])
	assert_eq(EquipModel.worn_enhance_target(bag), "")
	assert_eq(EquipModel.worn_enhance_target(BagModel.new()), "")


func _boot(scenario: String = "ready") -> Node:
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


func test_cave_enhance_entry_opens_bag_toast_and_worn_item_detail() -> void:
	var scene := await _boot("ready")
	var bag := scene.get("_bag_page") as BagPage
	var expected := EquipModel.worn_enhance_target(bag.model)
	assert_false(expected.is_empty(), "演示数据里有已穿戴且还能强化的装备")
	scene.call("_show_page", "cave")
	var button := (scene.get("_cave_page") as CavePage).enhance_entry_button()
	assert_not_null(button, "洞府页有临时强化入口")
	button.pressed.emit()
	await get_tree().process_frame
	assert_eq(scene.get("_page"), "bag")
	assert_true((scene.get("_pages")["bag"] as Control).visible)
	assert_false((scene.get("_pages")["cave"] as Control).visible)
	assert_eq((scene.get("_toast") as Toast).text(), "点一件装备进行强化")
	var popup := scene.get("_item_popup") as ItemDetailPopup
	assert_true(popup.visible, "打开现有物品详情，不新做强化面板")
	assert_eq(str(popup.view.get("id", "")), expected)
	assert_eq(str(popup.view.get("type", "")), "equip_worn")
	var enhance := popup.button_named("强 化")
	assert_not_null(enhance, "强化仍走详情里的现有按钮")
	var before := int((bag.model.find(expected) as Dictionary).get("enhance", 0))
	enhance.pressed.emit()
	for _i in 6:
		await get_tree().process_frame
	assert_string_contains((scene.get("_toast") as Toast).text(), "强化成功")
	assert_gt(int(((scene.get("_bag_page") as BagPage).model.find(expected) as Dictionary).get("enhance", 0)), before, "强化等级由现有接口写回")
	assert_true((scene.get("_item_popup") as ItemDetailPopup).visible, "强化后回到这件装备的详情")


func test_enhance_entry_without_worn_gear_only_switches_to_bag() -> void:
	var scene := await _boot("fresh")
	var bag := scene.get("_bag_page") as BagPage
	assert_eq(EquipModel.worn_enhance_target(bag.model), "")
	scene.call("open_enhance_entry")
	await get_tree().process_frame
	assert_eq(scene.get("_page"), "bag")
	assert_eq((scene.get("_toast") as Toast).text(), "点一件装备进行强化")
	assert_false((scene.get("_item_popup") as ItemDetailPopup).visible)
