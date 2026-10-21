extends GutTest
## 演示模式的强化/分解处理与服务器同口径；强化红点和分解提示依赖它。

var _state: Dictionary
var _content: Dictionary


func before_each() -> void:
	_state = UiMock.state()
	_content = UiMock.content()


func _id_of(slug: String) -> String:
	for row in _state.items:
		if row.itemSlug == slug:
			return str(row.id)
	return ""


## 第五批：强化花的是行囊里的「炼器精粹」堆叠（演示数据 1286）。
func _set_essence(count: int) -> void:
	for row in _state.items:
		if row.itemSlug == "refine_essence":
			row["quantity"] = count


func _post(path: String, body: Dictionary = {}) -> Dictionary:
	return UiMock.handle(path, body, _state, _content)


func test_enhance_spends_exp_and_raises_level() -> void:
	var id := _id_of("sword_g")
	var rules := EnhanceModel.from_content(_content)
	var cost := rules.cost(1, 3)
	var result := _post("/api/v1/me/items/%s/enhance" % id, {"toMax": false})
	assert_eq(result.code, 200)
	assert_eq(result.enhanced.fromLevel, 3)
	assert_eq(result.enhanced.toLevel, 4)
	assert_eq(int(result.enhanced.spentEssence), cost)
	assert_eq(int(result.enhanced.spentExp), 0)
	assert_eq(int(result.state.essence.count), 1286 - cost)
	assert_eq(cost, int(round(40 * pow(1.25, 3) * 1.1)), "精粹消耗 = 基础 40 × 1.25^等级 × 品质倍数")


func test_enhance_to_max_stops_when_exp_runs_out() -> void:
	var id := _id_of("sword_g")
	var result := _post("/api/v1/me/items/%s/enhance" % id, {"toMax": true})
	assert_eq(result.code, 200)
	assert_gt(int(result.enhanced.toLevel), 4)
	assert_lte(int(result.enhanced.toLevel), 8, "绿色上限 8")
	assert_gte(int(result.state.essence.count), 0)


func test_enhance_refuses_without_exp_or_at_cap() -> void:
	_set_essence(0)
	var broke := _post("/api/v1/me/items/%s/enhance" % _id_of("sword_g"))
	assert_eq(broke.code, 409)
	assert_eq(str(broke.error.code), "ESSENCE_SHORT")
	assert_eq(str(broke.error.message), "炼器精粹不足，分解装备可获得")
	_set_essence(100000)
	for row in _state.items:
		if row.itemSlug == "acc_o":
			row["enhanceLevel"] = 15
	var capped := _post("/api/v1/me/items/%s/enhance" % _id_of("acc_o"))
	assert_eq(capped.code, 400, "橙色上限 15，满级不能再强化")
	assert_string_contains(str(capped.error.message), "上限")


func test_decompose_gives_essence_and_refuses_worn_gear() -> void:
	var id := _id_of("acc_o")
	var expected := 1000 + 4 * 40  # 橙 1000 + 强化 +4 × 每级返还 40
	var result := _post("/api/v1/me/items/decompose", {"itemIds": [id]})
	assert_eq(result.code, 200)
	assert_eq(int(result.gainedEssence), expected)
	assert_eq(int(result.state.essence.count), 1286 + expected)
	var batch := _post("/api/v1/me/items/decompose", {"itemIds": [_id_of("sword_w"), _id_of("helm_g")]})
	assert_eq(int(batch.gainedEssence), 20 + 60, "白 20 + 绿 60")
	var mixed := _post("/api/v1/me/items/decompose", {"itemIds": [_id_of("sword_b"), _id_of("sword_g")]})
	assert_eq(mixed.code, 409, "有一件穿着就整单拒绝")
	assert_ne(_id_of("sword_b"), "", "整单拒绝时什么都不分解")
	var worn := _post("/api/v1/me/items/%s/decompose" % _id_of("sword_g"))
	assert_eq(worn.code, 409)
	assert_eq(worn.error.code, "EQUIPPED_CANNOT_DECOMPOSE")
	assert_string_contains(str(worn.error.message), "不能分解")


func _stack(slug: String) -> int:
	var total := 0
	for row in _state.items:
		if row.itemSlug == slug and row.isStack:
			total += int(row.quantity)
	return total


func test_gear_on_a_node_must_break_through_before_enhancing_more() -> void:
	_set_essence(1000000)
	var id := _id_of("sword_p")  # 紫 +5，节点 +5 需要 下品突破石 ×8，有 6
	var blocked := _post("/api/v1/me/items/%s/enhance" % id, {"toMax": true})
	assert_eq(blocked.code, 409)
	assert_eq(blocked.error.code, "BREAKTHROUGH_REQUIRED")
	var short := _post("/api/v1/me/items/%s/breakthrough" % id)
	assert_eq(short.code, 409)
	assert_eq(short.error.code, "BREAKTHROUGH_MATERIAL_SHORT")
	assert_string_contains(str(short.error.message), "还差 2")
	assert_eq(_stack("enh_stone_low"), 6, "材料不够时什么都不扣")
	# 凑够 8 个
	for row in _state.items:
		if row.itemSlug == "enh_stone_low":
			row["quantity"] = 8
	var ok := _post("/api/v1/me/items/%s/breakthrough" % id)
	assert_eq(ok.code, 200)
	assert_eq(int(ok.broken.level), 5)
	assert_eq(_stack("enh_stone_low"), 0, "刚好用完")
	var again := _post("/api/v1/me/items/%s/breakthrough" % id)
	assert_eq(again.code, 400, "已经突破，不在节点上了")
	var go := _post("/api/v1/me/items/%s/enhance" % id, {"toMax": true})
	assert_eq(go.code, 200)
	assert_eq(int(go.enhanced.fromLevel), 5)
	assert_eq(int(go.enhanced.toLevel), 10, "一键强化停在下一个节点 +10")
	assert_eq(int(go.enhanced.blockedByBreakthrough), 10)


func test_break_through_takes_materials_from_the_bag_and_keeps_no_fail() -> void:
	var id := _id_of("shoe_b")  # 蓝 +5，需要 ×5，有 6
	var ok := _post("/api/v1/me/items/%s/breakthrough" % id)
	assert_eq(ok.code, 200)
	assert_eq(_stack("enh_stone_low"), 1)
	var model := BagModel.from_state(ok.state, _content, {})
	for item in model.items:
		if item.slug == "shoe_b":
			assert_eq(item.break_level, 5)
			assert_false(BagModel.is_blocked_by_node(item))


func test_breakthrough_refuses_gear_that_is_not_on_a_node() -> void:
	var result := _post("/api/v1/me/items/%s/breakthrough" % _id_of("acc_o"))
	assert_eq(result.code, 400)
	assert_string_contains(str(result.error.message), "不在突破节点")
