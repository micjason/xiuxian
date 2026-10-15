class_name BattlePage
extends VBoxContainer
## 首领战界面（设计稿 07）：关卡横幅、双方气血条、战场、实时战报、自动战斗/战斗速度、大招圆钮。
## 战斗画面由 BossFight 在本地预演（公式与服务器一致）；玩家点大招的时间记下来，战斗结束后随
## 挑战请求以 ultTaps 上报，胜负和掉落以服务器返回为准。
## 流程：就绪（点「开始挑战」，行囊已满时先弹提示）→ 进行中（可点大招）→ 提交 → 结算面板。

signal start_blocked(used: int, capacity: int)
signal submit_requested(stage_slug: String, taps: Array)
signal back_requested
signal retry_requested(stage_slug: String)

enum Phase { READY, RUNNING, SUBMITTING, RESULT }

var phase := Phase.READY
var fight: BossFight
var speed := 1.0
var stage_slug := ""

var _state: Dictionary = {}
var _content: Dictionary = {}
var _stage: Dictionary = {}
var _gate: Dictionary = {}
var _boss_name := ""
var _ult_name := "大招"
var _clock := 0.0
var _subtitle: Label
var _title_holder: Control
var _me_bar_host: Control
var _boss_bar_host: Control
var _me_name: Label
var _boss_name_label: Label
var _boss_meta: Label
var _arena: Control
var _boss_art: TextureRect
var _hero_art: TextureRect
var _float_layer: Control
var _report: BattleReport
var _ult: UltButton
var _ult_note: Label
var _speed_buttons: Dictionary = {}
var _start_button: Button
var _result_panel: PanelContainer
var _result_body: VBoxContainer
var _report_lines := 0
var _last_time_text := ""


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SP_1)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_title_holder = UiKit.page_title("")
	add_child(_title_holder)
	_subtitle = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_subtitle)
	add_child(_build_hp_row())
	_build_arena()
	add_child(_build_report_panel())
	add_child(_build_controls())


func _build_hp_row() -> Control:
	var row := UiKit.hbox(UiTokens.SP_1)
	row.custom_minimum_size = Vector2(0, 150)
	var left := _hp_card(true)
	var right := _hp_card(false)
	row.add_child(left)
	row.add_child(right)
	return row


func _hp_card(mine: bool) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", ArtLib.nine("panel_card"))
	var column := UiKit.vbox(2)
	card.add_child(column)
	var head := UiKit.hbox(UiTokens.SP_1)
	column.add_child(head)
	var name_label := UiKit.label("", UiTokens.FS_CAPTION, UiTokens.TEXT)
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var host := Control.new()
	host.custom_minimum_size = Vector2(0, 52)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(host)
	if mine:
		_me_name = name_label
		_me_bar_host = host
	else:
		_boss_name_label = name_label
		_boss_bar_host = host
		_boss_meta = UiKit.label("", UiTokens.FS_MICRO, UiTokens.WARNING, HORIZONTAL_ALIGNMENT_RIGHT)
		head.add_child(_boss_meta)
	return card


