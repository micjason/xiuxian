extends GutTest
## 强化规则的客户端镜像：公式、上限、分解返还、规则缺失时不给默认数字。

var _rules: EnhanceModel


func before_each() -> void:
	_rules = EnhanceModel.from_content(UiMock.content())


func test_rules_come_from_content_and_missing_rules_mean_unsupported() -> void:
	assert_true(_rules.is_ready())
	var empty := EnhanceModel.from_content({"globals": {}})
	assert_false(empty.is_ready())
	for rarity in 5:
		assert_false(empty.supports(rarity), "没有规则就是不支持，不用默认数字")
		assert_eq(empty.cap(rarity), 0)
		assert_eq(empty.decompose_exp(rarity, 3), 0)
	assert_false(EnhanceModel.from_content({}).is_ready())


func test_level_cap_grows_with_rarity_and_unconfigured_quality_is_unsupported() -> void:
	var previous := 0
	for rarity in 5:
		assert_true(_rules.supports(rarity))
		assert_gt(_rules.cap(rarity), previous, "品质越高上限越高")
		previous = _rules.cap(rarity)
	assert_eq(_rules.cap(0), 5)
	assert_eq(_rules.cap(4), 15)
	var without_orange := UiMock.content()
	(without_orange["globals"]["enhance"]["qualities"] as Dictionary).erase("orange")
	assert_false(EnhanceModel.from_content(without_orange).supports(4), "配置里没有这个品质的规则就不能强化，不用默认数字")


func test_cost_follows_the_formula() -> void:
	assert_eq(_rules.cost(0, 0), 60)
	assert_eq(_rules.cost(0, 1), 75)
	assert_eq(_rules.cost(0, 2), int(round(60.0 * 1.25 * 1.25)))
	assert_eq(_rules.cost(4, 0), int(round(60.0 * 1.6)))
	assert_gt(_rules.cost(2, 5), _rules.cost(2, 4))
	assert_gt(_rules.cost(3, 3), _rules.cost(2, 3), "同级时品质越高越贵")


func test_stat_scales_linearly_by_level() -> void:
	assert_almost_eq(_rules.stat(20.0, 0), 20.0, 0.001)
	assert_almost_eq(_rules.stat(20.0, 5), 26.0, 0.001)
	assert_almost_eq(_rules.stat(0.0, 9), 0.0, 0.001)
	assert_almost_eq(_rules.stat(14.45, 3), 17.05, 0.001, "保留 2 位小数，不取整")


func test_invested_and_decompose_refund() -> void:
	assert_eq(_rules.invested(0, 0), 0)
	assert_eq(_rules.invested(0, 2), _rules.cost(0, 0) + _rules.cost(0, 1))
	assert_eq(_rules.decompose_exp(0, 0), 30)
	assert_eq(_rules.decompose_exp(0, 2), 30 + int(floor(_rules.invested(0, 2) * 0.8)))
	assert_lt(_rules.decompose_exp(0, 3) - 30, _rules.invested(0, 3), "分解永远拿不回全部投入")


func test_levels_affordable_stops_at_pool_and_cap() -> void:
	assert_eq(_rules.levels_affordable(0, 0, 0), 0)
	assert_eq(_rules.levels_affordable(0, 0, 60), 1)
	assert_eq(_rules.levels_affordable(0, 0, 134), 1)
	assert_eq(_rules.levels_affordable(0, 0, 135), 2)
	assert_eq(_rules.levels_affordable(0, 0, 100000), 5, "不超过品质上限")
	assert_eq(_rules.levels_affordable(0, 5, 100000), 5)


func test_orange_is_the_top_quality_and_uses_its_own_configured_rules() -> void:
	# 批次②：品质 5 档，红（仙品）已去掉；超出范围的下标按最高档（橙）
	assert_true(_rules.supports(4))
	assert_eq(_rules.cap(4), 15)
	assert_eq(_rules.cost(4, 0), int(round(60.0 * 1.6)))
	assert_eq(_rules.decompose_exp(4, 0), 480)
	assert_eq(_rules.cap(5), _rules.cap(4), "没有第 6 档")


