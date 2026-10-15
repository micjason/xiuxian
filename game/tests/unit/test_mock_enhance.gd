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
	assert_eq(result.enhanced.spentExp, cost)
	assert_eq(int(result.state.enhanceExp), 380 - cost)


func test_enhance_to_max_stops_when_exp_runs_out() -> void:
	var id := _id_of("sword_g")
	var result := _post("/api/v1/me/items/%s/enhance" % id, {"toMax": true})
	assert_eq(result.code, 200)
	assert_gt(int(result.enhanced.toLevel), 4)
	assert_lte(int(result.enhanced.toLevel), 8, "绿色上限 8")
	assert_gte(int(result.state.enhanceExp), 0)


func test_enhance_refuses_without_exp_or_at_cap() -> void:
	_state["enhanceExp"] = 0
	var broke := _post("/api/v1/me/items/%s/enhance" % _id_of("sword_g"))
	assert_eq(broke.code, 400)
	assert_string_contains(str(broke.error.message), "不足")
	_state["enhanceExp"] = 100000
	for row in _state.items:
		if row.itemSlug == "acc_o":
			row["enhanceLevel"] = 15
	var capped := _post("/api/v1/me/items/%s/enhance" % _id_of("acc_o"))
	assert_eq(capped.code, 400, "橙色上限 15，满级不能再强化")
	assert_string_contains(str(capped.error.message), "上限")


func test_decompose_gives_enhance_exp_and_refuses_worn_gear() -> void:
	var rules := EnhanceModel.from_content(_content)
	var id := _id_of("acc_o")
	var expected := rules.decompose_exp(4, 4)
	var result := _post("/api/v1/me/items/%s/decompose" % id)
	assert_eq(result.code, 200)
	assert_eq(int(result.gainedEnhanceExp), expected)
	assert_eq(int(result.state.enhanceExp), 380 + expected)
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
	_state["enhanceExp"] = 1000000
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
