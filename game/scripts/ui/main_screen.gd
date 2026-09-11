extends Control

const DATA_MARKER_PATH := "user://demo_install_marker.txt"
const TICK_SECONDS := 1.0
const PAGE_CULTIVATE := "cultivate"
const PAGE_ADVENTURE := "adventure"
const PAGE_BAG := "bag"
const PAGE_SKILL := "skill"
const PAGE_SETTINGS := "settings"

@onready var title_label: Label = %Title
@onready var version_label: Label = %VersionLabel
@onready var data_marker: Label = %DataMarker
@onready var upgrade_badge: Label = %UpgradeBadge
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
@onready var download_progress: ProgressBar = %DownloadProgress
@onready var check_button: Button = %CheckButton
@onready var install_button: Button = %InstallButton
@onready var update_dialog: ConfirmationDialog = %UpdateDialog
@onready var offline_dialog: AcceptDialog = %OfflineDialog
@onready var update_service: UpdateService = %UpdateService
@onready var flash: ColorRect = %Flash
@onready var seal_ring: Panel = %SealRing
@onready var seal_inner: Panel = %SealInner
@onready var progress_hint: Label = %ProgressHint
@onready var cultivation_card: PanelContainer = %CultivationCard
@onready var stats_card: PanelContainer = %StatsCard
@onready var journal_card: PanelContainer = %JournalCard
@onready var update_card: PanelContainer = %UpdateCard
@onready var adventure_page: PanelContainer = %AdventurePage
@onready var bag_page: PanelContainer = %BagPage
@onready var skill_page: PanelContainer = %SkillPage
@onready var settings_page: PanelContainer = %SettingsPage
@onready var power_label: Label = %PowerLabel
@onready var stage_label: Label = %StageLabel
@onready var monster_label: Label = %MonsterLabel
@onready var layer_row: HBoxContainer = %LayerRow
@onready var sight_label: Label = %SightLabel
@onready var challenge_button: Button = %ChallengeButton
@onready var stage_hint: Label = %StageHint
@onready var loot_summary_label: Label = %LootSummaryLabel
@onready var battle_log_label: Label = %BattleLogLabel
@onready var equip_summary: Label = %EquipSummary
@onready var doll_board: PanelContainer = %DollBoard
@onready var bag_count_label: Label = %BagCountLabel
@onready var bag_tabs: HBoxContainer = %BagTabs
@onready var bag_list: GridContainer = %BagList
@onready var inspect_layer: ColorRect = %ItemInspectLayer
@onready var inspect_card: PanelContainer = %ItemInspectCard
@onready var learned_label: Label = %LearnedLabel
@onready var skill_list: VBoxContainer = %SkillList
@onready var battle_log_check: CheckButton = %BattleLogCheck
@onready var bag_policy_button: Button = %BagPolicyButton
@onready var volume_label: Label = %VolumeLabel
@onready var volume_slider: HSlider = %VolumeSlider
@onready var export_button: Button = %ExportButton
@onready var export_label: Label = %ExportLabel
@onready var tab_cultivate: Button = %TabCultivate
@onready var tab_adventure: Button = %TabAdventure
@onready var tab_bag: Button = %TabBag
@onready var tab_skill: Button = %TabSkill
@onready var tab_settings: Button = %TabSettings
@onready var hint_label: Label = $Margin/Content/Hint
@onready var atmosphere: Control = $Margin/Content/Atmosphere
@onready var chrome: PanelContainer = %Chrome
@onready var chrome_row: HBoxContainer = %ChromeRow
@onready var chrome_power: Label = %ChromePower
@onready var chrome_cultivation_row: HBoxContainer = %ChromeCultivationRow
@onready var stage_list: VBoxContainer = %StageList
@onready var inspect_panel: VBoxContainer = %InspectPanel

var _session: CultivationSession
var _tick: Timer
var _banner_tween: Tween
var _ready_pulse: Tween
var _banner_generation := 0
var _update_check_pending := true
var _page := PAGE_CULTIVATE
var _bag_fingerprint := ""
var _skill_fingerprint := ""
var _stage_fingerprint := ""
var _selected_bag_uid := 0
var _bag_tab := "all"
var _slot_buttons: Dictionary = {}
var _figure_label: Label
var _inspect_empty_slot := ""


