extends GutTest
## 装备栏：部位配置、穿戴映射、属性汇总、可替换候选。

var _bag: BagModel


func before_each() -> void:
	_bag = BagModel.from_state(UiMock.state(), UiMock.content())


func test_slot_config_has_six_core_slots_and_two_locked_placeholders() -> void:
	assert_eq(SlotConfig.core().size(), 6)
	assert_eq(SlotConfig.extra().size(), 2)
	for slot in SlotConfig.extra():
		assert_true(slot.locked)
		assert_false(SlotConfig.is_equippable(slot.id))
	var ids := []
	for slot in SlotConfig.all():
		assert_false(ids.has(slot.id), "部位 id 不能重复")
		ids.append(slot.id)


func test_server_has_six_slots_including_gloves() -> void:
	assert_eq(SlotConfig.server_supported_count(), 6)
	assert_true(SlotConfig.is_equippable("gloves"))
	assert_true(SlotConfig.is_equippable("weapon"))
	assert_eq(SlotConfig.id_from_server("helmet"), "helmet")
	assert_eq(SlotConfig.id_from_server("clothes"), "clothes")
	assert_eq(SlotConfig.id_from_server("gloves"), "gloves")
	assert_eq(SlotConfig.id_from_server(""), "")
	assert_eq(SlotConfig.id_from_server("tail"), "")


func test_every_server_slot_maps_to_a_ui_slot() -> void:
	for server_key in ["weapon", "helmet", "clothes", "gloves", "shoes", "accessory"]:
		assert_ne(SlotConfig.id_from_server(server_key), "", server_key)


func test_slots_of_contains_all_configured_slots() -> void:
	var slots := EquipModel.slots_of(_bag)
	assert_eq(slots.size(), 8)
	assert_false((slots["weapon"] as Dictionary).is_empty())
	assert_true((slots["gloves"] as Dictionary).is_empty())
	assert_true((slots["artifact"] as Dictionary).is_empty())
	assert_eq(EquipModel.worn_count(slots), 5)


func test_stat_totals_and_gear_power_add_up() -> void:
	var slots := EquipModel.slots_of(_bag)
	var totals := EquipModel.stat_totals(slots)
	# 青锋剑·良 基础攻击 23、强化 +3（每级 +6%）→ 27.14；道袍 基础防御 16、强化 +2 → 17.92；
	# 踏云靴·精 基础防御 5、速度 5，强化 +5（×1.3）→ 各 6.5；头冠、佩没强化。合计保留小数，显示时才取整
	assert_almost_eq(float(totals["attack"]), 27.14, 0.001)
	assert_almost_eq(float(totals["defense"]), 4 + 17.92 + 6.5 + 4, 0.001)
	assert_almost_eq(float(totals["speed"]), 6.5, 0.001)
	assert_eq(BagModel.shown(float(totals["attack"])), 27)
	var power := 0
	for slot_id in slots:
		var item: Dictionary = slots[slot_id]
		if not item.is_empty():
			power += item.power
	assert_eq(EquipModel.gear_power(slots), power)
	assert_gt(power, 0)


func test_candidates_are_unworn_same_slot_and_sorted_by_power() -> void:
	var candidates := EquipModel.candidates_for(_bag, "weapon")
	assert_eq(candidates.size(), 4)
	for item in candidates:
		assert_eq(item.slot_id, "weapon")
		assert_false(item.equipped)
	for i in range(1, candidates.size()):
		assert_gte(candidates[i - 1].power, candidates[i].power)
	assert_eq(EquipModel.candidates_for(_bag, "gloves").size(), 1)
	assert_eq(EquipModel.candidates_for(_bag, "pet").size(), 0)


func test_mock_equip_swaps_the_worn_item_in_that_slot() -> void:
	var state := UiMock.state()
	var content := UiMock.content()
	var bag := BagModel.from_state(state, content)
	var candidate := EquipModel.candidates_for(bag, "weapon")[0]
	var before_power := int(state.power)
	var result := UiMock.handle("/api/v1/me/items/%s/equip" % candidate.id, {}, state, content)
	assert_eq(result.code, 200)
	var after := BagModel.from_state(result.state, content)
	assert_eq(EquipModel.worn_in(after, "weapon").id, candidate.id)
	assert_eq(EquipModel.worn_count(EquipModel.slots_of(after)), 5, "换装后仍是 5 件")
	assert_gt(int(result.state.power), before_power)
	var gone := UiMock.handle("/api/v1/me/items/%s/unequip" % candidate.id, {}, result.state, content)
	assert_true(EquipModel.worn_in(BagModel.from_state(gone.state, content), "weapon").is_empty())


func test_enhancement_scales_worn_stats_and_power() -> void:
	var weapon := EquipModel.worn_in(_bag, "weapon")
	assert_eq(weapon.enhance, 3)
	assert_eq(int(weapon.base_stats["attack"]), 23)
	assert_eq(int(weapon.stats["attack"]), 27)
	var plain := BagModel.normalize({"id": "x", "itemSlug": "sword_g", "enhanceLevel": 0}, _content_def("sword_g"), _bag.weights, _bag.enhance)
	assert_gt(weapon.power, plain.power, "同一件装备强化后战力更高")


func _content_def(slug: String) -> Dictionary:
	for def in UiMock.content().items:
		if def.slug == slug:
			return def
	return {}
