extends Control

const PAGE_CULTIVATE := "cultivate"
const PAGE_ADVENTURE := "adventure"
const PAGE_BAG := "bag"
const PAGE_SKILL := "skill"
const PAGE_SETTINGS := "settings"

@onready var realm_label: Label = %RealmLabel
@onready var realm_path: Label = %RealmPath
@onready var cultivation_label: Label = %CultivationLabel
@onready var rate_label: Label = %RateLabel
@onready var next_cost_label: Label = %NextCostLabel
@onready var next_realm_label: Label = %NextRealmLabel
@onready var cultivation_progress: ProgressBar = %CultivationProgress
@onready var breakthrough_button: Button = %BreakthroughButton
@onready var breakthrough_banner: Label = %BreakthroughBanner
@onready var journal_label: Label = %JournalLabel
@onready var offline_label: Label = %OfflineLabel
@onready var status_label: Label = %StatusLabel
@onready var progress_hint: Label = %ProgressHint
@onready var cultivation_card: PanelContainer = %CultivationCard
@onready var adventure_page: PanelContainer = %AdventurePage
@onready var cave_page: Control = %CavePage
@onready var bag_page: PanelContainer = %BagPage
@onready var skill_page: PanelContainer = %SkillPage
@onready var settings_page: PanelContainer = %SettingsPage
@onready var power_label: Label = %PowerLabel
@onready var stage_label: Label = %StageLabel
@onready var monster_label: Label = %MonsterLabel
@onready var layer_row: Control = %LayerRow
@onready var sight_label: Label = %SightLabel
@onready var challenge_button: Button = %ChallengeButton
@onready var stage_hint: Label = %StageHint
@onready var loot_summary_label: Label = %LootSummaryLabel
@onready var battle_log_label: Label = %BattleLogLabel
@onready var equip_summary: Label = %EquipSummary
@onready var bag_count_label: Label = %BagCountLabel
@onready var bag_list: GridContainer = %BagList
@onready var learned_label: Label = %LearnedLabel
@onready var skill_list: VBoxContainer = %SkillList
@onready var expedition_panel: Control = %ExpeditionPanel
@onready var sect_panel: Control = %SectPanel
@onready var tab_cave: Button = %TabCave
@onready var tab_cultivate: Button = %TabCultivate
@onready var tab_adventure: Button = %TabAdventure
@onready var tab_bag: Button = %TabBag
@onready var tab_skill: Button = %TabSkill
@onready var export_button: Button = %ExportButton
@onready var export_label: Label = %ExportLabel
@onready var chrome_power: Label = %ChromePower
@onready var stage_list: VBoxContainer = %StageList
@onready var version_label: Label = %VersionLabel
@onready var flash: ColorRect = %Flash

var _state: Dictionary = {}
var _content: Dictionary = {}
var _login: PlayerLogin
var _timer: Timer
var _selected_stage := ""
var _busy := false
var _page := PAGE_CULTIVATE
var _bag_hint: Label
var _skill_hint: Label
var _combat_label: Label
var _cooldown_label: Label


func _ready() -> void:
	theme = MainTheme.make()
	_prepare_screen()
	breakthrough_button.pressed.connect(_on_breakthrough)
	challenge_button.pressed.connect(_on_challenge)
	tab_cultivate.pressed.connect(func() -> void: _show_page(PAGE_CULTIVATE))
	tab_adventure.pressed.connect(func() -> void: _show_page(PAGE_ADVENTURE))
	tab_bag.pressed.connect(func() -> void: _show_page(PAGE_BAG))
	tab_skill.pressed.connect(func() -> void: _show_page(PAGE_SKILL))
	_show_page(PAGE_CULTIVATE)
	_login = PlayerLogin.new()
	_login.logged_in.connect(_on_logged_in)
	add_child(_login)
	_timer = Timer.new()
	_timer.wait_time = 3.0
	_timer.timeout.connect(_refresh_state)
	add_child(_timer)
	if PlayerApi.token().is_empty():
		_login.show()
		_set_status("请先登录。")
	else:
		_login.hide()
		_timer.start()
		_refresh_state()