func _ready() -> void:
	theme = MainTheme.make()
	title_label.add_theme_font_override("font", MainTheme.title_font())
	realm_label.add_theme_font_override("font", MainTheme.title_font())
	cultivation_label.add_theme_font_override("font", MainTheme.title_font())
	chrome.add_theme_stylebox_override("panel", MainTheme.footer_panel())
	cultivation_card.add_theme_stylebox_override("panel", MainTheme.hero_panel())
	stats_card.add_theme_stylebox_override("panel", MainTheme.inner_panel())
	journal_card.add_theme_stylebox_override("panel", MainTheme.inner_panel())
	update_card.add_theme_stylebox_override("panel", MainTheme.footer_panel())
	adventure_page.add_theme_stylebox_override("panel", MainTheme.hero_panel())
	bag_page.add_theme_stylebox_override("panel", MainTheme.hero_panel())
	skill_page.add_theme_stylebox_override("panel", MainTheme.hero_panel())
	settings_page.add_theme_stylebox_override("panel", MainTheme.hero_panel())
	seal_ring.add_theme_stylebox_override("panel", MainTheme.seal_ring())
	seal_inner.add_theme_stylebox_override("panel", MainTheme.seal_inner())
	_install_chrome()
	_install_bag_board()
	_install_layer_row()
	_apply_layout()
	_style_secondary_button(check_button)
	_style_secondary_button(install_button)
	_style_secondary_button(bag_policy_button)
	_style_secondary_button(export_button)
	for tab in [tab_cultivate, tab_adventure, tab_bag, tab_skill, tab_settings]:
		_style_secondary_button(tab)
	download_progress.visible = false
	status_label.visible = false

	_session = CultivationSession.new()
	_session.state_changed.connect(_refresh_all)
	_session.offline_settled.connect(_on_offline_settled)
	_session.breakthrough_succeeded.connect(_on_breakthrough_succeeded)
	if not _session.start():
		status_label.text = "修炼配置读取失败。"
		status_label.visible = true
		return

	_tick = Timer.new()
	_tick.wait_time = TICK_SECONDS
	_tick.autostart = true
	_tick.timeout.connect(_session.tick_online)
	add_child(_tick)
	tree_exiting.connect(_session.tick_online)

	breakthrough_button.pressed.connect(_on_breakthrough_pressed)
	challenge_button.pressed.connect(_on_challenge_pressed)
	tab_cultivate.pressed.connect(func() -> void: _show_page(PAGE_CULTIVATE))
	tab_adventure.pressed.connect(func() -> void: _show_page(PAGE_ADVENTURE))
	tab_bag.pressed.connect(func() -> void: _show_page(PAGE_BAG))
	tab_skill.pressed.connect(func() -> void: _show_page(PAGE_SKILL))
	tab_settings.pressed.connect(func() -> void: _show_page(PAGE_SETTINGS))
	battle_log_check.toggled.connect(func(enabled: bool) -> void:
		_session.set_battle_log_enabled(enabled)
	)
	bag_policy_button.pressed.connect(_on_bag_policy_pressed)
	volume_slider.value_changed.connect(func(value: float) -> void:
		_session.set_sound_volume(value)
	)
	export_button.pressed.connect(_on_export_pressed)
	check_button.pressed.connect(update_service.check_for_update)
	install_button.pressed.connect(update_service.install_downloaded_update)
	update_dialog.confirmed.connect(update_service.download_update)
	update_service.status_changed.connect(_on_status_changed)
	update_service.update_available.connect(_on_update_available)
	update_service.no_update.connect(_on_no_update)
	update_service.download_progress_changed.connect(_on_download_progress_changed)
	update_service.download_ready.connect(_on_download_ready)
	update_service.failed.connect(_on_update_failed)

	var current_version := update_service.get_current_version()
	version_label.text = "版本 %s" % current_version
	data_marker.text = _load_or_create_data_marker()
	upgrade_badge.visible = false
	download_progress.value = 0.0
	breakthrough_banner.visible = false
	flash.modulate.a = 0.0
	realm_label.resized.connect(func() -> void:
		realm_label.pivot_offset = realm_label.size * 0.5
	)
	_show_page(PAGE_CULTIVATE)
	_refresh_all()
	offline_dialog.visibility_changed.connect(func() -> void:
		if not offline_dialog.visible:
			_maybe_check_update()
	)
	get_tree().create_timer(1.2).timeout.connect(_maybe_check_update)


func _show_page(page: String) -> void:
	_page = page
	var cultivate := page == PAGE_CULTIVATE
	cultivation_card.visible = cultivate
	journal_card.visible = cultivate
	atmosphere.visible = false
	hint_label.visible = false
	adventure_page.visible = page == PAGE_ADVENTURE
	bag_page.visible = page == PAGE_BAG
	skill_page.visible = page == PAGE_SKILL
	settings_page.visible = page == PAGE_SETTINGS
	update_card.visible = page == PAGE_SETTINGS
	_refresh_tabs()
	_refresh_all()


func _refresh_all() -> void:
	_refresh_cultivation()
	_refresh_chrome_power()
	if _page == PAGE_ADVENTURE:
		_refresh_adventure()
	elif _page == PAGE_BAG:
		_refresh_bag()
	elif _page == PAGE_SKILL:
		_refresh_skills()
	elif _page == PAGE_SETTINGS:
		_refresh_settings()


func _refresh_cultivation() -> void:
	var realm := _session.current_realm()
	if realm == null or _session.state == null:
		return
	realm_label.text = realm.display_name
	realm_path.text = _session.config.display_path(realm)
	var rate := _session.cultivate_rate()
	if _session.state.qi_pill_until > 0:
		rate_label.text = "%s · 回气中" % CultivationFormat.rate(rate)
	else:
		rate_label.text = CultivationFormat.rate(rate)
	cultivation_progress.value = _session.progress() * 100.0
	journal_label.text = _session.journal.as_text()
	var next_realm := _session.next_realm()
	if next_realm == null:
		cultivation_label.text = CultivationFormat.amount(_session.state.cultivation)
		next_cost_label.text = "—"
		next_realm_label.text = "已至顶峰"
		progress_hint.text = "已至当前示意表最高境界"
		breakthrough_button.disabled = true
		breakthrough_button.text = "已圆满"
		cultivation_progress.add_theme_stylebox_override("fill", MainTheme.progress_fill(false))
		_set_ready_pulse(false)
	else:
		cultivation_label.text = "%s / %s" % [
			CultivationFormat.amount(_session.state.cultivation),
			CultivationFormat.amount(realm.breakthrough_cost),
		]
		next_cost_label.text = CultivationFormat.amount(realm.breakthrough_cost)
		next_realm_label.text = next_realm.display_name
		var remaining := maxf(0.0, realm.breakthrough_cost - _session.state.cultivation)
		if remaining <= 0.001:
			progress_hint.text = "修为已足，可突破至 %s" % next_realm.display_name
		else:
			var wait := int(ceili(remaining / maxf(rate, 0.001)))
			progress_hint.text = "距突破还需 %s · 约 %s" % [
				CultivationFormat.amount(remaining),
				CultivationFormat.duration_hours(wait),
			]
		var can_break := _session.can_breakthrough()
		breakthrough_button.disabled = not can_break
		breakthrough_button.text = "突破境界" if can_break else "修为不足"
		cultivation_progress.add_theme_stylebox_override("fill", MainTheme.progress_fill(can_break))
		_set_ready_pulse(can_break)


