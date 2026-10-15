class_name BreakthroughPage
extends VBoxContainer
## 境界突破流程界面（设计稿 09 / 09b）：当前 → 目标 → 下一境界三个节点、战力提升环与成功率环、
## 突破条件（修为、必须击败的首领）、突破后的属性和总战力、「开始突破」金色大按钮。
## 条件没满足时按钮灰化（09），全满足时亮起（09b）。突破必定成功，超出的修为保留。
## 属性和战力的「突破后」数值来自服务器 breakthrough.preview，这里不自己算。

signal start_requested
signal goto_stage_requested(stage_slug: String)

var _view: Dictionary = {}
var _body: VBoxContainer
var _button: Button
var _hint: Label
var _goto: Button


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SP_1)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UiKit.page_title("境界突破"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_body = UiKit.vbox(UiTokens.SP_1)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_button = UiKit.cta_button("开始突破", "", MainTheme.VAR_PRIMARY, 168)
	_button.name = "StartButton"
	_button.pressed.connect(func() -> void: start_requested.emit())
	add_child(_button)
	_goto = UiKit.button("", MainTheme.VAR_GHOST, UiTokens.H_TOUCH)
	_goto.name = "GotoStageButton"
	_goto.visible = false
	add_child(_goto)
	_hint = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.name = "Hint"
	add_child(_hint)


func view() -> Dictionary:
	return _view


func start_button() -> Button:
	return _button


func set_busy(value: bool) -> void:
	_button.disabled = value or not bool(_view.get("can_start", false))


func bind(state: Dictionary, content: Dictionary, next_realm_name: String, after_next_name: String = "") -> void:
	_view = BreakthroughView.build(state, next_realm_name)
	UiKit.clear(_body)
	_body.add_child(_nodes_row(str(state.get("realmName", "")), next_realm_name, after_next_name))
	_body.add_child(_rings_row())
	_body.add_child(_conditions_card())
	var can_start := bool(_view.can_start)
	_button.disabled = not can_start
	UiKit.set_cta(_button, str(_view.button_text), str(_view.cost_text) if bool(_view.has_next) else "")
	_hint.text = "突破必定成功，超出的修为会保留" if bool(_view.has_next) and can_start else str(_view.hint)
	_goto.visible = bool(_view.has_next) and bool(_view.has_gate) and not bool(_view.boss_ok)
	for connection in _goto.pressed.get_connections():
		_goto.pressed.disconnect(connection.callable)
	if _goto.visible:
		var slug := str(_view.gate_stage)
		_goto.text = "去挑战 %s" % str(_view.gate_stage_name)
		_goto.pressed.connect(func() -> void: goto_stage_requested.emit(slug))


func _nodes_row(current_name: String, target_name: String, after_name: String) -> Control:
	var row := UiKit.hbox(UiTokens.SP_1)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size = Vector2(0, 290)
	row.add_child(_node(current_name, "当前", "current", "ui_yinyang"))
	row.add_child(UiKit.label("»", UiTokens.FS_H1, UiTokens.GOLD))
	row.add_child(_node(target_name if bool(_view.has_next) else "—", "突破目标", "target", "ui_pagoda"))
	row.add_child(UiKit.label("›", UiTokens.FS_H1, UiTokens.TEXT_DISABLED))
	row.add_child(_node(after_name if not after_name.is_empty() else "更高境界", "未解锁", "locked", "ui_lock"))
	return row


func _node(realm_name: String, tag: String, kind: String, icon_name: String) -> Control:
	var column := UiKit.vbox(2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tag_color := UiTokens.TEXT_MUTED
	var border := UiTokens.GOLD_BORDER
	var fill := Color(0.1, 0.27, 0.22, 0.95)
	match kind:
		"current":
			tag_color = UiTokens.JADE
			border = UiTokens.JADE_DEEP
		"target":
			tag_color = UiTokens.GOLD_HOVER
			border = UiTokens.GOLD
			fill = Color(0.36, 0.08, 0.1, 0.95)
		"locked":
			tag_color = UiTokens.TEXT_DISABLED
			border = Color(0.35, 0.37, 0.37)
			fill = Color(0.12, 0.13, 0.13, 0.95)
	chip.add_theme_stylebox_override("panel", ArtLib.nine("chip"))
	chip.add_child(UiKit.label(tag, UiTokens.FS_MICRO, tag_color, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(chip)
	var disc := PanelContainer.new()
	disc.custom_minimum_size = Vector2(136, 136)
	disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	disc.add_theme_stylebox_override("panel", KitStyle.box(fill, border, 5, 999))
	var icon := UiKit.icon(icon_name, 72, tag_color)
	disc.add_child(icon)
	column.add_child(disc)
	var label := UiKit.label(realm_name, UiTokens.FS_CAPTION, tag_color if kind != "current" else UiTokens.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	label.clip_text = true
	label.add_theme_font_override("font", ArtLib.title_font())
	column.add_child(label)
	return column


func _rings_row() -> Control:
	var row := UiKit.hbox(UiTokens.SP_2)
	row.custom_minimum_size = Vector2(0, 240)
	var gain := float(_view.power_gain_percent)
	var left := RingGauge.new(210.0)
	left.color = Color("a47bd8")
	left.ratio = clampf(gain / 200.0, 0.0, 1.0)
	left.name = "PowerRing"
	left.add_child(_ring_text("战力提升", "+%d%%" % int(round(gain)) if bool(_view.preview_ok) else "—"))
	var right := RingGauge.new(210.0)
	right.color = UiTokens.JADE_FILL
	right.ratio = float(_view.rate_percent) / 100.0
	right.name = "RateRing"
	right.add_child(_ring_text("成功率", "%d%%" % int(_view.rate_percent)))
	var hero := TextureRect.new()
	hero.texture = ArtLib.icon("avatar_meditate")
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.modulate = UiTokens.GOLD_HOVER
	row.add_child(left)
	row.add_child(hero)
	row.add_child(right)
	return row


func _ring_text(caption: String, value: String) -> Control:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(UiKit.label(caption, UiTokens.FS_MICRO, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var big := UiKit.label(value, UiTokens.FS_H2, UiTokens.GOLD_HOVER, HORIZONTAL_ALIGNMENT_CENTER)
	big.name = "Value"
	big.add_theme_font_override("font", ArtLib.title_font())
	box.add_child(big)
	return box


func _conditions_card() -> Control:
	var card := UiKit.card("突破条件")
	card.panel.name = "ConditionsCard"
	var body := card.body as VBoxContainer
	body.add_theme_constant_override("separation", UiTokens.SP_1)
	if not bool(_view.has_next):
		body.add_child(UiKit.label("当前已是最高境界", UiTokens.FS_BODY, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		return card.panel
	body.add_child(_condition_row("res_cultivation", "修为", "当前已达标" if bool(_view.cultivation_ok) else "还差 %s" % OfflineView.grouped(float(_view.cost) - float(_view.cultivation)), "%s / %s" % [OfflineView.grouped(float(_view.cultivation)), OfflineView.grouped(float(_view.cost))], bool(_view.cultivation_ok), float(_view.cultivation_ratio)))
	if bool(_view.has_gate):
		body.add_child(_condition_row("tab_adventure", "击败首领", str(_view.gate_stage_name), "%s · %s" % [str(_view.gate_boss), "已击败" if bool(_view.boss_ok) else "未击败"], bool(_view.boss_ok), -1.0))
	body.add_child(_after_row())
	return card.panel


func _condition_row(icon_name: String, title: String, sub: String, value: String, ok: bool, ratio: float) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ArtLib.nine("row_bg"))
	var row := UiKit.hbox(UiTokens.SP_1)
	panel.add_child(row)
	row.add_child(UiKit.icon(icon_name, 56, UiTokens.JADE if ok else UiTokens.TEXT_MUTED))
	var names := UiKit.vbox(0)
	names.custom_minimum_size = Vector2(190, 0)
	row.add_child(names)
	names.add_child(UiKit.label(title, UiTokens.FS_BODY, UiTokens.TEXT))
	var sub_label := UiKit.label(sub, UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	sub_label.clip_text = true
	names.add_child(sub_label)
	var middle := UiKit.vbox(2)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(middle)
	var value_label := UiKit.label(value, UiTokens.FS_CAPTION, UiTokens.GOLD_HOVER, HORIZONTAL_ALIGNMENT_RIGHT)
	value_label.clip_text = true
	middle.add_child(value_label)
	if ratio >= 0.0:
		middle.add_child(UiKit.ratio_bar(ratio, "bar_fill_gold" if ok else "bar_fill_jade", 20))
	var mark := UiKit.label(("已满足 ✔" if ok else "未满足 ✖"), UiTokens.FS_MICRO, UiTokens.SUCCESS if ok else UiTokens.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	mark.name = "Mark"
	row.add_child(mark)
	return panel


func _after_row() -> Control:
	var panel := PanelContainer.new()
	panel.name = "AfterRow"
	panel.add_theme_stylebox_override("panel", ArtLib.nine("row_bg"))
	var column := UiKit.vbox(2)
	panel.add_child(column)
	var head := UiKit.hbox(UiTokens.SP_1)
	column.add_child(head)
	head.add_child(UiKit.label("突破后", UiTokens.FS_BODY, UiTokens.TEXT))
	var power := UiKit.label("战力 %s → %s" % [OfflineView.grouped(float(_view.power_now)), OfflineView.grouped(float(_view.power_after))] if bool(_view.preview_ok) else "战力 %s" % OfflineView.grouped(float(_view.power_now)), UiTokens.FS_BODY, UiTokens.GOLD_HOVER, HORIZONTAL_ALIGNMENT_RIGHT)
	power.name = "PowerAfter"
	power.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(power)
	if bool(_view.preview_ok):
		var stats := UiKit.hbox(UiTokens.SP_2)
		column.add_child(stats)
		for row in _view.rows:
			stats.add_child(UiKit.label("%s %s → %s" % [str(row.name), OfflineView.grouped(float(row.before)), OfflineView.grouped(float(row.after))], UiTokens.FS_MICRO, UiTokens.TEXT))
	return panel
