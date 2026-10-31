class_name OfflinePopup
extends Control
## 离线收益弹窗（样式改版）：顶部摘要（时长 / 战力 / 件数）+ 中部可滚分类折叠列表 + 底部吸底「一键领取」。
## 修为在服务器早已入账：「一键领取」（以及右上角关闭、点空白处）只是告诉服务器“已读”
## （POST /me/offline-reports/:id/ack）并关闭。「双倍领取」是看广告翻倍，还没有：点了提示「功能暂未开放」。
## 掉落公式 / 入账 / 服务端 API 不动，只改客户端布局。
## 动画：弹窗 ui_popup open/close；宝箱 chest_open；「一键领取」用 ui_button_bounce。

signal acknowledged(report_id: String)

const PANEL_WIDTH := 940.0
## 弹窗框在 1080 画布上的位置（设计稿 70,540,940,1270；状态栏 90 以下）。
const FRAME := Rect2(70, 540, 940, 1270)
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
var _category_bodies: Dictionary = {}


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
	_body = UiKit.vbox(14)
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
	_ribbon.position = Vector2(540 - _ribbon.custom_minimum_size.x / 2.0, 424 + shift)
	_close.position = Vector2(948, 470 + shift)
	_close.size = Vector2(84, 89)
	if _fx != null:
		QFx.set_popup_pivot(_fx, Rect2(FRAME.position + Vector2(0, shift), FRAME.size))
	var foot := _host.get_node("FootPill") as Control
	foot.position = Vector2(340, 1844 + shift)
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
	_category_bodies.clear()
	UiKit.clear(_body)
	_body.add_child(_stage())
	_body.add_child(_summary())
	_body.add_child(_total_row())
	var formula := UiKit.label(_formula_text(), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	formula.name = "Formula"
	_body.add_child(formula)
	var cap := UiKit.label(str(view.get("cap_note", "")), UiTokens.FS_MICRO, UiTokens.Q_ORANGE_DARK if bool(view.get("hit_cap", false)) else UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	cap.name = "CapNote"
	_body.add_child(cap)
	_body.add_child(_loot_scroll())
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


func _formula_text() -> String:
	var text := "基础 %s" % str(_view.get("base_text", "0"))
	if not str(_view.get("bonus_percent_text", "")).is_empty():
		text += " + %s %s %s" % [str(_view.get("skill_label", "技能加成")).replace("技能", "").replace("功法", ""), str(_view.get("bonus_percent_text", "")), str(_view.get("bonus_text", "+0")).trim_prefix("+")]
	return text


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
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(row)
	row.add_child(QKit.cut_rect("icon_hourglass", Vector2(40, 52)))
	var away := QKit.title(str(_view.get("away_text", "")), 34, UiTokens.TEXT)
	away.name = "AwayLabel"
	row.add_child(away)
	var counted := QKit.tag(str(_view.get("counted_text", "")), "orange", 26, 12)
	counted.name = "CountedChip"
	row.add_child(counted)
	if bool(_view.get("has_power", false)):
		var power_chip := QKit.tag("战力 %s" % str(_view.get("power_text", "")), "blue", 26, 12)
		power_chip.name = "PowerChip"
		row.add_child(power_chip)
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


func _loot_scroll() -> Control:
	var wrap := PanelContainer.new()
	wrap.name = "ItemsBox"
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.custom_minimum_size = Vector2(0, 220)
	wrap.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_CARD, Color(0, 0, 0, 0), 0, 22, 12, 18, 12))
	var col := UiKit.vbox(8)
	wrap.add_child(col)
	col.add_child(QKit.title("战利品", 30, UiTokens.TEXT_MUTED))
	var scroll := ScrollContainer.new()
	scroll.name = "LootScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 180)
	col.add_child(scroll)
	var list := UiKit.vbox(8)
	list.name = "LootList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var categories: Array = _view.get("categories", []) if typeof(_view.get("categories", null)) == TYPE_ARRAY else []
	var rows: Array = _view.get("items", []) if typeof(_view.get("items", null)) == TYPE_ARRAY else []
	var bag_note := str(_view.get("bag_full_note", ""))
	if categories.is_empty() and rows.is_empty() and bag_note.is_empty():
		var none := UiKit.label("本次离线只累计修为，没有获得物品", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		none.name = "LootEmpty"
		none.custom_minimum_size = Vector2(0, 80)
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		list.add_child(none)
	else:
		for entry in categories:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			list.add_child(_category_block(entry))
		if categories.is_empty():
			for entry in rows:
				if typeof(entry) == TYPE_DICTIONARY:
					list.add_child(_loot_line(entry))
	if not bag_note.is_empty():
		var warn := UiKit.label(bag_note, UiTokens.FS_MICRO, UiTokens.Q_ORANGE_DARK, HORIZONTAL_ALIGNMENT_CENTER)
		warn.name = "BagFullNote"
		list.add_child(warn)
	return wrap


func _category_block(entry: Dictionary) -> Control:
	var title := str(entry.get("title", "其他"))
	var count := int(entry.get("count", 0))
	var items: Array = entry.get("items", []) if typeof(entry.get("items", null)) == TYPE_ARRAY else []
	var box := UiKit.vbox(4)
	box.name = "Category_%s" % title
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Button.new()
	head.name = "CategoryHead"
	head.focus_mode = Control.FOCUS_NONE
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.text = "▼  %s（%d）" % [title, count]
	head.add_theme_font_size_override("font_size", 30)
	head.add_theme_color_override("font_color", UiTokens.TEXT)
	head.custom_minimum_size = Vector2(0, 56)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color("f3e6d2")
	flat.corner_radius_top_left = 16
	flat.corner_radius_top_right = 16
	flat.corner_radius_bottom_left = 16
	flat.corner_radius_bottom_right = 16
	flat.content_margin_left = 18
	flat.content_margin_right = 18
	flat.content_margin_top = 8
	flat.content_margin_bottom = 8
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		head.add_theme_stylebox_override(key, flat if key != "focus" else StyleBoxEmpty.new())
	var body := UiKit.vbox(4)
	body.name = "CategoryBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		if typeof(item) == TYPE_DICTIONARY:
			body.add_child(_loot_line(item))
	_category_bodies[title] = body
	head.pressed.connect(func() -> void: _toggle_category(title, head))
	box.add_child(head)
	box.add_child(body)
	return box


func _toggle_category(title: String, head: Button) -> void:
	if not _category_bodies.has(title):
		return
	var body: Control = _category_bodies[title]
	body.visible = not body.visible
	var count := 0
	for child in body.get_children():
		count += 1
	head.text = ("%s  %s（%d）" % ["▼" if body.visible else "▶", title, count])


func _loot_line(row: Dictionary) -> Control:
	var rarity := Catalog.quality_index(str(row.get("quality", ""))) if not str(row.get("quality", "")).is_empty() else 0
	var color := UiTokens.rarity_color(rarity).darkened(0.15) if not str(row.get("quality", "")).is_empty() else UiTokens.TEXT
	var line := UiKit.label("　" + str(row.get("text", row.get("name", ""))), UiTokens.FS_BODY, color, HORIZONTAL_ALIGNMENT_LEFT)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size = Vector2(0, 40)
	return line


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