func _refresh_adventure() -> void:
	if _session.state == null:
		return
	var stats := _session.player_stats()
	power_label.text = "己方  攻 %s  防 %s  速 %s  血 %s" % [
		CultivationFormat.amount(stats.attack),
		CultivationFormat.amount(stats.defense),
		CultivationFormat.amount(stats.speed),
		CultivationFormat.amount(stats.hp),
	]
	var stage := _session.current_stage()
	if stage == null:
		stage_label.text = "未选定关卡"
		monster_label.text = ""
		challenge_button.disabled = true
		_refresh_layer_row()
		_refresh_sight()
		_refresh_stage_list(stats)
		return
	var layer := _session.state.current_layer()
	stage_label.text = "%s · %s · 挂机中" % [stage.display_name, StageLayer.display_name(layer)]
	var names: PackedStringArray = PackedStringArray()
	if layer == StageLayer.BOSS and not stage.monsters.is_empty():
		monster_label.text = "头目循环：%s" % stage.monsters[stage.monsters.size() - 1].display_name
	else:
		for monster in stage.monsters:
			names.append(monster.display_name)
			if names.size() >= 3:
				break
		var suffix := "（深处）" if layer == StageLayer.INNER else ""
		if stage.monsters.size() > names.size():
			monster_label.text = "出没：%s 等%s" % ["、".join(names), suffix]
		else:
			monster_label.text = "出没：%s%s" % ["、".join(names), suffix]
	_refresh_layer_row()
	_refresh_sight()
	var nxt := _session.next_stage()
	if nxt == null:
		challenge_button.text = "已至最深关卡"
		challenge_button.disabled = true
		stage_hint.text = "继续在此关收集更高品质装备。"
	else:
		challenge_button.disabled = false
		challenge_button.text = "挑战 %s" % nxt.display_name
		if _session.can_challenge_next():
			stage_hint.text = "短板与境界已足，可挑战下一关。"
		else:
			stage_hint.text = CombatRules.enter_reason(
				_session.state,
				_session.config,
				nxt,
				stats,
				false
			)
	if _session.last_combat_result != null and not _session.last_combat_result.loot_names.is_empty():
		loot_summary_label.text = "最近入袋：%s" % "、".join(_session.last_combat_result.loot_names)
	else:
		loot_summary_label.text = "最近入袋：尚无。挂机后会入行囊。"
	if _session.state.battle_log.is_empty():
		battle_log_label.text = "静待交手。挂机时会在此留下斩杀与掉落。"
	else:
		var start := maxi(_session.state.battle_log.size() - 16, 0)
		var slice := _session.state.battle_log.slice(start)
		battle_log_label.text = "\n".join(slice)
	_refresh_stage_list(stats)


func _refresh_bag() -> void:
	if _session.state == null:
		return
	_refresh_doll()
	var used := InventoryRules.bag_used(_session.state)
	bag_count_label.text = "行囊 %d / %d" % [used, _session.state.inventory_capacity]
	if _selected_bag_uid > 0 and InventoryRules.find_stack(_session.state, _selected_bag_uid) == null:
		_selected_bag_uid = 0
		_close_inspect()
	_refresh_bag_tabs()
	var visible := InventoryRules.filter_stacks(_session.state, _session.adventure, _bag_tab)
	var fingerprint := "%d|%d|%s|%d|%s|%d|%s|%d|%d|%s" % [
		_session.state.next_item_uid,
		_session.state.inventory.size(),
		JSON.stringify(_session.state.equipped.to_dictionary()),
		_session.state.learned_skill_ids.size(),
		_bag_tab,
		visible.size(),
		JSON.stringify(_session.state.skill_ranks),
		_session.state.qi_pill_until,
		_session.state.body_pill_until,
		_bag_progress_stamp(),
	]
	if fingerprint != _bag_fingerprint or bag_list.get_child_count() == 0:
		_bag_fingerprint = fingerprint
		for child in bag_list.get_children():
			child.queue_free()
		if visible.is_empty():
			var empty := Label.new()
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if used == 0 and _session.state.inventory.is_empty():
				empty.text = "行囊空空。去历练挂机，掉落会回到这里。"
			elif used == 0:
				empty.text = "穿戴中的装备在上方。袋里没有未穿的物品。"
			else:
				empty.text = "这一类还是空的。"
			MainTheme.stamp_label(empty, MainTheme.SIZE_CAPTION, MainTheme.MUTED)
			bag_list.add_child(empty)
		else:
			for stack in visible:
				bag_list.add_child(_make_bag_cell(stack))
	if inspect_layer.visible:
		_fill_inspect_card()


func _refresh_skills() -> void:
	if _session.state == null or _session.adventure == null:
		return
	var realm := _session.current_realm()
	var attack := 0.0
	var defense := 0.0
	var hp := 0.0
	var names: PackedStringArray = PackedStringArray()
	for skill_id in _session.state.learned_skill_ids:
		var learned_skill := _session.adventure.skill_by_id(skill_id)
		if learned_skill == null:
			continue
		var mastery := _session.state.skill_rank_of(skill_id)
		var live := learned_skill.to_stats(mastery)
		attack += live.attack
		defense += live.defense
		hp += live.hp
		names.append("%s（%s·%s）" % [
			learned_skill.display_name,
			SkillRank.display_name(learned_skill.rank),
			"小成" if mastery >= 2 else "入门",
		])
	if names.is_empty():
		learned_label.text = "尚未参悟。行囊里的残页可参悟。"
	else:
		learned_label.text = "已学加成  攻+%s  防+%s  血+%s\n%s" % [
			CultivationFormat.amount(attack),
			CultivationFormat.amount(defense),
			CultivationFormat.amount(hp),
			"、".join(names),
		]
	var fingerprint := "%s|%s|%s" % [
		",".join(_session.state.learned_skill_ids),
		JSON.stringify(_session.state.skill_ranks),
		realm.id if realm != null else "",
	]
	if fingerprint == _skill_fingerprint and skill_list.get_child_count() > 0:
		return
	_skill_fingerprint = fingerprint
	for child in skill_list.get_children():
		child.queue_free()
	for skill in _session.adventure.skills:
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", MainTheme.SIZE_CAPTION)
		var mastery := _session.state.skill_rank_of(skill.id)
		var locked := realm != null and realm.order < skill.min_realm_order
		var mark := "未入手"
		var shown := skill.to_stats(maxi(mastery, 1))
		if mastery >= 2:
			mark = "小成"
			row.add_theme_color_override("font_color", MainTheme.JADE)
		elif mastery >= 1:
			mark = "入门"
			row.add_theme_color_override("font_color", MainTheme.JADE)
		elif locked:
			mark = "需第 %d 阶" % skill.min_realm_order
			row.add_theme_color_override("font_color", MainTheme.MUTED)
		elif _has_book_for(skill.id):
			mark = "行囊有残页"
			row.add_theme_color_override("font_color", MainTheme.IVORY)
		else:
			row.add_theme_color_override("font_color", MainTheme.MUTED)
		row.text = "%s · %s · %s  攻+%s 防+%s 血+%s" % [
			skill.display_name,
			SkillRank.display_name(skill.rank),
			mark,
			CultivationFormat.amount(shown.attack),
			CultivationFormat.amount(shown.defense),
			CultivationFormat.amount(shown.hp),
		]
		skill_list.add_child(row)