func test_per_quality_growth_overrides_the_general_values() -> void:
	var content := UiMock.content()
	var orange: Dictionary = content["globals"]["enhance"]["qualities"]["orange"]
	orange["expGrowth"] = 2.0
	orange["statGrowthBp"] = 1000
	var rules := EnhanceModel.from_content(content)
	assert_eq(rules.cost(4, 3), int(round(60.0 * pow(2.0, 3) * 1.6)))
	assert_almost_eq(rules.stat(100.0, 4, 4), 140.0, 0.001)
	assert_eq(rules.cost(0, 3), int(round(60.0 * pow(1.25, 3))), "没覆盖的品质仍用通用值")
	assert_almost_eq(rules.stat(100.0, 4, 0), 124.0, 0.001)
	assert_almost_eq(rules.stat(100.0, 4), 124.0, 0.001, "不传品质时用通用每级加成")


func test_every_number_follows_the_content_not_the_code() -> void:
	var content := UiMock.content()
	var enhance: Dictionary = content["globals"]["enhance"]
	enhance["expBase"] = 10
	enhance["expGrowth"] = 1.0
	enhance["statGrowthBp"] = 2500
	enhance["refundBp"] = 5000
	(enhance["qualities"]["white"] as Dictionary)["cap"] = 2
	(enhance["qualities"]["white"] as Dictionary)["breakthroughs"] = []
	var rules := EnhanceModel.from_content(content)
	assert_eq(rules.cap(0), 2)
	assert_eq(rules.cost(0, 0), 10)
	assert_eq(rules.cost(0, 1), 10)
	assert_almost_eq(rules.stat(100.0, 2, 0), 150.0, 0.001)
	assert_eq(rules.decompose_exp(0, 2), 30 + 10)
	assert_eq(rules.levels_affordable(0, 0, 1000), 2, "上限按配置")


func test_break_nodes_come_from_content_sorted_and_below_cap() -> void:
	var nodes := _rules.nodes(4)
	assert_eq(nodes.size(), 2)
	assert_eq(int(nodes[0].level), 5)
	assert_eq(int(nodes[1].level), 10)
	assert_eq(nodes[0].materials[0].itemSlug, "enh_stone_low")
	assert_eq(int(nodes[0].materials[0].count), 10)
	assert_eq(_rules.nodes(0).size(), 0, "白色没有突破节点")
	assert_eq(_rules.nodes(3).size(), 2)


func test_pending_node_only_at_the_exact_unbroken_level() -> void:
	assert_true(_rules.pending_node(4, 4, 0).is_empty())
	assert_eq(int(_rules.pending_node(4, 5, 0).level), 5)
	assert_true(_rules.pending_node(4, 5, 5).is_empty(), "已突破就不再卡")
	assert_true(_rules.pending_node(4, 8, 0).is_empty(), "等级已经超过节点的老装备不受影响")
	assert_eq(int(_rules.pending_node(4, 10, 5).level), 10)
	assert_true(_rules.pending_node(0, 5, 0).is_empty(), "节点到了上限就不用突破")
	assert_eq(int(_rules.next_node(4, 6, 5).level), 10)
	assert_true(_rules.next_node(4, 11, 10).is_empty())
	assert_true(EnhanceModel.new().pending_node(4, 5, 0).is_empty(), "没有规则就没有节点")


func test_levels_affordable_stops_at_a_break_node() -> void:
	assert_eq(_rules.levels_affordable(4, 0, 1000000, 0), 5, "橙色第一个节点在 +5")
	assert_eq(_rules.levels_affordable(4, 5, 1000000, 0), 5, "卡在节点上，经验再多也不能升")
	assert_eq(_rules.levels_affordable(4, 5, 1000000, 5), 10, "突破后升到下一个节点")
	assert_eq(_rules.levels_affordable(4, 10, 1000000, 10), 15, "最后一个节点之后升到上限")
