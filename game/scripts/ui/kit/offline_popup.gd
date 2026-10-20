class_name OfflinePopup
extends Control
## 离线收益弹窗（Q 版设计稿 q_offline_popup）：绶带「离线收益」、宝箱舞台、离线时长 + 「计入 N 小时」、
## 获得修为大数字（美术位图数字 digits_xiuwei）、基础 + 功法加成的算式、获得物品、「领取」「双倍领取」。
## 修为在服务器早已入账：「领取」（以及右上角关闭、点空白处）只是告诉服务器“已读”
## （POST /me/offline-reports/:id/ack）并关闭。「双倍领取」是看广告翻倍，还没有：点了提示「功能暂未开放」。

signal acknowledged(report_id: String)

const PANEL_WIDTH := 940.0
## 弹窗框在 1080 画布上的位置（设计稿 70,540,940,1270；状态栏 90 以下）。
const FRAME := Rect2(70, 540, 940, 1270)

var report_id := ""
var _panel: PanelContainer
var _body: VBoxContainer
var _foot: Label
var _button: Button
var _double: Button
var _close: Button
var _ribbon: Control
var _view: Dictionary = {}
var _inset_top := 90.0


func _init() -> void:
	name = "OfflinePopup"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.name = "Dimmer"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and _button != null and not _button.disabled:
			_on_claim())
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "PopupFrame"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", QKit.cut_box("popup_frame", 24, 70) if ArtLib.qui("popup_frame") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 6, 48, 12, 24, 70))
	add_child(_panel)
	_body = UiKit.vbox(18)
	_panel.add_child(_body)
	_ribbon = QKit.ribbon("离线收益", 52, 340, true)
	_ribbon.name = "Ribbon"
	add_child(_ribbon)
	_close = Button.new()
	_close.name = "CloseButton"
	_close.focus_mode = Control.FOCUS_NONE
	var close_tex := ArtLib.qui("btn_close")
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		if close_tex != null and key != "focus":
			var box := StyleBoxTexture.new()
			box.texture = close_tex
			_close.add_theme_stylebox_override(key, box)
		else:
			_close.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	if close_tex == null:
		_close.text = "✕"
	_close.pressed.connect(_on_claim)
	add_child(_close)
	var pill := QKit.tag("点击空白处关闭", "dark", 32, 30)
	pill.name = "FootPill"
	_foot = pill.get_child(0) as Label
	_foot.name = "FootHint"
	add_child(pill)
	_layout()


func apply_safe_area(inset: Vector4) -> void:
	_inset_top = inset.y
	_layout()


func _layout() -> void:
	var shift := _inset_top - 90.0
	_panel.position = FRAME.position + Vector2(0, shift)
	_panel.size = FRAME.size + Vector2(0, 12)
	_ribbon.position = Vector2(540 - _ribbon.custom_minimum_size.x / 2.0, 424 + shift)
	_close.position = Vector2(948, 470 + shift)
	_close.size = Vector2(84, 89)
	var pill := get_node("FootPill") as Control
	pill.position = Vector2(340, 1844 + shift)
	pill.custom_minimum_size = Vector2(400, 60)


func current_view() -> Dictionary:
	return _view


func claim_button() -> Button:
	return _button


func double_button() -> Button:
	return _double


func close_button() -> Button:
	return _close