func _refresh_settings() -> void:
	if _session.state == null:
		return
	battle_log_check.set_pressed_no_signal(_session.state.settings.battle_log_enabled)
	if _session.state.settings.bag_full_policy == GameSettings.POLICY_DISCARD_LOWEST:
		bag_policy_button.text = "满包：丢掉最低品质"
	else:
		bag_policy_button.text = "满包：跳过掉落"
	volume_slider.set_value_no_signal(_session.state.settings.sound_volume)
	volume_label.text = "音量 %d%%" % int(round(_session.state.settings.sound_volume * 100.0))


func _install_chrome() -> void:
	realm_label.reparent(chrome_row)
	chrome_row.move_child(realm_label, 0)
	chrome_row.move_child(chrome_power, 1)
	cultivation_label.reparent(chrome_cultivation_row)
	realm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cultivation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chrome_power.size_flags_horizontal = Control.SIZE_SHRINK_END
	realm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cultivation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	chrome_power.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var settings_box := settings_page.get_node("SettingsMargin/SettingsBox") as VBoxContainer
	if settings_box != null:
		version_label.reparent(settings_box)
		settings_box.move_child(version_label, 0)
		version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _apply_layout() -> void:
	MainTheme.stamp_label(realm_label, MainTheme.SIZE_DISPLAY, MainTheme.JADE)
	MainTheme.stamp_label(cultivation_label, MainTheme.SIZE_NUMBER, MainTheme.IVORY)
	MainTheme.stamp_label(chrome_power, MainTheme.SIZE_CAPTION, MainTheme.GOLD)
	MainTheme.stamp_label(progress_hint, MainTheme.SIZE_UI, MainTheme.GOLD)
	MainTheme.stamp_label(realm_path, MainTheme.SIZE_MICRO, Color(0.72, 0.68, 0.5, 0.9))
	MainTheme.stamp_label(breakthrough_banner, MainTheme.SIZE_BODY, MainTheme.GOLD)
	MainTheme.stamp_label(offline_label, MainTheme.SIZE_CAPTION, MainTheme.GOLD)
	MainTheme.stamp_label(journal_label, MainTheme.SIZE_CAPTION, Color(0.74, 0.78, 0.74, 1))
	MainTheme.stamp_label(stage_label, MainTheme.SIZE_HERO, MainTheme.IVORY)
	MainTheme.stamp_label(power_label, MainTheme.SIZE_CAPTION, MainTheme.MUTED)
	MainTheme.stamp_label(monster_label, MainTheme.SIZE_CAPTION, MainTheme.MUTED)
	MainTheme.stamp_label(stage_hint, MainTheme.SIZE_CAPTION, MainTheme.GOLD)
	MainTheme.stamp_label(loot_summary_label, MainTheme.SIZE_CAPTION, MainTheme.IVORY)
	MainTheme.stamp_label(battle_log_label, MainTheme.SIZE_MICRO, Color(0.7, 0.74, 0.7, 1))
	MainTheme.stamp_label(equip_summary, MainTheme.SIZE_MICRO, MainTheme.MUTED)
	MainTheme.stamp_label(bag_count_label, MainTheme.SIZE_MICRO, MainTheme.MUTED)
	doll_board.add_theme_stylebox_override("panel", MainTheme.inner_panel())
	inspect_card.add_theme_stylebox_override("panel", MainTheme.hero_panel())
	bag_list.columns = MainTheme.BAG_COLUMNS
	MainTheme.stamp_label(learned_label, MainTheme.SIZE_BODY, MainTheme.IVORY)
	MainTheme.stamp_label(version_label, MainTheme.SIZE_MICRO, MainTheme.MUTED)
	MainTheme.stamp_label(volume_label, MainTheme.SIZE_CAPTION, MainTheme.MUTED)
	MainTheme.stamp_label(export_label, MainTheme.SIZE_MICRO, MainTheme.MUTED)
	cultivation_progress.custom_minimum_size = Vector2(0, MainTheme.H_BAR)
	breakthrough_button.custom_minimum_size = Vector2(0, MainTheme.H_CTA)
	breakthrough_button.add_theme_font_size_override("font_size", MainTheme.SIZE_NUMBER)
	challenge_button.custom_minimum_size = Vector2(0, MainTheme.H_CTA)
	challenge_button.add_theme_font_size_override("font_size", MainTheme.SIZE_NUMBER)
	for tab in [tab_cultivate, tab_adventure, tab_bag, tab_skill, tab_settings]:
		tab.custom_minimum_size = Vector2(0, MainTheme.H_TAB)
		tab.add_theme_font_size_override("font_size", MainTheme.SIZE_UI)
	var cultivate_box := cultivation_card.get_node_or_null("CultivationMargin/CultivationDetails") as VBoxContainer
	if cultivate_box != null:
		cultivate_box.move_child(progress_hint, 0)
		cultivate_box.move_child(cultivation_progress, 1)
		cultivate_box.move_child(breakthrough_button, 2)
		cultivate_box.move_child(stats_card, 3)
		cultivate_box.move_child(realm_path, 4)
		cultivate_box.move_child(breakthrough_banner, 5)
		cultivate_box.move_child(offline_label, 6)
	var adventure_box := adventure_page.get_node_or_null("AdventureMargin/AdventureBox") as VBoxContainer
	if adventure_box != null:
		adventure_box.move_child(stage_label, 0)
		adventure_box.move_child(power_label, 1)
		adventure_box.move_child(monster_label, 2)
		adventure_box.move_child(challenge_button, 3)
		adventure_box.move_child(stage_hint, 4)
		adventure_box.move_child(loot_summary_label, 5)
		adventure_box.move_child(stage_list, 6)
		var log_scroll := adventure_box.get_node_or_null("BattleLogScroll")
		if log_scroll != null:
			adventure_box.move_child(log_scroll, 7)