func _prepare_screen() -> void:
	flash.visible = false
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow := get_node_or_null("TopGlow") as CanvasItem
	if glow:
		glow.visible = false
	var background := get_node_or_null("Background") as Control
	if background:
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(%JournalCard as CanvasItem).visible = false
	(%UpdateCard as CanvasItem).visible = false
	(%SettingsButton as CanvasItem).visible = false
	(%Chrome as CanvasItem).visible = false
	chrome_power.reparent(self)
	chrome_power.visible = true
	chrome_power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome_power.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	chrome_power.offset_left = -520.0
	chrome_power.offset_top = 28.0
	chrome_power.offset_right = -32.0
	chrome_power.offset_bottom = 108.0
	chrome_power.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chrome_power.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_label_size(chrome_power, 48)
	var battle_log := battle_log_label.get_parent() as CanvasItem
	if battle_log:
		battle_log.visible = false
	var margin := $Margin as Control
	margin.offset_top = 48.0
	var realm_stage := realm_label.get_parent() as Control
	realm_stage.visible = true
	realm_stage.custom_minimum_size = Vector2(0, 180)
	_set_label_size(realm_label, 80)
	_set_label_size(realm_path, 40)
	_set_label_size(cultivation_label, 72)
	_ensure_combat_label()
	_set_label_size(progress_hint, 40)
	_set_label_size(rate_label, 44)
	_set_label_size(next_cost_label, 44)
	_set_label_size(next_realm_label, 44)
	_set_label_size(breakthrough_banner, 44)
	cultivation_progress.custom_minimum_size = Vector2(0, 36)
	breakthrough_button.custom_minimum_size = Vector2(0, 150)
	breakthrough_button.add_theme_font_size_override("font_size", 52)
	breakthrough_button.mouse_filter = Control.MOUSE_FILTER_STOP
	breakthrough_button.disabled = false
	for tab in [tab_cultivate, tab_adventure, tab_bag, tab_skill]:
		tab.custom_minimum_size = Vector2(0, 150)
		tab.add_theme_font_size_override("font_size", 40)
	export_button.visible = false
	layer_row.visible = false
	sight_label.visible = false
	power_label.visible = true
	_set_label_size(power_label, 40)
	power_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	expedition_panel.visible = false
	sect_panel.visible = false
	tab_cave.visible = false
	cave_page.visible = false
	offline_label.visible = false
	_show_title(adventure_page, "AdventureTitle")
	_show_title(bag_page, "BagTitle")
	_show_title(skill_page, "SkillTitle")
	_set_label_size(stage_label, 48)
	_set_label_size(monster_label, 40)
	_set_label_size(stage_hint, 36)
	_set_label_size(loot_summary_label, 36)
	monster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	challenge_button.custom_minimum_size = Vector2(0, 140)
	challenge_button.add_theme_font_size_override("font_size", 48)
	_cooldown_label = Label.new()
	_set_label_size(_cooldown_label, 36)
	challenge_button.get_parent().add_child(_cooldown_label)
	challenge_button.get_parent().move_child(_cooldown_label, challenge_button.get_index())
	_set_label_size(bag_count_label, 44)
	_set_label_size(equip_summary, 36)
	equip_summary.visible = false
	_set_label_size(learned_label, 40)
	bag_list.columns = 1
	_hide("%DollBoard")
	_hide("%BagTabs")
	_hide("%SkillTabs")
	_hide("%SkillSlotRow")
	_bag_hint = _make_hint()
	bag_count_label.get_parent().add_child(_bag_hint)
	_skill_hint = _make_hint()
	learned_label.get_parent().add_child(_skill_hint)
	for node in cultivation_card.find_children("*", "Label", true, false):
		var label := node as Label
		if label == realm_label or label == cultivation_label or label == rate_label or label == next_cost_label or label == next_realm_label or label == progress_hint or label == realm_path or label == breakthrough_banner:
			continue
		_set_label_size(label, 32)


func _ensure_combat_label() -> void:
	if _combat_label != null:
		return
	_combat_label = Label.new()
	_combat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_set_label_size(_combat_label, 40)
	_combat_label.add_theme_color_override("font_color", Color(0.86, 0.74, 0.44))
	var parent := cultivation_label.get_parent()
	parent.add_child(_combat_label)
	parent.move_child(_combat_label, cultivation_label.get_index() + 1)


func _power_text() -> String:
	return "战力 %d    攻击 %s  防御 %s  气血 %s  速度 %s" % [
		int(_state.get("power", 0)),
		CultivationFormat.amount(float(_state.get("attack", 0))),
		CultivationFormat.amount(float(_state.get("defense", 0))),
		CultivationFormat.amount(float(_state.get("hp", 0))),
		CultivationFormat.amount(float(_state.get("speed", 0))),
	]


func _set_label_size(label: Label, size: int) -> void:
	label.add_theme_font_size_override("font_size", size)


