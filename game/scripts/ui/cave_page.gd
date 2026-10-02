class_name CavePageController
extends PanelContainer

const TABS := [
	["overview", "总览"],
	["production", "生产"],
	["alchemy", "丹房"],
	["artifact", "器坊"],
	["beasts", "灵兽苑"],
]

var session: CultivationSession
var active_tab := "overview"
var _content: VBoxContainer
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var heading := Label.new()
	heading.text = "洞府"
	heading.add_theme_font_size_override("font_size", MainTheme.SIZE_HERO)
	heading.add_theme_color_override("font_color", Color("dcc076"))
	root.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "安排人手、蕴养丹器，让离线时间沉淀为传承。"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", MainTheme.SIZE_CAPTION)
	root.add_child(subtitle)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 5)
	root.add_child(tabs)
	for tab_data in TABS:
		var button := Button.new()
		button.text = tab_data[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 54
		button.pressed.connect(_select_tab.bind(tab_data[0]))
		tabs.add_child(button)
		_tab_buttons[tab_data[0]] = button
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	_refresh()


func bind_session(value: CultivationSession) -> void:
	session = value
	_refresh()


func refresh() -> void:
	_refresh()


func _select_tab(tab_id: String) -> void:
	active_tab = tab_id
	_refresh()


func _refresh() -> void:
	if _content == null:
		return
	for child in _content.get_children():
		child.queue_free()
	for tab_id in _tab_buttons:
		(_tab_buttons[tab_id] as Button).disabled = tab_id == active_tab
	if session == null or session.state == null:
		_add_label("洞府尚未落定。")
		return
	match active_tab:
		"production":
			_build_production()
		"alchemy":
			_build_recipes("alchemy")
		"artifact":
			_build_recipes("artifact")
		"beasts":
			_build_beasts()
		_:
			_build_overview()


func _build_overview() -> void:
	var progress := session.state.long_term
	var available := LongTermRules.available_labor(
		progress.cave,
		session.long_term_config,
		progress.sect,
		progress.ascension
	)
	_add_section("洞府总览")
	_add_label("人手 %d/%d · 建筑等级 %d · 制作完成 %d" % [
		progress.cave.assigned_labor(),
		available,
		_total_building_levels(),
		progress.craft.completed_jobs,
	])
	_add_label(_resource_summary())
	_add_section("今世与传承")
	_add_label("今世修行 %s · 已飞升 %d 次 · 传承点 %d" % [
		CultivationFormat.duration_hours(progress.run_seconds),
		progress.ascension.ascension_count,
		progress.ascension.legacy_points,
	])
	var ascend := Button.new()
	ascend.text = "条件已齐，软飞升" if session.can_soft_ascend() else "软飞升条件尚未齐备"
	ascend.disabled = not session.can_soft_ascend()
	ascend.custom_minimum_size.y = 64
	ascend.pressed.connect(_soft_ascend)
	_content.add_child(ascend)
	if progress.ascension.ascension_count > 0:
		_add_section("洞天据点")
		for outpost in session.long_term_config.outposts:
			var level := int(progress.ascension.outpost_levels.get(outpost.id, 0))
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = "%s  Lv.%d/%d" % [
				outpost.display_name,
				level,
				outpost.max_level,
			]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var upgrade := Button.new()
			var costs: Dictionary[String, float] = {}
			for resource_id in outpost.costs:
				costs[resource_id] = outpost.costs[resource_id] * float(level + 1)
			upgrade.text = "已满级" if level >= outpost.max_level else "建设"
			upgrade.disabled = (
				level >= outpost.max_level
				or not progress.economy.can_spend(costs)
			)
			upgrade.tooltip_text = _cost_text(costs)
			upgrade.pressed.connect(_upgrade_outpost.bind(outpost.id))
			row.add_child(upgrade)
			_content.add_child(row)
		_add_section("传承终局")
		for ending in session.long_term_config.endings:
			var completed := progress.ascension.completed_ending_ids.has(ending.id)
			var claim := Button.new()
			claim.text = "%s · %s" % [
				ending.display_name,
				"已完成" if completed else "飞升%d/传承%d/据点%d" % [
					ending.ascension_count,
					ending.legacy_points,
					ending.outpost_levels,
				],
			]
			claim.disabled = (
				completed
				or progress.ascension.ascension_count < ending.ascension_count
				or progress.ascension.legacy_points < ending.legacy_points
				or LongTermRules.total_outpost_levels(progress.ascension) < ending.outpost_levels
			)
			claim.pressed.connect(_claim_ending.bind(ending.id))
			_content.add_child(claim)
	if not progress.last_summary.is_empty():
		_add_section("最近结算")
		_add_label("\n".join(progress.last_summary))


func _build_production() -> void:
	var progress := session.state.long_term
	var total := LongTermRules.available_labor(
		progress.cave,
		session.long_term_config,
		progress.sect,
		progress.ascension
	)
	_add_section("生产调度 · 已安排 %d/%d" % [progress.cave.assigned_labor(), total])
	for resource_id in session.long_term_config.cave_rates:
		var row := HBoxContainer.new()
		var name := str(session.long_term_config.resource_names[resource_id])
		var workers := int(progress.cave.labor.get(resource_id, 0))
		var rate := session.long_term_config.cave_rates[resource_id] * float(workers)
		var label := Label.new()
		label.text = "%s  %s  ·  %d 人  ·  %.2f/秒" % [
			name,
			CultivationFormat.amount(progress.economy.amount(resource_id)),
			workers,
			rate,
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var minus := Button.new()
		minus.text = "−"
		minus.disabled = workers <= 0
		minus.pressed.connect(_change_labor.bind(resource_id, workers - 1))
		row.add_child(minus)
		var plus := Button.new()
		plus.text = "+"
		plus.disabled = progress.cave.assigned_labor() >= total
		plus.pressed.connect(_change_labor.bind(resource_id, workers + 1))
		row.add_child(plus)
		_content.add_child(row)
	_add_section("洞府建筑")
	for building in session.long_term_config.buildings:
		var level := progress.cave.building_level(building.id)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s  Lv.%d/%d" % [building.display_name, level, building.max_level]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.text = "已满级" if level >= building.max_level else "升级"
		button.disabled = level >= building.max_level
		button.tooltip_text = _cost_text(
			LongTermRules.building_upgrade_cost(building, level + 1)
		)
		button.pressed.connect(_upgrade_building.bind(building.id))
		row.add_child(button)
		_content.add_child(row)
	_add_section("旧物回收")
	var recycle := Button.new()
	recycle.text = "回收行囊中的全部未锁定材料"
	recycle.custom_minimum_size.y = 58
	recycle.pressed.connect(_recycle_materials)
	_content.add_child(recycle)


func _build_recipes(category: String) -> void:
	var progress := session.state.long_term
	_add_section("制作队列 %d/%d" % [
		progress.craft.queue.size(),
		session.long_term_config.queue_limit,
	])
	if progress.craft.queue.is_empty():
		_add_label("当前没有正在制作的丹器。")
	else:
		for job in progress.craft.queue:
			var recipe := session.long_term_config.recipe_by_id(job.recipe_id)
			_add_label("%s ×%d · 剩余 %s" % [
				recipe.display_name if recipe != null else job.recipe_id,
				job.amount,
				CultivationFormat.duration_hours(int(ceil(job.remaining_seconds))),
			])
	_add_section("可用配方")
	for recipe in session.long_term_config.recipes:
		if recipe.category != category:
			continue
		var unlocked := progress.craft.has_recipe(recipe.id)
		var card := VBoxContainer.new()
		var title := Label.new()
		title.text = "%s%s · %s" % [
			recipe.display_name,
			"" if unlocked else "（门派传承未得）",
			_cost_text(recipe.inputs),
		]
		card.add_child(title)
		var actions := HBoxContainer.new()
		if not unlocked and recipe.research_pity > 0:
			var research := Button.new()
			var attempts := int(progress.craft.research_attempts.get(recipe.id, 0))
			research.text = "研究 %d/%d" % [attempts, recipe.research_pity]
			research.disabled = not progress.economy.can_spend(recipe.research_costs)
			research.tooltip_text = _cost_text(recipe.research_costs)
			research.pressed.connect(_research_recipe.bind(recipe.id))
			actions.add_child(research)
		var make_one := Button.new()
		make_one.text = "制作 1"
		make_one.disabled = (
			not unlocked
			or progress.craft.queue.size() >= session.long_term_config.queue_limit
			or not progress.economy.can_spend(recipe.inputs)
		)
		make_one.pressed.connect(_queue_recipe.bind(recipe.id, 1))
		actions.add_child(make_one)
		var make_five := Button.new()
		make_five.text = "制作 5"
		var five_costs: Dictionary[String, float] = {}
		for resource_id in recipe.inputs:
			five_costs[resource_id] = recipe.inputs[resource_id] * 5.0
		make_five.disabled = (
			not unlocked
			or progress.craft.queue.size() >= session.long_term_config.queue_limit
			or not progress.economy.can_spend(five_costs)
		)
		make_five.pressed.connect(_queue_recipe.bind(recipe.id, 5))
		actions.add_child(make_five)
		var salvage := Button.new()
		salvage.text = "拆解 1"
		salvage.disabled = not progress.economy.can_spend(recipe.outputs)
		salvage.pressed.connect(_decompose.bind(recipe.id))
		actions.add_child(salvage)
		card.add_child(actions)
		_content.add_child(card)


func _build_beasts() -> void:
	var progress := session.state.long_term
	_add_section("灵兽苑")
	for beast in session.long_term_config.beasts:
		var owned := progress.beast.owns(beast.id)
		var level := progress.beast.level_of(beast.id)
		var active := progress.beast.active_id == beast.id
		var title := Label.new()
		title.text = "%s · %s" % [
			beast.display_name,
			("Lv.%d%s" % [level, " · 出战" if active else ""]) if owned else "尚未结缘",
		]
		_content.add_child(title)
		var actions := HBoxContainer.new()
		var claim := Button.new()
		claim.text = "结缘"
		claim.visible = not owned
		claim.disabled = (
			progress.expedition.clear_count(beast.claim_expedition_id)
			< beast.claim_clear_count
		)
		claim.pressed.connect(_claim_beast.bind(beast.id))
		actions.add_child(claim)
		var deploy := Button.new()
		deploy.text = "已出战" if active else "出战"
		deploy.visible = owned
		deploy.disabled = active
		deploy.pressed.connect(_deploy_beast.bind(beast.id))
		actions.add_child(deploy)
		var feed := Button.new()
		feed.text = "喂养"
		feed.visible = owned
		feed.disabled = (
			progress.economy.amount(beast.feed_resource_id) + 0.000001
			< beast.feed_amount
		)
		feed.pressed.connect(_feed_beast.bind(beast.id))
		actions.add_child(feed)
		_content.add_child(actions)


func _change_labor(resource_id: String, amount: int) -> void:
	session.assign_cave_labor(resource_id, amount)
	_refresh()


func _upgrade_building(building_id: String) -> void:
	session.upgrade_cave_building(building_id)
	_refresh()


func _queue_recipe(recipe_id: String, amount: int) -> void:
	session.queue_recipe(recipe_id, amount)
	_refresh()


func _research_recipe(recipe_id: String) -> void:
	session.research_recipe(recipe_id)
	_refresh()


func _decompose(recipe_id: String) -> void:
	session.decompose_recipe(recipe_id)
	_refresh()


func _recycle_materials() -> void:
	session.recycle_old_materials()
	_refresh()


func _claim_beast(beast_id: String) -> void:
	session.claim_beast(beast_id)
	_refresh()


func _deploy_beast(beast_id: String) -> void:
	session.deploy_beast(beast_id)
	_refresh()


func _feed_beast(beast_id: String) -> void:
	session.feed_beast(beast_id)
	_refresh()


func _soft_ascend() -> void:
	session.soft_ascend()
	_refresh()


func _upgrade_outpost(outpost_id: String) -> void:
	session.upgrade_outpost(outpost_id)
	_refresh()


func _claim_ending(ending_id: String) -> void:
	session.claim_ending(ending_id)
	_refresh()


func _total_building_levels() -> int:
	var total := 0
	for level in session.state.long_term.cave.building_levels.values():
		total += int(level)
	return total


func _resource_summary() -> String:
	var parts := PackedStringArray()
	for resource_id in session.long_term_config.resource_names:
		var amount := session.state.long_term.economy.amount(resource_id)
		if amount > 0.0:
			parts.append("%s %s" % [
				session.long_term_config.resource_names[resource_id],
				CultivationFormat.amount(amount),
			])
	return "资源尚待开采。" if parts.is_empty() else " · ".join(parts)


func _cost_text(costs: Dictionary) -> String:
	var parts := PackedStringArray()
	for resource_id in costs:
		parts.append("%s %s" % [
			session.long_term_config.resource_names.get(resource_id, resource_id),
			CultivationFormat.amount(float(costs[resource_id])),
		])
	return "无需材料" if parts.is_empty() else "、".join(parts)


func _add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", MainTheme.SIZE_BODY)
	label.add_theme_color_override("font_color", Color("dcc076"))
	_content.add_child(label)


func _add_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", MainTheme.SIZE_CAPTION)
	_content.add_child(label)
