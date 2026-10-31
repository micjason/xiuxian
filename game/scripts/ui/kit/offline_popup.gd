class_name OfflinePopup
extends Control
## 离线收益弹窗（极简）：摘要（时长 / 修为 / 件数）+ 吸底「一键领取」。
## 不要滚动条、不要装备/战利品明细列表。修为在服务器早已入账：
## 「一键领取」（以及右上角关闭、点空白处）只是告诉服务器“已读”
## （POST /me/offline-reports/:id/ack）并关闭。「双倍领取」是看广告翻倍，还没有：点了提示「功能暂未开放」。
## 掉落公式 / 入账 / 服务端 API 不动，只改客户端布局。
## 动画：弹窗 ui_popup open/close；宝箱 chest_open；「一键领取」用 ui_button_bounce。

signal acknowledged(report_id: String)

const PANEL_WIDTH := 940.0
## 极简内容：宝箱 + 摘要 + 修为数字 + 吸底按钮，框体比样式改版矮一截。
const FRAME := Rect2(70, 700, 940, 820)
const CLAIM_LABEL := "一键领取"

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
var _fx: Control
var _host: Control
var _claim_fx: Control
var _chest_fx: Node2D
var _total_label: Label
var _close_gen := 0
var _roll: Tween

var _dim: ColorRect


func _init() -> void:
	name = "OfflinePopup"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_host = self
	_fx = QFx.popup_shell(Color(0, 0, 0, 0.55))
	var dim: ColorRect
	if _fx != null:
		_fx.name = "PopupFx"
		add_child(_fx)
		dim = _fx.get_node("Backdrop") as ColorRect
		_host = QFx.popup_content(_fx)
		QFx.set_popup_pivot(_fx, FRAME)
	else:
		dim = ColorRect.new()
		dim.color = Color(0, 0, 0, 0.55)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		dim.name = "Dimmer"
	_dim = dim
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and _button != null and not _button.disabled:
			_on_claim())
	_panel = PanelContainer.new()
	_panel.name = "PopupFrame"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", QKit.cut_box("popup_frame", 24, 70) if ArtLib.qui("popup_frame") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 6, 48, 12, 24, 70))
	_host.add_child(_panel)
	_body = UiKit.vbox(18)
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_body)
	_ribbon = QKit.ribbon("离线收益", 52, 340, true)
	_ribbon.name = "Ribbon"
	_host.add_child(_ribbon)
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
	_host.add_child(_close)
	var pill := QKit.tag("点击空白处关闭", "dark", 32, 30)
	pill.name = "FootPill"
	_foot = pill.get_child(0) as Label
	_foot.name = "FootHint"
	_host.add_child(pill)
	_layout()


func apply_safe_area(inset: Vector4) -> void:
	_inset_top = inset.y
	_layout()


func _layout() -> void:
	var shift := _inset_top - 90.0
	_panel.position = FRAME.position + Vector2(0, shift)
	_panel.size = FRAME.size + Vector2(0, 12)
	_ribbon.position = Vector2(540 - _ribbon.custom_minimum_size.x / 2.0, FRAME.position.y - 116.0 + shift)
	_close.position = Vector2(948, FRAME.position.y - 70.0 + shift)
	_close.size = Vector2(84, 89)
	if _fx != null:
		QFx.set_popup_pivot(_fx, Rect2(FRAME.position + Vector2(0, shift), FRAME.size))
	var foot := _host.get_node("FootPill") as Control
	foot.position = Vector2(340, FRAME.position.y + FRAME.size.y + 34.0 + shift)
	foot.custom_minimum_size = Vector2(400, 60)


func current_view() -> Dictionary:
	return _view


func claim_button() -> Button:
	return _button


func double_button() -> Button:
	return _double


func close_button() -> Button:
	return _close


