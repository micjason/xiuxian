class_name BreakthroughSuccess
extends Control
## 突破成功弹窗：绶带「突破成功」、主角坐莲台（动画主角 + 突破特效 idle）、旧境界 → 新境界、四项属性前后和增量、
## 总战力前后与增幅、境界解锁（每秒修为 / 大招伤害 / 新关卡）、「继续修炼」。
## 数据来自 BreakthroughView.success_summary（前后两份服务器状态）和 BreakthroughView.unlocks。
## 2026-10-20：旧版顶部插画（墨色旧主角）换成 Q 版舞台 + 新主角；「突破成功」绶带放在弹窗最上面单独一行，
## 下面才是舞台和「旧境界 → 新境界」——原来绶带压在插画底边、离境界行只差几像素，看着像压住了标题。
## 弹出用 ui_popup 的 open 动画；「继续修炼」按下回弹。

signal closed

var _panel: PanelContainer
var _body: VBoxContainer
var _summary: Dictionary = {}
var _unlocks: Array[Dictionary] = []
var _fx: Control

const STAGE_HEIGHT := 380.0


func _init() -> void:
	name = "BreakthroughSuccess"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var host: Control = self
	_fx = QFx.popup_shell(Color(0, 0, 0, 0.72))
	if _fx != null:
		_fx.name = "PopupFx"
		add_child(_fx)
		host = QFx.popup_content(_fx)
	else:
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.72)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
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
	_body.add_child(_header())
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
	QFx.bounce(button)
	_body.add_child(button)
	visible = true
	if _fx != null:
		QFx.set_popup_pivot(_fx, Rect2(Vector2.ZERO, get_viewport_rect().size))
		QFx.play(_fx, "open")


## 顶部：「突破成功」绶带（单独一行，不压任何字）+ 舞台（青色底、莲台、动画主角、突破特效 idle 循环）。
func _header() -> Control:
	var box := UiKit.vbox(12)
	box.name = "Header"
	var ribbon := QKit.ribbon("突破成功", 60, 420, true)
	ribbon.name = "Ribbon"
	var title := ribbon.find_child("RibbonText", true, false) as Label
	if title != null:
		title.name = "Title"
	box.add_child(ribbon)
	var stage := Panel.new()
	stage.name = "Stage"
	stage.custom_minimum_size = Vector2(0, STAGE_HEIGHT)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_theme_stylebox_override("panel", QKit.cut_box("well_teal", 0, 0) if ArtLib.qui("well_teal") != null else QSkin.custom(Color("cfeefa"), Color(0, 0, 0, 0), 0, 36, 0, 0, 0))
	box.add_child(stage)
	var anchor := Control.new()
	anchor.name = "StageAnchor"
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.anchor_left = 0.5
	anchor.anchor_right = 0.5
	anchor.offset_top = STAGE_HEIGHT - 40.0
	anchor.offset_bottom = STAGE_HEIGHT - 40.0
	stage.add_child(anchor)
	var fx := QFx.make(QFx.BREAKTHROUGH) as Node2D
	if fx != null:
		fx.name = "BreakFx"
		fx.scale = Vector2.ONE * 0.8
		var banner := fx.get_node_or_null("Front/Title") as CanvasItem
		if banner != null:
			banner.visible = false  # 标题已在上面的绶带里
		anchor.add_child(fx)
		QFx.play(fx, "idle")
	if ArtLib.has_q("sprites/lotus_platform.png"):
		var lotus := TextureRect.new()
		lotus.texture = ArtLib.q("sprites/lotus_platform")
		lotus.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lotus.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lotus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lotus.position = Vector2(-184, -133)
		lotus.size = Vector2(368, 179)
		anchor.add_child(lotus)
	var hero := QHero.new(true, false)
	hero.name = "Hero"
	hero.position = Vector2(-160, -313)
	hero.size = Vector2(320, 313)
	anchor.add_child(hero)
	return box


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


## 顶部绶带「突破成功」（测试用）。
func title_label() -> Label:
	return _body.find_child("Title", true, false) as Label