func _refresh_chrome_power() -> void:
	if _session == null or _session.state == null:
		chrome_power.text = "战力 —"
		return
	var stats := _session.player_stats()
	chrome_power.text = "战力 %s" % CultivationFormat.amount(stats.power())


func _refresh_tabs() -> void:
	var selected := {
		PAGE_CULTIVATE: tab_cultivate,
		PAGE_ADVENTURE: tab_adventure,
		PAGE_BAG: tab_bag,
		PAGE_SKILL: tab_skill,
		PAGE_SETTINGS: tab_settings,
	}
	for page in selected.keys():
		var tab: Button = selected[page]
		if str(page) == _page:
			tab.remove_theme_stylebox_override("normal")
			tab.remove_theme_stylebox_override("hover")
			tab.remove_theme_stylebox_override("pressed")
			tab.add_theme_color_override("font_color", Color(0.12, 0.1, 0.06, 1))
			tab.add_theme_color_override("font_hover_color", Color(0.12, 0.1, 0.06, 1))
		else:
			_style_secondary_button(tab)


func _refresh_stage_list(stats: CombatStats) -> void:
	if _session.adventure == null:
		return
	var fingerprint := "%s|%s|%.0f|%s|%s|%s" % [
		_session.state.current_stage_id,
		",".join(_session.state.unlocked_stage_ids),
		stats.power(),
		_session.state.realm_id,
		JSON.stringify(_session.state.stage_layers),
		JSON.stringify(_session.state.layer_kills),
	]
	if fingerprint == _stage_fingerprint and stage_list.get_child_count() > 0:
		return
	_stage_fingerprint = fingerprint
	for child in stage_list.get_children():
		child.queue_free()
	for stage in _session.adventure.stages:
		var reason := CombatRules.enter_reason(
			_session.state,
			_session.config,
			stage,
			stats,
			true
		)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, MainTheme.H_ROW)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", MainTheme.SIZE_CAPTION)
		var nxt := _session.next_stage()
		if stage.id == _session.state.current_stage_id:
			button.text = "%s · %s  ·  挂机中" % [
				stage.display_name,
				StageLayer.display_name(_session.state.current_layer()),
			]
			button.disabled = true
		elif reason.is_empty():
			button.text = "%s · %s" % [stage.display_name, _sight_status(stage)]
			var stage_id := stage.id
			button.pressed.connect(func() -> void:
				_show_hint(_session.select_stage(stage_id))
			)
		elif nxt != null and stage.id == nxt.id:
			if reason.contains("境界"):
				button.text = "%s  ·  境界不足" % stage.display_name
			elif reason.contains("缺"):
				button.text = "%s  ·  %s" % [stage.display_name, reason.get_slice("，", 0)]
			elif reason.contains("战力"):
				button.text = "%s  ·  需战力 %.0f" % [stage.display_name, stage.min_power]
			else:
				button.text = "%s  ·  未开" % stage.display_name
			button.disabled = true
		else:
			button.text = "%s  ·  未至" % stage.display_name
			button.disabled = true
		_style_secondary_button(button)
		if button.disabled:
			button.add_theme_color_override("font_disabled_color", MainTheme.MUTED)
		stage_list.add_child(button)


func _install_bag_board() -> void:
	equip_summary.visible = false
	inspect_panel.visible = false
	doll_board.add_theme_stylebox_override("panel", MainTheme.inner_panel())
	for child in doll_board.get_children():
		child.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	doll_board.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(grid)
	var figure := PanelContainer.new()
	figure.custom_minimum_size = Vector2(MainTheme.H_SLOT + 16, MainTheme.H_SLOT + 28)
	figure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	figure.size_flags_vertical = Control.SIZE_EXPAND_FILL
	figure.add_theme_stylebox_override("panel", MainTheme.seal_ring())
	_figure_label = Label.new()
	_figure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_figure_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_figure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_figure_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_figure_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	figure.add_child(_figure_label)
	_slot_buttons.clear()
	var layout: Array = [
		["", EquipSlot.HELMET, ""],
		[EquipSlot.WEAPON, "figure", EquipSlot.ACCESSORY],
		["", EquipSlot.CLOTHES, ""],
		["", EquipSlot.SHOES, ""],
	]
	for row in layout:
		for cell in row:
			var key := str(cell)
			if key.is_empty():
				var pad := Control.new()
				pad.custom_minimum_size = Vector2(MainTheme.H_SLOT, MainTheme.H_SLOT)
				pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grid.add_child(pad)
			elif key == "figure":
				grid.add_child(figure)
			else:
				var button := _make_slot_button(key)
				_slot_buttons[key] = button
				grid.add_child(button)
	for child in bag_tabs.get_children():
		child.queue_free()
	for entry in [
		["all", "全部"],
		[ItemDef.KIND_EQUIPMENT, "装备"],
		[ItemDef.KIND_PILL, "丹药"],
		[ItemDef.KIND_MATERIAL, "材料"],
		[ItemDef.KIND_SKILL_BOOK, "功法"],
	]:
		var tab := Button.new()
		tab.text = str(entry[1])
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, MainTheme.H_ACTION)
		tab.add_theme_font_size_override("font_size", MainTheme.SIZE_UI)
		var tab_id := str(entry[0])
		tab.pressed.connect(func() -> void:
			_bag_tab = tab_id
			_bag_fingerprint = ""
			_refresh_bag()
		)
		bag_tabs.add_child(tab)
	inspect_layer.gui_input.connect(_on_inspect_layer_gui_input)
	inspect_card.mouse_filter = Control.MOUSE_FILTER_STOP