func show_report(view: Dictionary) -> void:
	_view = view
	report_id = str(view.get("id", ""))
	UiKit.clear(_body)
	_body.add_child(_stage())
	_body.add_child(_summary())
	_body.add_child(_total_row())
	var spacer := Control.new()
	spacer.name = "BodySpacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(spacer)
	_body.add_child(_buttons())
	_close_gen += 1
	visible = true
	if _fx != null:
		QFx.play(_fx, "open")
	_play_chest()


func _play_chest() -> void:
	if _roll != null:
		_roll.kill()
	if _chest_fx == null:
		return
	var ap := QFx.player(_chest_fx)
	ap.play("idle_closed")
	var gen := _close_gen
	var total := float(_view.get("total", 0))
	var final_text := str(_view.get("total_text", "+0"))
	if _total_label != null:
		_total_label.text = "+0"
	_roll = create_tween()
	_roll.tween_interval(0.6)
	_roll.tween_callback(func() -> void:
		if gen == _close_gen:
			ap.play("open")
			ap.queue("idle_open"))
	_roll.tween_interval(1.0)
	if _total_label != null:
		_roll.tween_method(func(t: float) -> void:
			_total_label.text = "+" + OfflineView.grouped(floorf(total * t)), 0.0, 1.0, 1.2)
		_roll.tween_callback(func() -> void: _total_label.text = final_text)
		_roll.tween_property(_total_label, "scale", Vector2.ONE * 1.22, 0.16)
		_roll.tween_property(_total_label, "scale", Vector2.ONE * 0.95, 0.14)
		_roll.tween_property(_total_label, "scale", Vector2.ONE, 0.12)


func chest_fx() -> Node2D:
	return _chest_fx


func total_text() -> String:
	return _total_label.text if _total_label != null else ""


func _stage() -> Control:
	var stage := Panel.new()
	stage.name = "ChestStage"
	stage.custom_minimum_size = Vector2(0, 200)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_theme_stylebox_override("panel", QSkin.custom(Color("d7f1fb"), Color(0, 0, 0, 0), 0, 30, 0, 0, 0))
	_chest_fx = QFx.make(QFx.CHEST) as Node2D
	if _chest_fx != null:
		stage.clip_contents = false
		var anchor := Control.new()
		anchor.name = "ChestAnchor"
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor.anchor_left = 0.5
		anchor.anchor_right = 0.5
		anchor.offset_top = 110.0
		anchor.offset_bottom = 110.0
		stage.add_child(anchor)
		_chest_fx.name = "ChestFx"
		_chest_fx.scale = Vector2(0.72, 0.72)
		var sample := _chest_fx.get_node_or_null("Number") as CanvasItem
		if sample != null:
			sample.visible = false
		anchor.add_child(_chest_fx)
		return stage
	var burst := TextureRect.new()
	burst.texture = ArtLib.q("sprites/fx_sunburst") if ArtLib.has_q("sprites/fx_sunburst.png") else null
	burst.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	burst.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	burst.offset_top = -80
	burst.offset_bottom = 80
	burst.modulate.a = 0.8
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(burst)
	var chest := TextureRect.new()
	chest.name = "Chest"
	chest.texture = _chest_texture()
	chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chest.set_anchors_preset(Control.PRESET_CENTER)
	chest.offset_left = -120
	chest.offset_right = 120
	chest.offset_top = -100
	chest.offset_bottom = 110
	chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(chest)
	return stage


static func _chest_texture() -> Texture2D:
	for cut in ["sprites/chest_open", "sprites/chest_closed_hd", "sprites/chest_closed"]:
		if ArtLib.has_q(cut + ".png"):
			return ArtLib.q(cut)
	return ArtLib.icon("chest")