func _show_title(page: Node, node_name: String) -> void:
	var title := page.find_child(node_name, true, false) as Label
	if title == null:
		return
	title.visible = true
	_set_label_size(title, 56)


func _hide(path: String) -> void:
	var node := get_node_or_null(path) as CanvasItem
	if node:
		node.visible = false


func _make_hint() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(0.86, 0.74, 0.44))
	label.visible = false
	return label


func _style_choice(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 40)
	button.custom_minimum_size = Vector2(0, 110)


func _show_page(page: String) -> void:
	_page = page
	cultivation_card.visible = page == PAGE_CULTIVATE
	adventure_page.visible = page == PAGE_ADVENTURE
	bag_page.visible = page == PAGE_BAG
	skill_page.visible = page == PAGE_SKILL
	settings_page.visible = page == PAGE_SETTINGS


func _on_logged_in() -> void:
	_login.hide()
	_set_status("")
	_timer.start()
	_refresh_state()


func _refresh_state() -> void:
	if PlayerApi.token().is_empty() or _busy:
		return
	if _content.is_empty():
		var content := await PlayerApi.fetch_content()
		if int(content.get("code", 0)) == 200:
			_content = content
		else:
			_set_status("后台还没有发布内容，暂时不能修炼。")
			return
	var state := await PlayerApi.fetch_state()
	if int(state.get("code", 0)) != 200:
		_set_status(PlayerApi.error_message(state))
		return
	_state = state
	_set_status("")
	_render()


func _render() -> void:
	var breakthrough: Dictionary = _state.get("breakthrough", {})
	var rate: Dictionary = _state.get("cultivationRate", {})
	var cultivation := float(_state.get("cultivation", 0))
	var cost := float(breakthrough.get("cost", 0))
	var next_slug := str(breakthrough.get("nextSlug", ""))
	realm_label.text = str(_state.get("realmName", ""))
	realm_path.text = "成功率 %d%%" % int(round(float(breakthrough.get("rateBp", 0)) / 100.0))
	cultivation_label.text = "修为  %s" % CultivationFormat.amount(cultivation)
	var gain := float(rate.get("gainPerTick", 0))
	rate_label.text = "尚未设置" if gain <= 0 else CultivationFormat.rate(gain)
	var power_text := _power_text()
	_combat_label.text = power_text
	power_label.text = power_text
	chrome_power.text = "战力 %d" % int(_state.get("power", 0))
	var cooldown = _state.get("challengeCooldownSeconds", null)
	if _cooldown_label:
		_cooldown_label.text = "" if cooldown == null else "挑战冷却 %s 秒" % str(cooldown)
	if gain <= 0:
		next_cost_label.text = "—"
		next_realm_label.text = _realm_name(next_slug) if not next_slug.is_empty() else "—"
		progress_hint.text = "后台还没设置多少秒获得多少修为，现在得不到修为。"
		breakthrough_button.disabled = true
		breakthrough_button.text = "突破境界"
		cultivation_progress.value = 0.0
	elif next_slug.is_empty():
		next_cost_label.text = "—"
		next_realm_label.text = "已至顶峰"
		progress_hint.text = "已至当前最高境界"
		breakthrough_button.disabled = true
		breakthrough_button.text = "已圆满"
		cultivation_progress.value = 100.0
	else:
		next_cost_label.text = CultivationFormat.amount(cost)
		next_realm_label.text = _realm_name(next_slug)
		var can_break := cultivation >= cost
		progress_hint.text = "修为已足，可尝试突破" if can_break else "修为不足"
		breakthrough_button.disabled = not can_break or _busy
		breakthrough_button.text = "突破境界"
		cultivation_progress.max_value = 100.0
		cultivation_progress.value = clampf(cultivation / maxf(cost, 1.0), 0.0, 1.0) * 100.0
	_render_stages()
	_render_bag()
	_render_skills()


