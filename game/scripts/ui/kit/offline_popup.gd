class_name OfflinePopup
extends Control
## 离线收益弹窗（设计稿 08，无广告按钮）：卷轴外框 panel_popup_scroll，顶部「闭关归来」，
## 离线时长条、获得修为大字、基础修为 + 功法加成 = 合计。修为在服务器早已入账，
## 点「知道了」只是告诉服务器“已读”（POST /me/offline-reports/:id/ack）并关闭。

signal acknowledged(report_id: String)

const PANEL_WIDTH := 936.0

var report_id := ""
var _panel: PanelContainer
var _stack: VBoxContainer
var _foot: Label
var _body: VBoxContainer
var _button: Button
var _view: Dictionary = {}


func _init() -> void:
	name = "OfflinePopup"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	# 卷轴 + 它下面的一行提示（设计稿 08：提示在卷轴外面，不压在下轴上）
	_stack = UiKit.vbox(UiTokens.SP_2)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_stack)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_popup_scroll"))
	_stack.add_child(_panel)
	_body = UiKit.vbox(UiTokens.SP_1)
	_panel.add_child(_body)


func current_view() -> Dictionary:
	return _view


func claim_button() -> Button:
	return _button


## view 来自 OfflineView.build。
func show_report(view: Dictionary) -> void:
	_view = view
	report_id = str(view.get("id", ""))
	UiKit.clear(_body)
	_body.add_child(_header())
	var subtitle := UiKit.label("洞府静修，灵气已悄然入体", UiTokens.FS_CAPTION, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_body.add_child(subtitle)
	_body.add_child(_duration_card())
	_body.add_child(UiKit.label("获得修为", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var total := UiKit.label(str(view.get("total_text", "+0")), 96, UiTokens.GOLD_HOVER, HORIZONTAL_ALIGNMENT_CENTER)
	total.name = "TotalLabel"
	total.add_theme_font_override("font", ArtLib.title_font())
	total.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.02, 0.9))
	total.add_theme_constant_override("outline_size", 10)
	_body.add_child(total)
	_body.add_child(_breakdown_card())
	_button = UiKit.button("知道了", MainTheme.VAR_PRIMARY, UiTokens.H_CTA)
	_button.name = "ClaimButton"
	_button.pressed.connect(_on_claim)
	_body.add_child(_button)
	var gap := Control.new()  # 按钮和下轴之间留一点空，不要贴着
	gap.custom_minimum_size = Vector2(0, UiTokens.SP_2)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(gap)
	if _foot == null:
		_foot = UiKit.label("收益已入账", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		_foot.name = "FootHint"
		_stack.add_child(_foot)
	visible = true


func _header() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 330)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_bottom = -30
	frame.clip_contents = true
	frame.add_theme_stylebox_override("panel", ArtLib.nine("panel_inset"))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	# 顶部插画：交付 popup_offline_header 切图前先用渡劫背景图裁一块。
	var art := TextureRect.new()
	art.texture = ArtLib.ui("popup_offline_header") if ArtLib.has_ui("popup_offline_header") else ArtLib.bg("breakthrough")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	var ribbon := PanelContainer.new()
	ribbon.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ribbon.offset_left = -300
	ribbon.offset_right = 300
	ribbon.offset_top = -104
	ribbon.offset_bottom = 0
	ribbon.add_theme_stylebox_override("panel", ArtLib.nine("ribbon_title", Color(1.0, 0.55, 0.5)))
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := UiKit.label("闭关归来", UiTokens.FS_H1, UiTokens.GOLD_HOVER, HORIZONTAL_ALIGNMENT_CENTER)
	text.add_theme_font_override("font", ArtLib.title_font())
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ribbon.add_child(text)
	holder.add_child(ribbon)
	return holder


func _duration_card() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_card"))
	var column := UiKit.vbox(UiTokens.SP_1)
	panel.add_child(column)
	var row := UiKit.hbox(UiTokens.SP_1)
	column.add_child(row)
	row.add_child(UiKit.icon_from(ArtLib.icon_or("ui_hourglass", "ui_moon"), 64, UiTokens.GOLD))
	var away := UiKit.label("离线 %s" % str(_view.get("away_text", "")), UiTokens.FS_BODY_L, UiTokens.TEXT)
	away.name = "AwayLabel"
	away.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(away)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", ArtLib.nine("chip"))
	chip.add_child(UiKit.label(str(_view.get("counted_text", "")), UiTokens.FS_MICRO, UiTokens.GOLD))
	row.add_child(chip)
	var bar := UiKit.ratio_bar(float(_view.get("bar_ratio", 0.0)), "bar_fill_gold", 36)
	column.add_child(bar)
	var note_color := UiTokens.WARNING if bool(_view.get("hit_cap", false)) else UiTokens.TEXT_MUTED
	var note := UiKit.wrap_label(str(_view.get("cap_note", "")), UiTokens.FS_MICRO, note_color)
	note.name = "CapNote"
	column.add_child(note)
	column.add_child(UiKit.label(str(_view.get("bar_text", "")), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	return panel


func _breakdown_card() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_card"))
	var column := UiKit.vbox(UiTokens.SP_1)
	panel.add_child(column)
	var base := UiKit.hbox(UiTokens.SP_1)
	column.add_child(base)
	base.add_child(UiKit.icon("res_cultivation", 48, UiTokens.JADE))
	var base_name := UiKit.label("基础修为", UiTokens.FS_BODY, UiTokens.TEXT)
	base_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base.add_child(base_name)
	var base_value := UiKit.label(str(_view.get("base_text", "0")), UiTokens.FS_BODY_L, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	base_value.name = "BaseValue"
	base.add_child(base_value)
	column.add_child(UiKit.divider())
	var bonus := UiKit.hbox(UiTokens.SP_1)
	column.add_child(bonus)
	bonus.add_child(UiKit.icon("cat_scroll", 48, UiTokens.GOLD))
	var bonus_name := UiKit.label(str(_view.get("skill_label", "功法加成")), UiTokens.FS_BODY, UiTokens.TEXT)
	bonus_name.clip_text = true
	bonus_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bonus.add_child(bonus_name)
	if not str(_view.get("bonus_percent_text", "")).is_empty():
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", KitStyle.box(Color(0.14, 0.38, 0.28), UiTokens.JADE, 2, UiTokens.R_SM, 4))
		tag.add_child(UiKit.label(str(_view.get("bonus_percent_text", "")), UiTokens.FS_MICRO, UiTokens.SUCCESS))
		bonus.add_child(tag)
	var bonus_value := UiKit.label(str(_view.get("bonus_text", "+0")), UiTokens.FS_BODY_L, UiTokens.SUCCESS, HORIZONTAL_ALIGNMENT_RIGHT)
	bonus_value.name = "BonusValue"
	bonus.add_child(bonus_value)
	return panel


func _on_claim() -> void:
	_button.disabled = true
	acknowledged.emit(report_id)


## 服务器确认已读（或失败后放弃）后调用。
func close_popup() -> void:
	visible = false
	_view = {}