func _build_arena() -> void:
	_arena = Control.new()
	_arena.name = "Arena"
	_arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_arena.custom_minimum_size = Vector2(0, 360)
	_arena.clip_contents = true
	_arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_arena)
	_hero_art = UiKit.icon("avatar_meditate", 230, UiTokens.GOLD_HOVER)
	_hero_art.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_hero_art.offset_left = 30
	_hero_art.offset_right = 270
	_hero_art.offset_top = -100
	_hero_art.offset_bottom = 130
	_arena.add_child(_hero_art)
	_boss_art = TextureRect.new()
	_boss_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_boss_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_boss_art.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_boss_art.offset_left = -480
	_boss_art.offset_right = -20
	_boss_art.offset_top = -190
	_boss_art.offset_bottom = 190
	_boss_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(_boss_art)
	_float_layer = Control.new()
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(_float_layer)
	_start_button = UiKit.cta_button("开始挑战", "限时 45 秒", MainTheme.VAR_PRIMARY, 150)
	_start_button.name = "StartButton"
	_start_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_start_button.offset_left = -270
	_start_button.offset_right = 270
	_start_button.offset_top = -170
	_start_button.offset_bottom = -20
	_start_button.pressed.connect(_on_start)
	_arena.add_child(_start_button)
	_result_panel = PanelContainer.new()
	_result_panel.name = "ResultPanel"
	_result_panel.visible = false
	_result_panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_popup"))
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.offset_left = 20
	_result_panel.offset_right = -20
	_result_panel.offset_top = 6
	_result_panel.offset_bottom = -6
	_arena.add_child(_result_panel)
	_result_body = UiKit.vbox(UiTokens.SP_1)
	_result_panel.add_child(_result_body)


func _build_report_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "ReportPanel"
	panel.custom_minimum_size = Vector2(0, 250)
	panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_inset"))
	var column := UiKit.vbox(2)
	panel.add_child(column)
	column.add_child(UiKit.label("战报", UiTokens.FS_MICRO, UiTokens.GOLD))
	_report = BattleReport.new()
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_report)
	return panel


