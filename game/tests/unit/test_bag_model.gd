extends GutTest
## 行囊数据模型：展示字典、分类、品质、排序、容量、对比、分解规则、批量选择。

var _content := {}
var _state := {}


func before_each() -> void:
	_content = UiMock.content()
	_state = UiMock.state()


func _model(seen: Dictionary = {}) -> BagModel:
	return BagModel.from_state(_state, _content, seen)


func test_capacity_is_20_from_server_state_then_content_then_design_default() -> void:
	assert_eq(_model().capacity, 20)
	_state["bagCapacity"] = 28
	assert_eq(_model().capacity, 28, "服务器给的容量（含扩容）优先")
	_state.erase("bagCapacity")
	_content["globals"]["bagCapacity"] = 24
	assert_eq(_model().capacity, 24)
	_content["globals"] = {}
	assert_eq(_model().capacity, BagModel.DEFAULT_CAPACITY)
	assert_eq(BagModel.DEFAULT_CAPACITY, 20)


func test_equipped_items_do_not_use_bag_slots() -> void:
	var model := _model()
	var worn := 0
	for item in model.items:
		if item.equipped:
			worn += 1
	assert_eq(worn, 5)
	assert_eq(model.used_slots(), model.items.size() - 5)
	assert_false(model.is_full())
	model.capacity = model.used_slots()
	assert_true(model.is_full())


func test_items_are_split_into_the_four_categories() -> void:
	var model := _model()
	assert_eq(model.category_count("equip"), 10)
	assert_eq(model.category_count("material"), 5)
	assert_eq(model.category_count("pill"), 2)
	assert_eq(model.category_count("other"), 1)
	var total := 0
	for category in BagModel.CATEGORIES:
		total += model.category_count(str(category.id))
	assert_eq(total, model.used_slots())


func test_rarity_maps_server_quality_names() -> void:
	assert_eq(BagModel.rarity_of({"quality": "white"}), 0)
	assert_eq(BagModel.rarity_of({"quality": "purple"}), 3)
	assert_eq(BagModel.rarity_of({"quality": "orange"}), 4)
	assert_eq(BagModel.rarity_of({}), 0)
	assert_eq(BagModel.rarity_of({"quality": "nonsense"}), 0)


func test_equipment_power_uses_weights_and_non_equipment_has_none() -> void:
	var model := _model()
	var pendant: Dictionary
	var herb: Dictionary
	for item in model.items:
		if item.slug == "acc_o":
			pendant = item
		if item.slug == "herb":
			herb = item
	# 强化 +4（每级 +6%）后：攻 7、防 9、血 134、速 2 → 7*4.7 + 9*1.6 + 134*0.95 + 2*2.6 = 180
	assert_eq(pendant.power, 180)
	assert_eq(herb.power, 0)
	assert_eq(herb.qty, 36)
	assert_eq(pendant.slot_id, "accessory")


func test_power_weights_can_be_overridden_by_content() -> void:
	_content["globals"]["powerWeights"] = {"attack": 10, "defense": 0, "hp": 0, "speed": 0}
	var model := _model()
	for item in model.items:
		if item.slug == "sword_p":
			# 紫色 +5：基础攻击 30 × (1 + 5 × 6%) = 39，权重 10
			assert_eq(item.power, 390)


func test_sort_by_rarity_and_power_and_name() -> void:
	var model := _model()
	var by_rarity := model.visible_items("equip", "rarity")
	assert_eq(by_rarity[0].slug, "sword_r", "仙品（红）排第一")
	for i in range(1, by_rarity.size()):
		assert_gte(by_rarity[i - 1].rarity, by_rarity[i].rarity)
	var by_power := model.visible_items("equip", "power")
	for i in range(1, by_power.size()):
		assert_gte(by_power[i - 1].power, by_power[i].power)
	var by_name := model.visible_items("equip", "name")
	for i in range(1, by_name.size()):
		assert_lte(by_name[i - 1].name, by_name[i].name)


func test_new_marker_needs_a_seen_set() -> void:
	var model := _model({})
	for item in model.items:
		assert_false(item.is_new, "没有记录时不显示新")
	var seen := {}
	for item in _model().items:
		seen[item.id] = true
	seen.erase(_model().items[6].id)
	var marked := _model(seen)
	assert_true(marked.items[6].is_new)
	assert_false(marked.items[5].is_new)


func test_compare_shows_signed_deltas_and_skips_zero_rows() -> void:
	var model := _model()
	var upgrade: Dictionary
	var worn: Dictionary
	for item in model.items:
		if item.slug == "sword_b":
			upgrade = item
		if item.slug == "sword_g":
			worn = item
	var rows := BagModel.compare(upgrade, worn)
	var by_key := {}
	for row in rows:
		by_key[row.key] = row
	# 对比用强化后的实际数值：青锋剑·良 +3 攻 27 血 81；青锋剑·精 未强化 攻 26 血 78
	assert_eq(by_key["attack"].delta, -1)
	assert_eq(by_key["hp"].delta, -3)
	assert_false(by_key.has("defense"), "两件都是 0 的属性不显示")
	var against_empty := BagModel.compare(upgrade, {})
	assert_eq(against_empty[0].other, 0)


func test_only_unequipped_gear_can_be_decomposed() -> void:
	var model := _model()
	var gear: Dictionary = model.visible_items("equip")[0]
	assert_true(BagModel.can_decompose(gear))
	for item in model.items:
		if item.equipped:
			assert_false(BagModel.can_decompose(item))
		if item.category != "equip":
			assert_false(BagModel.can_decompose(item))