func _render_stages() -> void:
	for child in stage_list.get_children():
		child.queue_free()
	var stages := _stages_for_current_realm()
	if stages.is_empty():
		_selected_stage = ""
		stage_label.text = "还没有可以打的关卡" if _current_realm_code() >= 0 else "境界不存在"
		monster_label.text = ""
		challenge_button.disabled = true
		challenge_button.text = "挑战首领"
		return
	var known := false
	for stage in stages:
		if str(stage.get("slug", "")) == _selected_stage:
			known = true
	if not known:
		_selected_stage = str(stages[0].get("slug", ""))
	for stage in stages:
		var slug := str(stage.get("slug", ""))
		var button := Button.new()
		_style_choice(button)
		button.text = _stage_button_text(stage)
		button.pressed.connect(_select_stage.bind(slug))
		stage_list.add_child(button)
	var selected := _stage_def(_selected_stage)
	stage_label.text = _stage_button_text(selected)
	monster_label.text = _boss_text(selected)
	challenge_button.disabled = _selected_stage.is_empty() or _busy
	var bosses: Array = selected.get("bosses", [])
	var boss_name := ""
	if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY:
		boss_name = str((bosses[0] as Dictionary).get("name", ""))
	var power := int(selected.get("recommendedPower", 0))
	var power_text := " · 推荐战力 %d" % power if power > 0 else ""
	challenge_button.text = "挑战 %s%s" % [boss_name if not boss_name.is_empty() else "首领", power_text]


func _plain_text(value: Variant) -> String:
	if value == null:
		return ""
	var text := str(value).strip_edges()
	if text.is_empty() or text == "<null>":
		return ""
	return text


func _equipped_slot(item: Dictionary) -> String:
	return _plain_text(item.get("equippedSlot", null))


