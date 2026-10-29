class_name OfflinePopup
extends Control
## 离线收益弹窗（Q 版设计稿 q_offline_popup）：绶带「离线收益」、宝箱舞台、离线时长 + 「计入 N 小时」、
## 获得修为大数字（美术位图数字 digits_xiuwei）、基础 + 功法加成的算式、获得物品、「领取」「双倍领取」。
## 修为在服务器早已入账：「领取」（以及右上角关闭、点空白处）只是告诉服务器“已读”
## （POST /me/offline-reports/:id/ack）并关闭。「双倍领取」是看广告翻倍，还没有：点了提示「功能暂未开放」。
## 动画（2026-10-20 动画交付，README 2a/2b/5）：弹窗 ui_popup 的 open / close；宝箱 chest_open（关着轻抖 → 开盖 → 金光、
## 金币元宝灵石喷出 → 打开后循环发光）；「领取」用 ui_button_bounce（按下回弹），「双倍领取」同样的回弹。
## 获得修为大数字在宝箱打开时从 0 滚到真实值（场景自带的示例数字 Number 不用，避免同一个数显示两遍）。

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
var _fx: Control  # ui_popup 外壳（遮罩 + 弹出动画）；没有动画交付时为 null
var _host: Control  # 弹窗内容的父节点（_fx 的 Panel/Content，或自己）
var _claim_fx: Control  # ui_button_bounce「领取」
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
	_dim = dim  # 有动画时节点名保持 Backdrop（ui_popup 的 open / close 轨道按这个名字找）
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
	_ribbon.position = Vector2(540 - _ribbon.custom_minimum_size.x / 2.0, 424 + shift)
	_close.position = Vector2(948, 470 + shift)
	_close.size = Vector2(84, 89)
	if _fx != null:
		QFx.set_popup_pivot(_fx, Rect2(FRAME.position + Vector2(0, shift), FRAME.size))
	var pill := _host.get_node("FootPill") as Control
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
	_close_gen += 1
	visible = true
	if _fx != null:
		QFx.play(_fx, "open")
	_play_chest()


## 宝箱：关着轻抖 0.6s → 开盖（2.8s，第 1–2.2 秒数字从 0 滚到真实值）→ 打开后循环发光。
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


func _formula_text() -> String:
	var text := "基础 %s" % str(_view.get("base_text", "0"))
	if not str(_view.get("bonus_percent_text", "")).is_empty():
		text += " + %s %s %s" % [str(_view.get("skill_label", "技能加成")).replace("技能", "").replace("功法", ""), str(_view.get("bonus_percent_text", "")), str(_view.get("bonus_text", "+0")).trim_prefix("+")]
	return text


## 宝箱舞台（设计稿 94,610,892,390：浅蓝底 + 放射光 + 宝箱）。
func _stage() -> Control:
	var stage := Panel.new()
	stage.name = "ChestStage"
	stage.custom_minimum_size = Vector2(0, 390)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_theme_stylebox_override("panel", QSkin.custom(Color("d7f1fb"), Color(0, 0, 0, 0), 0, 30, 0, 0, 0))
	_chest_fx = QFx.make(QFx.CHEST) as Node2D
	if _chest_fx != null:
		# 动画宝箱（README 5）：锚点 = 设计稿 (540, 827.5)，即舞台 (94,610) 内 (446, 217.5)；宝箱底边落在 y=997。
		stage.clip_contents = false  # 金币、元宝喷出舞台
		var anchor := Control.new()
		anchor.name = "ChestAnchor"
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor.anchor_left = 0.5
		anchor.anchor_right = 0.5
		anchor.offset_top = 217.5
		anchor.offset_bottom = 217.5
		stage.add_child(anchor)
		_chest_fx.name = "ChestFx"
		var sample := _chest_fx.get_node_or_null("Number") as CanvasItem
		if sample != null:
			sample.visible = false  # 示例数字不用：真实数字在下面的 TotalLabel
		anchor.add_child(_chest_fx)
		return stage
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
	chest.texture = _chest_texture()
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


## 没有动画场景时：离线弹窗用打开的宝箱（美术 chest_open）；没有就退回 Q 版宝箱 / 旧图标。
static func _chest_texture() -> Texture2D:
	for cut in ["sprites/chest_open", "sprites/chest_closed_hd", "sprites/chest_closed"]:
		if ArtLib.has_q(cut + ".png"):
			return ArtLib.q(cut)
	return ArtLib.icon("chest")


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
	total.resized.connect(func() -> void: total.pivot_offset = total.size / 2.0)
	_total_label = total
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
	_claim_fx = QFx.make(QFx.BUTTON_BOUNCE) as Control
	if _claim_fx != null:
		# 「领 取」= ui_button_bounce（400×130，README 2a）：手指按下 / 松开时场景自己播 press / release，这里只接 Hit 的 pressed。
		_claim_fx.name = "ClaimFx"
		_claim_fx.custom_minimum_size = Vector2(400, 130)
		_claim_fx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_button = _claim_fx.get_node("Hit") as Button
		row.add_child(_claim_fx)
	else:
		_button = QKit.button("领取", "o", 124, 52)
		_button.custom_minimum_size.x = 400
		row.add_child(_button)
	_button.name = "ClaimButton"
	_button.pressed.connect(_on_claim)
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
	QFx.bounce(_double)
	row.add_child(_double)
	return row


func _on_claim() -> void:
	if _button == null or _button.disabled:
		return
	_button.disabled = true
	acknowledged.emit(report_id)


## 「领取」按钮上的字（动画按钮是「领 取」，没有动画时是按钮自己的字）。
func claim_text() -> String:
	if _claim_fx != null:
		return (_claim_fx.get_node("Text") as Label).text
	return _button.text if _button != null else ""


## 服务器确认已读（或失败后放弃）后调用。有动画时先播 close（0.22s）再隐藏；期间不再接点击。
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