func test_batch_ids_skip_worn_materials_and_unknown() -> void:
	var model := _model()
	var gear := model.visible_items("equip")
	var worn_id := ""
	var material_id := ""
	for item in model.items:
		if item.equipped:
			worn_id = item.id
		elif item.category == "material":
			material_id = item.id
	var picked := model.batch_ids([gear[0].id, gear[1].id, worn_id, material_id, "no-such-id"])
	assert_eq(picked, [gear[0].id, gear[1].id] as Array[String])


func test_enhanced_gear_has_scaled_stats_cap_and_next_cost() -> void:
	var model := _model()
	var enhanced: Dictionary
	for item in model.items:
		if item.slug == "acc_o":
			enhanced = item
	assert_eq(enhanced.enhance, 4)
	assert_eq(enhanced.enhance_cap, 15, "绝品（橙）上限 15")
	assert_eq(enhanced.enhance_cost, model.enhance.cost(4, 4))
	assert_eq(int(enhanced.stats["attack"]), model.enhance.stat(6.0, 4))
	assert_eq(int(enhanced.base_stats["attack"]), 6)
	assert_true(BagModel.can_enhance(enhanced))
	assert_eq(model.enhance_exp, 380)
	for item in model.items:
		if item.category != "equip":
			assert_false(BagModel.can_enhance(item))
			assert_eq(item.enhance_cap, 0)


func test_decompose_exp_includes_refund_of_invested_exp() -> void:
	var model := _model()
	for item in model.items:
		if item.slug == "acc_o":
			var invested := model.enhance.invested(4, 4)
			assert_eq(item.decompose_exp, 480 + int(floor(invested * 0.8)))
		if item.slug == "sword_w":
			assert_eq(item.decompose_exp, 30, "白色未强化：只有基础经验")


func _by_slug(model: BagModel, slug: String) -> Dictionary:
	for item in model.items:
		if item.slug == slug:
			return item
	return {}


func test_gear_on_a_break_node_is_blocked_and_lists_materials_with_counts() -> void:
	var model := _model()
	var purple := _by_slug(model, "sword_p")  # 紫 +5，节点 +5 需要 下品突破石 ×8，行囊里有 6
	assert_eq(purple.enhance, 5)
	assert_true(BagModel.is_blocked_by_node(purple))
	assert_false(BagModel.can_enhance(purple), "卡在节点上先要突破")
	assert_true(BagModel.can_break(purple))
	var pending: Dictionary = purple.break_view.pending
	assert_eq(int(pending.level), 5)
	assert_false(pending.ready, "材料不够")
	assert_eq(pending.materials[0].name, "突破石·下品")
	assert_eq(int(pending.materials[0].need), 8)
	assert_eq(int(pending.materials[0].have), 6)
	var shoes := _by_slug(model, "shoe_b")  # 蓝 +5，节点 +5 需要 ×5，有 6
	assert_true(shoes.break_view.pending.ready)
	assert_eq(model.material_count("enh_stone_low"), 6)


func test_next_node_is_shown_before_reaching_it() -> void:
	var model := _model()
	var orange := _by_slug(model, "acc_o")  # 橙 +4：下一个节点 +5
	assert_false(BagModel.is_blocked_by_node(orange))
	assert_true(BagModel.can_enhance(orange))
	assert_eq(int(orange.break_view.next.level), 5)
	assert_true(orange.break_view.pending.is_empty())


func test_broken_node_no_longer_blocks_and_points_to_the_next() -> void:
	var state := UiMock.state()
	for row in state.items:
		if row.itemSlug == "sword_p":
			row["breakLevel"] = 5
	var model := BagModel.from_state(state, UiMock.content(), {})
	var purple := _by_slug(model, "sword_p")
	assert_false(BagModel.is_blocked_by_node(purple))
	assert_true(BagModel.can_enhance(purple))
	assert_eq(int(purple.break_view.next.level), 10)


func test_red_gear_has_its_own_cap_and_can_be_enhanced() -> void:
	var model := _model()
	var red := _by_slug(model, "sword_r")
	assert_eq(red.rarity, 5)
	assert_eq(red.rarity_name, "仙品")
	assert_eq(red.enhance_cap, 18)
	assert_eq(red.enhance, 2)
	assert_true(BagModel.can_enhance(red))
	assert_eq(red.enhance_cost, model.enhance.cost(5, 2))
	assert_eq(int(red.stats["attack"]), model.enhance.stat(40.0, 2, 5))


func test_decompose_reason_explains_worn_gear_and_batch_skips_it() -> void:
	var model := _model()
	var worn := _by_slug(model, "sword_g")
	assert_true(worn.equipped)
	assert_false(BagModel.can_decompose(worn))
	assert_string_contains(BagModel.decompose_block_reason(worn), "已穿戴的装备不能分解")
	assert_string_contains(BagModel.decompose_block_reason(worn), "先脱下")
	assert_eq(BagModel.decompose_block_reason(_by_slug(model, "herb")), "只有装备可以分解")
	assert_eq(BagModel.decompose_block_reason(_by_slug(model, "sword_w")), "")
	var spare := _by_slug(model, "sword_w")
	assert_eq(model.batch_ids([worn.id, spare.id]), [spare.id] as Array[String], "批量分解跳过已穿戴的")