func _bag_section(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_label_size(label, 40)
	label.add_theme_color_override("font_color", Color(0.86, 0.74, 0.44))
	bag_list.add_child(label)


func _bag_empty(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_set_label_size(label, 36)
	bag_list.add_child(label)


func _bag_button(item: Dictionary, worn: bool) -> void:
	var item_id := str(item.get("id", ""))
	var slug := str(item.get("itemSlug", ""))
	var button := Button.new()
	_style_choice(button)
	button.text = _item_name(slug)
	button.pressed.connect(_on_item.bind(item_id, worn))
	bag_list.add_child(button)
	if worn or str(_item_def(slug).get("kind", "")) != "equipment":
		return
	var decompose := Button.new()
	_style_choice(decompose)
	decompose.text = "分解 %s" % _item_name(slug)
	decompose.pressed.connect(_on_decompose.bind(item_id))
	bag_list.add_child(decompose)


func _render_bag() -> void:
	for child in bag_list.get_children():
		child.queue_free()
	var auto := Button.new()
	_style_choice(auto)
	var enabled := bool(_state.get("autoDecompose", false))
	auto.text = "自动分解低于身上的装备：%s" % ("开" if enabled else "关")
	auto.pressed.connect(_on_auto_decompose.bind(not enabled))
	bag_list.add_child(auto)
	var worn_items: Array[Dictionary] = []
	var bag_items: Array[Dictionary] = []
	for row in _state.get("items", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var item := row as Dictionary
		if _equipped_slot(item).is_empty():
			bag_items.append(item)
		else:
			worn_items.append(item)
	bag_count_label.text = "已穿戴 %d 件，背包 %d 件" % [worn_items.size(), bag_items.size()]
	_bag_section("已穿戴")
	if worn_items.is_empty():
		_bag_empty("还没有穿戴")
	else:
		for item in worn_items:
			_bag_button(item, true)
	_bag_section("背包")
	if bag_items.is_empty():
		_bag_empty("背包是空的")
	else:
		for item in bag_items:
			_bag_button(item, false)


func _render_skills() -> void:
	for child in skill_list.get_children():
		child.queue_free()
	var skills: Array = _state.get("skills", [])
	var lines: PackedStringArray = []
	for row in skills:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var skill: Dictionary = row
		var slug := str(skill.get("skillSlug", ""))
		var name := _skill_name(slug)
		var level := int(skill.get("level", 1))
		if level < 1:
			level = 1
		var title := "%s · %d层" % [name, level]
		var running := _plain_text(skill.get("runningSlot", null))
		lines.append(title if running.is_empty() else "%s · 运转中" % title)
		var button := Button.new()
		_style_choice(button)
		button.text = "运转 %s" % title if running.is_empty() else "停止 %s" % title
		button.pressed.connect(_on_skill.bind(slug, running))
		skill_list.add_child(button)
	learned_label.text = "已学：" + ("、".join(lines) if not lines.is_empty() else "还没有功法")


func _select_stage(slug: String) -> void:
	_selected_stage = slug
	_render_stages()


func _on_breakthrough() -> void:
	if _busy:
		return
	_busy = true
	breakthrough_button.disabled = true
	progress_hint.text = "正在突破…"
	var result := await PlayerApi.post_action("/api/v1/me/breakthrough")
	_busy = false
	if int(result.get("code", 0)) != 200:
		_render()
		progress_hint.text = PlayerApi.error_message(result)
		return
	var outcome: Dictionary = result.get("result", {})
	if bool(outcome.get("success", false)):
		breakthrough_banner.text = "突破成功"
	else:
		breakthrough_banner.text = "突破失败，损失修为 %s" % CultivationFormat.amount(float(outcome.get("lostCultivation", 0)))
	breakthrough_banner.visible = true
	_apply_action_state(result)


func _on_challenge() -> void:
	if _busy or _selected_stage.is_empty():
		return
	_busy = true
	var result := await PlayerApi.post_action("/api/v1/me/stages/%s/challenge" % _selected_stage.uri_encode())
	_busy = false
	if int(result.get("code", 0)) != 200:
		stage_hint.text = PlayerApi.error_message(result)
		return
	var battle: Dictionary = result.get("battle", {})
	var won := bool(battle.get("win", false))
	stage_hint.text = "胜利" if won else "失败：%s" % str(battle.get("reason", ""))
	var names: PackedStringArray = []
	for drop in result.get("drops", []):
		if typeof(drop) == TYPE_DICTIONARY:
			var reward := _reward_name(str((drop as Dictionary).get("itemSlug", "")))
			if bool((drop as Dictionary).get("decomposed", false)):
				reward += "（已分解）"
			names.append(reward)
	loot_summary_label.text = "获得：" + ("、".join(names) if not names.is_empty() else "无")
	battle_log_label.text = stage_hint.text
	_apply_action_state(result)


func _on_item(item_id: String, worn: bool) -> void:
	if _busy or item_id.is_empty():
		return
	var slug := _item_slug_by_id(item_id)
	var action := "equip"
	if worn:
		action = "unequip"
	elif str(_item_def(slug).get("kind", "")) == "skill_book":
		action = "use"
	var path := "/api/v1/me/items/%s/%s" % [item_id.uri_encode(), action]
	_busy = true
	var result := await PlayerApi.post_action(path)
	_busy = false
	if int(result.get("code", 0)) != 200:
		_bag_hint.text = PlayerApi.error_message(result)
		_bag_hint.visible = true
		return
	if action == "use":
		var learned: Dictionary = result.get("learned", {})
		if learned.has("convertedCultivation"):
			_bag_hint.text = "功法已圆满，转为修为 %s" % CultivationFormat.amount(float(learned.get("convertedCultivation", 0)))
		else:
			_bag_hint.text = "学会了，现在是 %s 层" % str(learned.get("level", ""))
		_bag_hint.visible = true
	else:
		_bag_hint.visible = false
	_apply_action_state(result)


func _on_decompose(item_id: String) -> void:
	if _busy or item_id.is_empty():
		return
	_busy = true
	var result := await PlayerApi.post_action("/api/v1/me/items/%s/decompose" % item_id.uri_encode())
	_busy = false
	if int(result.get("code", 0)) != 200:
		_bag_hint.text = PlayerApi.error_message(result)
		_bag_hint.visible = true
		return
	_bag_hint.text = "分解得到修为 %s" % CultivationFormat.amount(float(result.get("convertedCultivation", 0)))
	_bag_hint.visible = true
	_apply_action_state(result)


func _on_auto_decompose(enabled: bool) -> void:
	if _busy:
		return
	_busy = true
	var result := await PlayerApi.post_action("/api/v1/me/auto-decompose", {"enabled": enabled})
	_busy = false
	if int(result.get("code", 0)) != 200:
		_bag_hint.text = PlayerApi.error_message(result)
		_bag_hint.visible = true
		return
	_bag_hint.visible = false
	_apply_action_state(result)


func _item_slug_by_id(item_id: String) -> String:
	for row in _state.get("items", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("id", "")) == item_id:
			return str((row as Dictionary).get("itemSlug", ""))
	return ""


func _on_skill(slug: String, running: String) -> void:
	if _busy or slug.is_empty():
		return
	_busy = true
	var result: Dictionary
	if running.is_empty():
		var slot := "heart" if str(_skill_def(slug).get("role", "")) == "heart" else "art_1"
		result = await PlayerApi.post_action("/api/v1/me/skills/%s/run" % slug.uri_encode(), {"slot": slot})
	else:
		result = await PlayerApi.post_action("/api/v1/me/skills/%s/stop" % slug.uri_encode())
	_busy = false
	if int(result.get("code", 0)) != 200:
		_skill_hint.text = PlayerApi.error_message(result)
		_skill_hint.visible = true
		return
	_skill_hint.visible = false
	_apply_action_state(result)


func _apply_action_state(result: Dictionary) -> void:
	var state: Variant = result.get("state", {})
	if typeof(state) == TYPE_DICTIONARY:
		_state = state
		_state["code"] = 200
		_render()


func _set_status(message: String) -> void:
	status_label.text = message
	status_label.visible = not message.is_empty()


func _realm_name(slug: String) -> String:
	for row in _content.get("realms", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return str((row as Dictionary).get("displayName", slug))
	return slug


func _current_realm_code() -> int:
	var slug := str(_state.get("realmSlug", ""))
	for row in _content.get("realms", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return int((row as Dictionary).get("sortOrder", -1))
	return -1


func _stages_for_current_realm() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var code := _current_realm_code()
	if code < 0:
		return found
	for row in _content.get("stages", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var stage_code := int((row as Dictionary).get("requiredRealmOrder", -1))
		if stage_code >= 0 and stage_code <= code:
			found.append(row as Dictionary)
	found.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_code := int(left.get("requiredRealmOrder", 0))
		var right_code := int(right.get("requiredRealmOrder", 0))
		if left_code == right_code:
			return str(left.get("displayName", "")) < str(right.get("displayName", ""))
		return left_code < right_code
	)
	return found


func _stage_button_text(stage: Dictionary) -> String:
	var stage_code := int(stage.get("requiredRealmOrder", -1))
	var realm_name := _realm_name_for_code(stage_code)
	var stage_name := str(stage.get("displayName", ""))
	if stage_name.is_empty():
		stage_name = "名称缺失"
	var power := int(stage.get("recommendedPower", 0))
	if power > 0:
		return "%s · %s · 推荐战力 %d" % [realm_name, stage_name, power]
	return "%s · %s" % [realm_name, stage_name]


func _realm_name_for_code(code: int) -> String:
	for row in _content.get("realms", []):
		if typeof(row) == TYPE_DICTIONARY and int((row as Dictionary).get("sortOrder", -1)) == code:
			var name := str((row as Dictionary).get("displayName", ""))
			return name if not name.is_empty() else "名称缺失"
	return "境界编号 %d 不存在" % code


func _boss_text(stage: Dictionary) -> String:
	var bosses: Array = stage.get("bosses", [])
	if bosses.is_empty():
		var legacy := str(stage.get("bossName", ""))
		return legacy if not legacy.is_empty() else "还没有首领"
	var lines: PackedStringArray = []
	for boss in bosses:
		if typeof(boss) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = boss
		var names: PackedStringArray = []
		for drop in record.get("drops", []):
			if typeof(drop) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = drop
			names.append("%s %s%%" % [_reward_name(str(entry.get("itemSlug", ""))), str(float(entry.get("chanceBp", 0)) / 100.0)])
		var mounted := "、".join(names) if not names.is_empty() else "无"
		var boss_name := str(record.get("name", ""))
		lines.append("%s　气血 %s　掉落 %s" % [boss_name if not boss_name.is_empty() else "名称缺失", str(record.get("hp", "")), mounted])
	return "\n".join(lines)


func _stage_name(slug: String) -> String:
	var definition := _stage_def(slug)
	if definition.is_empty():
		return "关卡不存在"
	var name := str(definition.get("displayName", ""))
	return name if not name.is_empty() else "名称缺失"


func _stage_def(slug: String) -> Dictionary:
	for row in _content.get("stages", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return row
	return {}


func _reward_name(slug: String) -> String:
	var item := _item_def(slug)
	if not item.is_empty():
		var item_name := str(item.get("displayName", ""))
		return item_name if not item_name.is_empty() else "名称缺失"
	var skill := _skill_def(slug)
	if not skill.is_empty():
		var skill_name := str(skill.get("displayName", ""))
		return skill_name if not skill_name.is_empty() else "名称缺失"
	return "名称缺失"


func _item_name(slug: String) -> String:
	var definition := _item_def(slug)
	if definition.is_empty():
		return "物品不存在"
	var name := str(definition.get("displayName", ""))
	return name if not name.is_empty() else "名称缺失"


func _item_def(slug: String) -> Dictionary:
	for row in _content.get("items", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return row
	return {}


func _skill_name(slug: String) -> String:
	var definition := _skill_def(slug)
	if definition.is_empty():
		return "功法不存在"
	var name := str(definition.get("displayName", ""))
	return name if not name.is_empty() else "名称缺失"


func _skill_def(slug: String) -> Dictionary:
	for row in _content.get("skills", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return row
	return {}