## view 来自 OfflineView.build。
func show_report(view: Dictionary) -> void:
	_view = view
	report_id = str(view.get("id", ""))
	UiKit.clear(_body)
	_body.add_child(_stage())
	_body.add_child(_duration_row())
	_body.add_child(_total_row())
	var formula := UiKit.label(_formula_text(), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	formula.name = "Formula"
	_body.add_child(formula)
	var cap := UiKit.label(str(view.get("cap_note", "")), UiTokens.FS_MICRO, UiTokens.Q_ORANGE_DARK if bool(view.get("hit_cap", false)) else UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	cap.name = "CapNote"
	_body.add_child(cap)
	_body.add_child(_items())
	_body.add_child(_buttons())
	visible = true


func _formula_text() -> String:
	var text := "基础 %s" % str(_view.get("base_text", "0"))
	if not str(_view.get("bonus_percent_text", "")).is_empty():
		text += " + %s %s %s" % [str(_view.get("skill_label", "功法加成")).replace("功法", ""), str(_view.get("bonus_percent_text", "")), str(_view.get("bonus_text", "+0")).trim_prefix("+")]
	return text


## 宝箱舞台（设计稿 94,610,892,390：浅蓝底 + 放射光 + 宝箱）。
func _stage() -> Control:
	var stage := Panel.new()
	stage.name = "ChestStage"
	stage.custom_minimum_size = Vector2(0, 390)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_theme_stylebox_override("panel", QSkin.custom(Color("d7f1fb"), Color(0, 0, 0, 0), 0, 30, 0, 0, 0))
	var burst := TextureRect.new()
	burst.texture = ArtLib.q("sprites/fx_sunburst") if ArtLib.has_q("sprites/fx_sunburst.png") else null
	burst.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	burst.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	burst.offset_top = -200
	burst.offset_bottom = 200
	burst.modulate.a = 0.8
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(burst)
	var chest := TextureRect.new()
	chest.name = "Chest"
	chest.texture = ArtLib.q("sprites/chest_closed") if ArtLib.has_q("sprites/chest_closed.png") else ArtLib.icon("chest")
	chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chest.set_anchors_preset(Control.PRESET_CENTER)
	chest.offset_left = -180
	chest.offset_right = 180
	chest.offset_top = -160
	chest.offset_bottom = 195
	chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(chest)
	return stage


func _duration_row() -> Control:
	var plate := PanelContainer.new()
	plate.name = "DurationRow"
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.custom_minimum_size = Vector2(700, 84)
	plate.add_theme_stylebox_override("panel", QKit.cut_box("plate_label_cream_66", 26, 0) if ArtLib.qui("plate_label_cream_66") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 4, 33, 4, 26, 0))
	var row := UiKit.hbox(12)
	plate.add_child(row)
	row.add_child(QKit.cut_rect("icon_hourglass", Vector2(50, 64)))
	row.add_child(QKit.title("离线时长", 34, UiTokens.TEXT))
	var away := QKit.title(str(_view.get("away_text", "")), 42, UiTokens.TEXT)
	away.name = "AwayLabel"
	away.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(away)
	var chip := QKit.tag(str(_view.get("counted_text", "")), "orange", 30, 14)
	chip.name = "CountedChip"
	row.add_child(chip)
	return plate


## 获得修为：莲花 + 大数字（digits_xiuwei 位图字体）+「修为」。
func _total_row() -> Control:
	var row := UiKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiKit.icon("res_lotus", 120))
	var total := Label.new()
	total.name = "TotalLabel"
	total.text = str(_view.get("total_text", "+0"))
	var font := ArtLib.digits_font("xiuwei")
	if font != null:
		total.add_theme_font_override("font", font)
		total.add_theme_font_size_override("font_size", 112)
		total.add_theme_color_override("font_color", Color.WHITE)  # 位图字体会乘字色，保持原色
	else:
		total.add_theme_font_override("font", ArtLib.title_font())
		total.add_theme_font_size_override("font_size", 104)
		total.add_theme_color_override("font_outline_color", Color("2e8fd8"))
		total.add_theme_constant_override("outline_size", 16)
	total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(total)
	row.add_child(QKit.title("修为", 40, UiTokens.Q_BLUE_DARK))
	return row


## 获得物品：离线报告里有物品（items / drops）才列出来；现在的离线结算只给修为。
func _items() -> Control:
	var box := QKit.inset(UiTokens.Q_CARD, 30, 22, 14)
	box.panel.name = "ItemsBox"
	box.panel.custom_minimum_size = Vector2(0, 200)
	box.body.add_child(QKit.title("获得物品", 32, UiTokens.TEXT_MUTED))
	var rows: Array = _view.get("items", []) if typeof(_view.get("items", null)) == TYPE_ARRAY else []
	if rows.is_empty():
		var none := UiKit.label("本次离线只累计修为，没有获得物品", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		none.size_flags_vertical = Control.SIZE_EXPAND_FILL
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.body.add_child(none)
	return box.panel


func _buttons() -> Control:
	var row := UiKit.hbox(60)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_button = QKit.button("领取", "o", 124, 52)
	_button.name = "ClaimButton"
	_button.custom_minimum_size.x = 400
	_button.pressed.connect(_on_claim)
	row.add_child(_button)
	_double = QKit.button("双倍领取", "m", 124, 52)
	_double.name = "DoubleButton"
	_double.custom_minimum_size.x = 400
	var video := QKit.cut_rect("icon_video", Vector2(64, 48))
	video.position = Vector2(-10, -26)
	_double.add_child(video)
	var badge := QKit.tag("×2", "red", 30, 12)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -80
	badge.offset_top = -22
	_double.add_child(badge)
	LockedFeature.wire(_double, "offline_double")
	row.add_child(_double)
	return row


func _on_claim() -> void:
	if _button == null or _button.disabled:
		return
	_button.disabled = true
	acknowledged.emit(report_id)


## 服务器确认已读（或失败后放弃）后调用。
func close_popup() -> void:
	visible = false
	_view = {}
