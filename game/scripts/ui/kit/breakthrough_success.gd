class_name BreakthroughSuccess
extends Control
## 突破成功弹窗（设计稿 06）：丝带「突破成功」、旧境界 → 新境界、四项属性前后和增量、
## 总战力前后与增幅、境界解锁（每秒修为 / 大招伤害 / 新关卡）、「继续修炼」。
## 数据来自 BreakthroughView.success_summary（前后两份服务器状态）和 BreakthroughView.unlocks。

signal closed

var _panel: PanelContainer
var _body: VBoxContainer
var _summary: Dictionary = {}
var _unlocks: Array[Dictionary] = []


func _init() -> void:
	name = "BreakthroughSuccess"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(936, 0)
	_panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_popup"))
	center.add_child(_panel)
	_body = UiKit.vbox(UiTokens.SP_1)
	_panel.add_child(_body)


func summary() -> Dictionary:
	return _summary


func show_success(summary: Dictionary, unlocks: Array[Dictionary]) -> void:
	_summary = summary
	_unlocks = unlocks
	UiKit.clear(_body)
	var ribbon := PanelContainer.new()
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ribbon.custom_minimum_size = Vector2(620, 110)
	ribbon.add_theme_stylebox_override("panel", ArtLib.nine("ribbon_title", Color(1.0, 0.55, 0.5)))
	var title := UiKit.label("突破成功", 72, UiTokens.GOLD_HOVER, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	title.add_theme_font_override("font", ArtLib.title_font())
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.05, 0.02, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	ribbon.add_child(title)
	_body.add_child(ribbon)
	var names := UiKit.hbox(UiTokens.SP_2)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_child(UiKit.label(str(summary.from_name), UiTokens.FS_H2, UiTokens.TEXT_MUTED))
	names.add_child(UiKit.label("→", UiTokens.FS_H2, UiTokens.GOLD))
	var to_label := UiKit.label(str(summary.to_name), UiTokens.FS_H1, UiTokens.GOLD_HOVER)
	to_label.name = "ToName"
	to_label.add_theme_font_override("font", ArtLib.title_font())
	names.add_child(to_label)
	_body.add_child(names)
	_body.add_child(UiKit.section_title("境界提升  属性增强"))
	for row in summary.rows:
		_body.add_child(_stat_row(row))
	var power := UiKit.hbox(UiTokens.SP_1)
	power.alignment = BoxContainer.ALIGNMENT_CENTER
	power.add_child(UiKit.label("战力", UiTokens.FS_CAPTION, UiTokens.TEXT))
	power.add_child(UiKit.label(OfflineView.grouped(float(summary.power_before)), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	power.add_child(UiKit.label("→", UiTokens.FS_CAPTION, UiTokens.GOLD))
	var after := UiKit.label(OfflineView.grouped(float(summary.power_after)), UiTokens.FS_H1, UiTokens.GOLD_HOVER)
	after.name = "PowerAfter"
	after.add_theme_font_override("font", ArtLib.title_font())
	power.add_child(after)
	power.add_child(UiKit.label("▲%s（+%d%%）" % [OfflineView.grouped(float(summary.power_delta)), int(round(float(summary.power_gain_percent)))], UiTokens.FS_CAPTION, UiTokens.SUCCESS))
	_body.add_child(power)
	if not unlocks.is_empty():
		_body.add_child(UiKit.section_title("境界解锁"))
		var unlock_row := UiKit.hbox(UiTokens.SP_1)
		unlock_row.alignment = BoxContainer.ALIGNMENT_CENTER
		for unlock in unlocks:
			var column := UiKit.vbox(0)
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_child(UiKit.label(str(unlock.title), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
			var text := UiKit.label(str(unlock.text), UiTokens.FS_CAPTION, UiTokens.GOLD_HOVER, HORIZONTAL_ALIGNMENT_CENTER)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(text)
			unlock_row.add_child(column)
		_body.add_child(unlock_row)
	var button := UiKit.button("继续修炼", MainTheme.VAR_PRIMARY, UiTokens.H_CTA)
	button.name = "ContinueButton"
	button.pressed.connect(close_popup)
	_body.add_child(button)
	visible = true


func _stat_row(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ArtLib.nine("row_bg"))
	var line := UiKit.hbox(UiTokens.SP_1)
	panel.add_child(line)
	line.add_child(UiKit.icon(_icon_of(str(row.key)), 48, UiTokens.JADE))
	var name := UiKit.label(str(row.name), UiTokens.FS_BODY, UiTokens.TEXT)
	name.custom_minimum_size = Vector2(120, 0)
	line.add_child(name)
	var range_label := UiKit.label("%s → %s" % [OfflineView.grouped(float(row.before)), OfflineView.grouped(float(row.after))], UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED)
	range_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(range_label)
	var delta := float(row.delta)
	line.add_child(UiKit.label("%s%s ▲" % ["+" if delta >= 0.0 else "-", OfflineView.grouped(absf(delta))], UiTokens.FS_BODY_L, UiTokens.SUCCESS, HORIZONTAL_ALIGNMENT_RIGHT))
	return panel


static func _icon_of(key: String) -> String:
	for row in BreakthroughView.STAT_ROWS:
		if str(row.key) == key:
			return str(row.icon)
	return "res_power"


func close_popup() -> void:
	visible = false
	closed.emit()