func _build_controls() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_card"))
	var row := UiKit.hbox(UiTokens.SP_2)
	panel.add_child(row)
	var left := UiKit.vbox(UiTokens.SP_1)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(left)
	# 自动战斗：服务器的大招自动释放始终生效，这里只显示状态，不可关闭。
	var auto_row := UiKit.hbox(UiTokens.SP_1)
	auto_row.name = "AutoRow"
	auto_row.add_child(UiKit.label("自动战斗", UiTokens.FS_CAPTION, UiTokens.TEXT))
	var auto_state := UiKit.label("已开启", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	auto_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_row.add_child(auto_state)
	var switch := UiKit.icon_from(ArtLib.switch_tex(true), 96, Color.WHITE)
	switch.custom_minimum_size = Vector2(128, 64)
	switch.tooltip_text = "战斗自动进行，大招冷却完毕后自动释放（始终开启）"
	auto_row.add_child(switch)
	left.add_child(auto_row)
	var speed_row := UiKit.hbox(UiTokens.SP_1)
	speed_row.name = "SpeedRow"
	speed_row.add_child(UiKit.label("战斗速度", UiTokens.FS_CAPTION, UiTokens.TEXT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(spacer)
	for value in [1.0, 2.0]:
		var button := UiKit.button("x%d" % int(value), MainTheme.VAR_CHOICE, 80)
		button.custom_minimum_size = Vector2(110, 80)
		button.pressed.connect(_set_speed.bind(value))
		speed_row.add_child(button)
		_speed_buttons[value] = button
	left.add_child(speed_row)
	var right := UiKit.vbox(UiTokens.SP_1)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	_ult = UltButton.new()
	_ult.name = "UltButton"
	_ult.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ult.tapped.connect(_on_ult_tapped)
	right.add_child(_ult)
	var note_panel := PanelContainer.new()
	note_panel.add_theme_stylebox_override("panel", ArtLib.nine("chip"))
	_ult_note = UiKit.label("冷却完毕自动释放", UiTokens.FS_MICRO, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	note_panel.add_child(_ult_note)
	right.add_child(note_panel)
	_set_speed(1.0)
	return panel


## 打开某个关卡的首领战。gate = BagModel.challenge_gate(...) 的结果。
func open_stage(state: Dictionary, content: Dictionary, stage: Dictionary, gate: Dictionary, my_realm_name: String) -> void:
	_state = state
	_content = content
	_stage = stage
	_gate = gate
	stage_slug = str(stage.get("slug", ""))
	var bosses: Array = stage.get("bosses", [])
	var boss: Dictionary = bosses[0] if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY else {}
	_boss_name = str(boss.get("name", "首领"))
	var ult_cfg: Variant = state.get("ult", {})
	_ult_name = str((ult_cfg as Dictionary).get("name", "大招")) if typeof(ult_cfg) == TYPE_DICTIONARY and not (ult_cfg as Dictionary).is_empty() else "大招"
	fight = BossFight.from_state(state, content, stage)
	phase = Phase.READY
	_clock = 0.0
	_report_lines = 0
	_report.clear()
	_clear_floats()
	_result_panel.visible = false
	_start_button.visible = true
	_start_button.disabled = fight == null
	_find_title().text = "%s  首领战" % str(stage.get("displayName", ""))
	var limit := fight.time_limit if fight != null else 45.0
	UiKit.set_cta(_start_button, "开始挑战", "限时 %d 秒" % int(limit))
	_me_name.text = "我 · %s" % my_realm_name
	_boss_name_label.text = _boss_name
	_boss_meta.text = "首领  推荐战力 %d" % int(stage.get("recommendedPower", 0)) if int(stage.get("recommendedPower", 0)) > 0 else "首领"
	_boss_art.texture = ArtLib.icon(ArtLib.boss_icon_name(_boss_name))
	_boss_art.modulate = UiTokens.rarity_color(4).lightened(0.25)
	_refresh_bars()
	_refresh_ult()
	_refresh_time()
	if fight == null:
		_subtitle.text = "这个关卡还没有首领"
		return
	_append_info("你（气血 %d）对阵 %s（气血 %d）" % [BagModel.shown(fight.player_max_hp), _boss_name, BagModel.shown(fight.boss_max_hp)])
	if fight.has_ult():
		_append_info("「%s」%d 秒后冷却完毕，冷却完毕后 %d 秒内可点击释放，不点则自动释放" % [_ult_name, int(round(float(fight.ult.get("firstCooldownSeconds", 8.0)))), int(round(fight.auto_window()))])


func _find_title() -> Label:
	return _title_holder.find_child("Title", true, false) as Label


func is_running() -> bool:
	return phase == Phase.RUNNING


func _set_speed(value: float) -> void:
	speed = value
	for key in _speed_buttons:
		var on := is_equal_approx(float(key), value)
		(_speed_buttons[key] as Button).theme_type_variation = MainTheme.VAR_CHOICE_SELECTED if on else MainTheme.VAR_CHOICE


func _on_start() -> void:
	if fight == null or phase != Phase.READY:
		return
	if bool(_gate.get("blocked", false)):
		start_blocked.emit(int(_gate.get("used", 0)), int(_gate.get("capacity", 0)))
		return
	phase = Phase.RUNNING
	_clock = 0.0
	_start_button.visible = false
	_append_info("战斗开始")
	if bool(_gate.get("will_free", false)):
		_append_info("背包已满，开战前会自动分解一件未强化的白/绿装备腾出一格")


func _on_ult_tapped() -> void:
	if phase != Phase.RUNNING or fight == null:
		return
	if fight.tap():
		_consume_events()
		_refresh_ult()


func _process(delta: float) -> void:
	if phase != Phase.RUNNING or fight == null or not is_visible_in_tree():
		return
	_clock += delta * speed
	fight.advance_to(_clock)
	_consume_events()
	_refresh_ult()
	_refresh_time()
	if fight.finished:
		phase = Phase.SUBMITTING
		_subtitle.text = "战斗结束，正在结算……"
		_ult.enabled = false
		submit_requested.emit(stage_slug, fight.upload_taps())


## 测试 / 脚本：直接把时钟推进 seconds 秒（不依赖帧）。
func step(seconds: float) -> void:
	if phase != Phase.RUNNING or fight == null:
		return
	_clock += seconds
	fight.advance_to(_clock)
	_consume_events()
	_refresh_ult()
	_refresh_time()
	if fight.finished:
		phase = Phase.SUBMITTING
		_ult.enabled = false
		submit_requested.emit(stage_slug, fight.upload_taps())


func _consume_events() -> void:
	var events := fight.take_events()
	if events.is_empty():
		return
	for event in events:
		var line := BattleReportBuilder.live_line(event, _boss_name, _ult_name)
		_append_report(int(line.kind), str(line.text))
		_float_damage(event)
	_refresh_bars()


func _append_report(kind: int, text: String) -> void:
	_report.add_line(kind as BattleReport.Kind, text, 0)
	_report_lines += 1


func _append_info(text: String) -> void:
	_report.add_line(BattleReport.Kind.PLAIN, text, 0)


func _refresh_bars() -> void:
	if fight == null:
		_set_bar(_me_bar_host, 1.0, "bar_fill_jade", "气血 --")
		_set_bar(_boss_bar_host, 1.0, "bar_fill_cin", "气血 --")
		return
	_set_bar(_me_bar_host, fight.player_hp / maxf(fight.player_max_hp, 1.0), "bar_fill_jade", "气血 %d / %d" % [BagModel.shown(maxf(fight.player_hp, 0.0)), BagModel.shown(fight.player_max_hp)])
	_set_bar(_boss_bar_host, fight.boss_hp / maxf(fight.boss_max_hp, 1.0), "bar_fill_cin", "气血 %d / %d" % [BagModel.shown(maxf(fight.boss_hp, 0.0)), BagModel.shown(fight.boss_max_hp)])


func _set_bar(host: Control, ratio: float, fill: String, text: String) -> void:
	UiKit.clear(host)
	var bar := UiKit.ratio_bar(clampf(ratio, 0.0, 1.0), fill, 52)
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bar)
	var label := UiKit.label(text, UiTokens.FS_MICRO, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(label)


func _refresh_time() -> void:
	if fight == null:
		return
	var used := minf(fight.t if not fight.finished else fight.duration, fight.time_limit)
	var text := "首领战 · 限时 %d 秒 · 已用 %s" % [int(fight.time_limit), OfflineView.clock_text(int(used)).substr(3)]
	if text != _last_time_text and phase != Phase.SUBMITTING and phase != Phase.RESULT:
		_last_time_text = text
		_subtitle.text = text


func _refresh_ult() -> void:
	if fight == null or not fight.has_ult():
		_ult.title = "大招"
		_ult.ratio = 0.0
		_ult.ready_now = false
		_ult.sub_text = "未学会"
		_ult.enabled = false
		_ult_note.text = "本境界还没有大招"
		return
	_ult.title = _ult_name if _ult_name.length() <= 2 else "大招"
	_ult.enabled = phase == Phase.RUNNING
	_ult.ratio = fight.ult_progress()
	_ult.ready_now = fight.ult_ready()
	if phase == Phase.READY:
		_ult.sub_text = "%.1fs" % float(fight.ult.get("firstCooldownSeconds", 8.0))
		_ult_note.text = "冷却完毕自动释放"
	elif fight.ult_ready():
		_ult.sub_text = "点击释放"
		_ult_note.text = "冷却完毕，%.1f 秒后自动释放" % fight.ult_auto_left()
	else:
		_ult.sub_text = "%.1fs" % fight.ult_cooldown_left()
		_ult_note.text = "冷却完毕自动释放"


func _float_damage(event: Dictionary) -> void:
	var boss_side := str(event.get("side", "")) == "boss"
	var ult := str(event.get("kind", "")) == "ult"
	var amount := BagModel.shown(float(event.get("damage", 0)))
	var label := UiKit.label("-%d" % amount, UiTokens.FS_H1 if ult else UiTokens.FS_BODY_L, UiTokens.DANGER if boss_side else (UiTokens.REPORT_CRIT if ult else UiTokens.REPORT_DAMAGE_DEALT), HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_font_override("font", ArtLib.title_font())
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 10)
	label.set_anchors_preset(Control.PRESET_CENTER_LEFT if boss_side else Control.PRESET_CENTER_RIGHT)
	var x := 80.0 if boss_side else -380.0
	var y := -150.0 + float(randi() % 120)
	label.offset_left = x
	label.offset_right = x + 280.0
	label.offset_top = y
	label.offset_bottom = y + 80.0
	_float_layer.add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "offset_top", y - 90.0, 0.9)
	tween.tween_property(label, "offset_bottom", y - 10.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)
	while _float_layer.get_child_count() > 14:
		_float_layer.get_child(0).queue_free()
		break


func _clear_floats() -> void:
	UiKit.clear(_float_layer)


## 提交失败（网络/服务器拒绝）：回到就绪，让玩家可以重来。
func show_submit_error(message: String) -> void:
	phase = Phase.READY
	_start_button.visible = true
	_start_button.disabled = false
	_subtitle.text = message
	_report.add_line(BattleReport.Kind.LOSE, "结算失败：%s" % message, 0)


## 服务器结算返回后显示结果：完整战报换成服务器的版本，再弹出结算面板。
func show_result(result: Dictionary, name_of: Callable) -> void:
	phase = Phase.RESULT
	var battle: Dictionary = result.get("battle", {}) if typeof(result.get("battle", null)) == TYPE_DICTIONARY else {}
	var lines := BattleReportBuilder.build(battle, _boss_name, BagModel.shown(fight.player_max_hp) if fight != null else 0, BagModel.shown(fight.boss_max_hp) if fight != null else 0, _ult_name)
	BattleReportBuilder.render(_report, lines)
	var view := BattleResultView.build(result, _boss_name, name_of)
	_last_view = view
	_subtitle.text = str(view.reason)
	UiKit.clear(_result_body)
	var title := UiKit.label(str(view.title), UiTokens.FS_H1, UiTokens.SUCCESS if bool(view.win) else UiTokens.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "ResultTitle"
	title.add_theme_font_override("font", ArtLib.title_font())
	_result_body.add_child(title)
	_result_body.add_child(UiKit.label(str(view.reason), UiTokens.FS_CAPTION, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_result_body.add_child(UiKit.divider())
	for text in view.lines:
		_result_body.add_child(UiKit.label(str(text), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if not (view.loot as Array).is_empty():
		_result_body.add_child(UiKit.label("获得", UiTokens.FS_MICRO, UiTokens.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		for row in view.loot:
			var color := UiTokens.rarity_color({"white": 0, "green": 1, "blue": 2, "purple": 3, "orange": 4, "red": 5}.get(str(row.quality), 1) as int).lightened(0.15)
			var loot_label := UiKit.label(str(row.text), UiTokens.FS_CAPTION, color, HORIZONTAL_ALIGNMENT_CENTER)
			loot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_result_body.add_child(loot_label)
	elif bool(view.win):
		_result_body.add_child(UiKit.label("这次没有掉落", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	for note in view.notes:
		var note_label := UiKit.label(str(note), UiTokens.FS_MICRO, UiTokens.WARNING, HORIZONTAL_ALIGNMENT_CENTER)
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_result_body.add_child(note_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_body.add_child(spacer)
	var buttons := UiKit.hbox(UiTokens.SP_2)
	var back := UiKit.button("返回", MainTheme.VAR_SECONDARY, UiTokens.H_CTA)
	back.name = "BackButton"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(back)
	var again := UiKit.button("再来一次", MainTheme.VAR_PRIMARY, UiTokens.H_CTA)
	again.name = "RetryButton"
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(func() -> void: retry_requested.emit(stage_slug))
	buttons.add_child(again)
	_result_body.add_child(buttons)
	_result_panel.visible = true
	_ult.enabled = false


var _last_view: Dictionary = {}


func last_view() -> Dictionary:
	return _last_view


func report_text() -> String:
	return _report.get_parsed_text()