func _make_slot_button(slot: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(MainTheme.H_SLOT, MainTheme.H_SLOT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", MainTheme.SIZE_MICRO)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(func() -> void:
		_open_slot(slot)
	)
	return button


func _refresh_doll() -> void:
	var realm := _session.current_realm()
	if _figure_label != null:
		_figure_label.text = "%s\n修士" % (realm.display_name if realm != null else "凡人")
		MainTheme.stamp_label(_figure_label, MainTheme.SIZE_CAPTION, MainTheme.GOLD)
	for slot in EquipSlot.ORDER:
		var button: Button = _slot_buttons.get(slot, null)
		if button == null:
			continue
		var uid := _session.state.equipped.uid_for(slot)
		var stack := InventoryRules.find_stack(_session.state, uid)
		var item := _session.item_def(stack.item_id) if stack != null else null
		if item == null:
			button.text = EquipSlot.display_name(slot)
			_style_secondary_button(button)
			button.add_theme_color_override("font_color", MainTheme.MUTED)
		else:
			button.text = item.display_name
			button.add_theme_stylebox_override(
				"normal",
				MainTheme._box(Color(0.1, 0.12, 0.1, 1), QualityId.color(item.quality), 2, 16, 0, 8, 8)
			)
			button.add_theme_color_override("font_color", QualityId.color(item.quality))


func _refresh_bag_tabs() -> void:
	var wanted := _bag_tab
	for tab in bag_tabs.get_children():
		var button := tab as Button
		if button == null:
			continue
		var id := "all"
		match button.text:
			"装备":
				id = ItemDef.KIND_EQUIPMENT
			"丹药":
				id = ItemDef.KIND_PILL
			"材料":
				id = ItemDef.KIND_MATERIAL
			"功法":
				id = ItemDef.KIND_SKILL_BOOK
		if id == wanted:
			button.remove_theme_stylebox_override("normal")
			button.remove_theme_stylebox_override("hover")
			button.remove_theme_stylebox_override("pressed")
			button.add_theme_color_override("font_color", Color(0.12, 0.1, 0.06, 1))
		else:
			_style_secondary_button(button)


func _make_bag_cell(stack: ItemStack) -> Control:
	var item := _session.item_def(stack.item_id)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, MainTheme.H_CELL)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", MainTheme.SIZE_CAPTION)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.text = _bag_cell_caption(item, stack)
	var quality := item.quality if item != null else QualityId.WHITE
	_style_secondary_button(button)
	button.add_theme_color_override("font_color", QualityId.color(quality))
	button.add_theme_stylebox_override(
		"normal",
		MainTheme._box(Color(0.07, 0.1, 0.09, 0.95), QualityId.color(quality), 1, 14, 0, 8, 8)
	)
	var uid := stack.uid
	button.pressed.connect(func() -> void:
		_open_inspect(uid)
	)
	return button


func _bag_cell_caption(item: ItemDef, stack: ItemStack) -> String:
	var name := stack.item_id if item == null else item.display_name
	if item != null and item.is_skill_book() and name.ends_with("残页"):
		name = name.substr(0, name.length() - 2)
	if name.length() > 5:
		name = name.substr(0, 4) + "…"
	if stack.count > 1:
		name = "%s×%d" % [name, stack.count]
	if stack.locked:
		name = "锁\n%s" % name
	return name


func _open_slot(slot: String) -> void:
	var uid := _session.state.equipped.uid_for(slot)
	if uid > 0 and InventoryRules.find_stack(_session.state, uid) != null:
		_open_inspect(uid)
		return
	_inspect_empty_slot = slot
	_selected_bag_uid = 0
	inspect_layer.visible = true
	_fill_inspect_card()


func _open_inspect(uid: int) -> void:
	_selected_bag_uid = uid
	_inspect_empty_slot = ""
	inspect_layer.visible = true
	_fill_inspect_card()


func _close_inspect() -> void:
	inspect_layer.visible = false
	_inspect_empty_slot = ""


func _on_inspect_layer_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_inspect()