func _summary() -> Control:
	var plate := PanelContainer.new()
	plate.name = "SummaryRow"
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.custom_minimum_size = Vector2(0, 88)
	plate.add_theme_stylebox_override("panel", QKit.cut_box("plate_label_cream_66", 22, 0) if ArtLib.qui("plate_label_cream_66") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 4, 28, 4, 22, 0))
	var row := UiKit.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(row)
	row.add_child(QKit.cut_rect("icon_hourglass", Vector2(40, 52)))
	var away := QKit.title(str(_view.get("away_text", "")), 34, UiTokens.TEXT)
	away.name = "AwayLabel"
	row.add_child(away)
	var count_chip := QKit.tag(str(_view.get("item_count_text", "0 件")), "mint", 26, 12)
	count_chip.name = "ItemCountChip"
	row.add_child(count_chip)
	return plate


func _total_row() -> Control:
	var row := UiKit.hbox(10)
	row.name = "TotalRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiKit.icon("res_lotus", 84))
	var total := Label.new()
	total.name = "TotalLabel"
	total.text = str(_view.get("total_text", "+0"))
	var font := ArtLib.digits_font("xiuwei")
	if font != null:
		total.add_theme_font_override("font", font)
		total.add_theme_font_size_override("font_size", 84)
		total.add_theme_color_override("font_color", Color.WHITE)
	else:
		total.add_theme_font_override("font", ArtLib.title_font())
		total.add_theme_font_size_override("font_size", 72)
		total.add_theme_color_override("font_outline_color", Color("2e8fd8"))
		total.add_theme_constant_override("outline_size", 12)
	total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total.resized.connect(func() -> void: total.pivot_offset = total.size / 2.0)
	_total_label = total
	row.add_child(total)
	row.add_child(QKit.title("修为", 34, UiTokens.Q_BLUE_DARK))
	return row


func _buttons() -> Control:
	var foot := PanelContainer.new()
	foot.name = "StickyFooter"
	foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.size_flags_vertical = Control.SIZE_SHRINK_END
	var pad := StyleBoxFlat.new()
	pad.bg_color = Color(0, 0, 0, 0)
	pad.content_margin_top = 8
	pad.content_margin_bottom = 4
	foot.add_theme_stylebox_override("panel", pad)
	var row := UiKit.hbox(40)
	row.name = "ButtonRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_child(row)
	_claim_fx = QFx.make(QFx.BUTTON_BOUNCE) as Control
	if _claim_fx != null:
		_claim_fx.name = "ClaimFx"
		_claim_fx.custom_minimum_size = Vector2(400, 130)
		_claim_fx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_button = _claim_fx.get_node("Hit") as Button
		var label := _claim_fx.get_node_or_null("Text") as Label
		if label != null:
			label.text = CLAIM_LABEL
		row.add_child(_claim_fx)
	else:
		_button = QKit.button(CLAIM_LABEL, "o", 124, 48)
		_button.custom_minimum_size.x = 400
		row.add_child(_button)
	_button.name = "ClaimButton"
	_button.pressed.connect(_on_claim)
	_double = QKit.button("双倍领取", "m", 124, 48)
	_double.name = "DoubleButton"
	_double.custom_minimum_size.x = 360
	var video := QKit.cut_rect("icon_video", Vector2(64, 48))
	video.position = Vector2(-10, -26)
	_double.add_child(video)
	var badge := QKit.tag("×2", "red", 30, 12)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -80
	badge.offset_top = -22
	_double.add_child(badge)
	LockedFeature.wire(_double, "offline_double")
	QFx.bounce(_double)
	row.add_child(_double)
	return foot


func _on_claim() -> void:
	if _button == null or _button.disabled:
		return
	_button.disabled = true
	acknowledged.emit(report_id)


func claim_text() -> String:
	if _claim_fx != null:
		var label := _claim_fx.get_node_or_null("Text") as Label
		if label != null:
			return label.text
	return _button.text if _button != null else ""


func close_popup() -> void:
	_view = {}
	_close_gen += 1
	if _roll != null:
		_roll.kill()
	if _fx == null or not visible:
		visible = false
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	QFx.play(_fx, "close")
	var gen := _close_gen
	get_tree().create_timer(0.24).timeout.connect(func() -> void:
		if gen == _close_gen:
			visible = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP)