func _fill_inspect_card() -> void:
	for child in inspect_card.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	inspect_card.add_child(box)
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	if not _inspect_empty_slot.is_empty():
		title.text = EquipSlot.display_name(_inspect_empty_slot)
		MainTheme.stamp_label(title, MainTheme.SIZE_HERO, MainTheme.GOLD)
		body.text = "此槽空着。\n去下方行囊选一件%s。" % EquipSlot.display_name(_inspect_empty_slot)
		MainTheme.stamp_label(body, MainTheme.SIZE_BODY, MainTheme.MUTED)
		box.add_child(_action_button("关闭", _close_inspect))
		return
	var stack := InventoryRules.find_stack(_session.state, _selected_bag_uid)
	if stack == null:
		title.text = "物品"
		MainTheme.stamp_label(title, MainTheme.SIZE_HERO, MainTheme.IVORY)
		body.text = "这件东西已经不在了。"
		MainTheme.stamp_label(body, MainTheme.SIZE_BODY, MainTheme.MUTED)
		box.add_child(_action_button("关闭", _close_inspect))
		return
	var item := _session.item_def(stack.item_id)
	title.text = item.display_name if item != null else stack.item_id
	var title_color := QualityId.color(item.quality) if item != null else MainTheme.IVORY
	MainTheme.stamp_label(title, MainTheme.SIZE_HERO, title_color)
	body.text = InventoryRules.inspect_text(
		_session.state,
		_session.config,
		_session.adventure,
		stack
	)
	MainTheme.stamp_label(body, MainTheme.SIZE_CAPTION, MainTheme.IVORY)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var extra := HBoxContainer.new()
	extra.add_theme_constant_override("separation", 8)
	if item != null and item.is_equipment():
		if _session.state.equipped.contains_uid(stack.uid):
			row.add_child(_action_button("卸下", func() -> void:
				_session.unequip_slot(item.slot)
				_close_inspect()
			))
		else:
			row.add_child(_action_button("穿上", func() -> void:
				_show_hint(_session.equip_item(stack.uid))
				_close_inspect()
			))
			if InventoryRules.find_merge_partner(_session.state, stack.uid) != null:
				extra.add_child(_action_button("合并", func() -> void:
					_show_hint(_session.merge_item(stack.uid))
					_fill_inspect_card()
				))
			if not stack.tempered:
				extra.add_child(_action_button("温养", func() -> void:
					_show_hint(_session.temper_item(stack.uid))
					_fill_inspect_card()
				))
	if item != null and item.is_skill_book():
		var skill := _session.adventure.skill_by_id(item.skill_id) if _session.adventure != null else null
		var mastery := _session.state.skill_rank_of(item.skill_id) if skill != null else 0
		var learn_label := "小成" if mastery == 1 else "参悟"
		row.add_child(_action_button(learn_label, func() -> void:
			_show_hint(_session.learn_skill_from(stack.uid))
			_close_inspect()
		))
	if item != null and item.is_pill():
		row.add_child(_action_button("服用", func() -> void:
			_show_hint(_session.consume_pill(stack.uid))
			_close_inspect()
		))
	row.add_child(_action_button("上锁" if not stack.locked else "解锁", func() -> void:
		_session.toggle_lock(stack.uid)
		_fill_inspect_card()
	))
	row.add_child(_action_button("丢弃", func() -> void:
		_show_hint(_session.discard_item(stack.uid))
		_close_inspect()
	))
	box.add_child(row)
	if extra.get_child_count() > 0:
		box.add_child(extra)
	box.add_child(_action_button("关闭", _close_inspect))


func _install_layer_row() -> void:
	for child in layer_row.get_children():
		child.queue_free()
	for layer: int in [StageLayer.OUTER, StageLayer.INNER, StageLayer.BOSS]:
		var chosen: int = layer
		var button := _action_button(StageLayer.display_name(chosen), func() -> void:
			_show_hint(_session.select_layer(chosen))
		)
		button.set_meta("layer", chosen)
		layer_row.add_child(button)


func _refresh_layer_row() -> void:
	if _session.state == null:
		return
	var stage := _session.current_stage()
	var current := _session.state.current_layer()
	for child in layer_row.get_children():
		var button := child as Button
		if button == null:
			continue
		var layer := int(button.get_meta("layer", StageLayer.OUTER))
		var reason := ""
		if stage != null:
			reason = CombatRules.layer_reason(_session.state, stage, layer)
		button.disabled = not reason.is_empty()
		if layer == current:
			button.text = "%s · 当前" % StageLayer.display_name(layer)
		elif reason.is_empty():
			button.text = StageLayer.display_name(layer)
		elif layer == StageLayer.INNER:
			button.text = "深处未开"
		else:
			button.text = "头目未开"
		_style_secondary_button(button)
		if button.disabled:
			button.add_theme_color_override("font_disabled_color", MainTheme.MUTED)


func _refresh_sight() -> void:
	if _session.state == null or _session.adventure == null:
		return
	var lines: PackedStringArray = PackedStringArray(["见闻"])
	for stage in _session.adventure.stages:
		if (
			not _session.state.unlocked_stage_ids.has(stage.id)
			and stage.id != _session.state.current_stage_id
		):
			continue
		var outer := _session.state.kills_of(stage.id, StageLayer.OUTER)
		var inner := _session.state.kills_of(stage.id, StageLayer.INNER)
		var boss := _session.state.kills_of(stage.id, StageLayer.BOSS)
		lines.append("%s · %s  斩%d/%d/%d" % [
			stage.display_name,
			_sight_status(stage),
			outer,
			inner,
			boss,
		])
	sight_label.text = "\n".join(lines)
	MainTheme.stamp_label(sight_label, MainTheme.SIZE_CAPTION, MainTheme.MUTED)


func _sight_status(stage: StageDef) -> String:
	if _session.state == null or stage == null:
		return "外围"
	var outer := _session.state.kills_of(stage.id, StageLayer.OUTER)
	var inner := _session.state.kills_of(stage.id, StageLayer.INNER)
	var boss := _session.state.kills_of(stage.id, StageLayer.BOSS)
	if boss > 0:
		return "头目已见"
	if inner >= StageLayer.BOSS_KILLS:
		return "头目可至"
	if outer >= StageLayer.INNER_KILLS:
		return "深处"
	if inner > 0:
		return "深处未满"
	return "外围"


func _bag_progress_stamp() -> String:
	var parts := PackedStringArray()
	if _session.state == null:
		return ""
	for stack in _session.state.inventory:
		parts.append("%d:%d:%s" % [stack.uid, stack.merge_level, stack.tempered])
	return ",".join(parts)


func _has_book_for(skill_id: String) -> bool:
	for stack in _session.state.inventory:
		var item := _session.item_def(stack.item_id)
		if item != null and item.skill_id == skill_id:
			return true
	return false


func _action_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, MainTheme.H_ACTION)
	button.add_theme_font_size_override("font_size", MainTheme.SIZE_UI)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_secondary_button(button)
	button.pressed.connect(callback)
	return button


func _show_hint(message: String) -> void:
	if message.is_empty():
		return
	stage_hint.text = message
	export_label.text = message


func _on_challenge_pressed() -> void:
	var reason := _session.challenge_next()
	if not reason.is_empty():
		stage_hint.text = reason


func _on_bag_policy_pressed() -> void:
	if _session.state.settings.bag_full_policy == GameSettings.POLICY_SKIP:
		_session.set_bag_full_policy(GameSettings.POLICY_DISCARD_LOWEST)
	else:
		_session.set_bag_full_policy(GameSettings.POLICY_SKIP)


func _on_export_pressed() -> void:
	var text := _session.export_save_text()
	if text.is_empty():
		export_label.text = "还没有可导出的存档。"
		return
	export_label.text = "已读取本地存档，共 %d 字。路径：user://saves/cultivation.json" % text.length()
	DisplayServer.clipboard_set(text)


func _on_breakthrough_pressed() -> void:
	_session.try_breakthrough()


func _on_breakthrough_succeeded(from_name: String, to_name: String, new_rate: float) -> void:
	breakthrough_banner.text = BreakthroughCopy.banner(from_name, to_name, new_rate)
	breakthrough_banner.visible = true
	offline_label.text = ""
	_play_breakthrough_flash()
	_refresh_all()
	_banner_generation += 1
	var generation := _banner_generation
	get_tree().create_timer(3.6).timeout.connect(func() -> void:
		if generation == _banner_generation:
			breakthrough_banner.visible = false
	)


func _style_secondary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", MainTheme.ghost_button())
	button.add_theme_stylebox_override("hover", MainTheme._box(Color(0.14, 0.16, 0.13, 1), MainTheme.GOLD, 1, 20, 0, 14, 12))
	button.add_theme_stylebox_override("pressed", MainTheme._box(Color(0.1, 0.12, 0.1, 1), Color(0.5, 0.42, 0.22, 1), 1, 20, 0, 14, 12))
	button.add_theme_color_override("font_color", MainTheme.GOLD)
	button.add_theme_color_override("font_hover_color", MainTheme.IVORY)
	button.add_theme_color_override("font_pressed_color", MainTheme.GOLD)


func _set_ready_pulse(enabled: bool) -> void:
	if enabled:
		if _ready_pulse != null:
			return
		_ready_pulse = create_tween()
		_ready_pulse.set_loops()
		_ready_pulse.tween_property(breakthrough_button, "modulate", Color(1.12, 1.08, 0.92, 1), 0.7)
		_ready_pulse.tween_property(breakthrough_button, "modulate", Color.WHITE, 0.7)
		return
	if _ready_pulse != null:
		_ready_pulse.kill()
		_ready_pulse = null
	breakthrough_button.modulate = Color.WHITE


func _start_seal_pulse() -> void:
	var pulse := create_tween()
	pulse.set_loops()
	pulse.tween_property(seal_ring, "modulate:a", 0.55, 1.8).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(seal_ring, "modulate:a", 1.0, 1.8).set_trans(Tween.TRANS_SINE)


func _play_breakthrough_flash() -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	flash.modulate = Color(MainTheme.GOLD.r, MainTheme.GOLD.g, MainTheme.GOLD.b, 0.0)
	realm_label.modulate = MainTheme.GOLD
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(flash, "modulate:a", 0.28, 0.12)
	_banner_tween.tween_property(realm_label, "scale", Vector2(1.08, 1.08), 0.12)
	_banner_tween.chain()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(flash, "modulate:a", 0.0, 0.45)
	_banner_tween.tween_property(realm_label, "scale", Vector2.ONE, 0.35)
	_banner_tween.tween_property(realm_label, "modulate", MainTheme.JADE, 0.45)


func _on_offline_settled(result: SettlementResult) -> void:
	offline_label.text = OfflineCopy.banner(result)
	var message := OfflineCopy.dialog(result, _session.config.offline_cap_seconds)
	if message.is_empty():
		_refresh_all()
		return
	offline_dialog.dialog_text = message
	offline_dialog.popup_centered(Vector2i(780, 520))
	_refresh_all()


func _maybe_check_update() -> void:
	if not _update_check_pending or offline_dialog.visible:
		return
	_update_check_pending = false
	update_service.check_for_update(true)


func _on_status_changed(message: String) -> void:
	status_label.text = message
	status_label.visible = not message.strip_edges().is_empty()


func _on_update_available(info: Dictionary) -> void:
	check_button.disabled = false
	var notes := str(info.get("release_notes", ""))
	if notes.is_empty():
		notes = "包含新的可玩内容。"
	update_dialog.dialog_text = "新版本：%s\n\n%s\n\n是否立即下载？" % [
		str(info.get("version", "")),
		notes,
	]
	update_dialog.popup_centered(Vector2i(780, 520))


func _on_no_update(_version: String) -> void:
	check_button.disabled = false


func _on_download_progress_changed(progress: float) -> void:
	check_button.disabled = true
	download_progress.visible = true
	download_progress.value = progress * 100.0


func _on_download_ready(_path: String) -> void:
	check_button.disabled = false
	install_button.visible = true
	update_service.install_downloaded_update()


func _on_update_failed(_message: String) -> void:
	check_button.disabled = false


func _load_or_create_data_marker() -> String:
	if FileAccess.file_exists(DATA_MARKER_PATH):
		var saved_marker := FileAccess.get_file_as_string(DATA_MARKER_PATH).strip_edges()
		var shown := InstallMarker.display_text(saved_marker)
		if not shown.is_empty():
			return shown
	var marker := "首次安装 %s" % update_service.get_current_version()
	var file := FileAccess.open(DATA_MARKER_PATH, FileAccess.WRITE)
	if file == null:
		return "无法写入"
	file.store_string(marker)
	return marker
