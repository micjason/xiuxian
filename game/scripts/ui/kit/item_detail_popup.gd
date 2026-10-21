class_name ItemDetailPopup
extends Control
## 物品详情弹窗（美术 2026-10-20 设计稿 q_popup_{equip,equip_worn,item,material}，SPEC_Q 第 13 节）。
## 换皮：数据来自 ItemDetailView（玩家状态 + 内容配置），按钮都是已有功能（穿戴 / 卸下 / 换一件 / 强化 / 一键强化 / 突破 / 分解 / 使用）。
## 场景：res://scenes/ui/item_detail_popup.tscn（根节点挂本脚本）；位置、字号、颜色全部在 LAYOUT / COLORS 里，改版只改这里。
## 用法：popup.show_view(ItemDetailView.build(...), handlers)。handlers 键：
##   equip(id) unequip(id) swap(id) use(id) enhance(id, to_max) breakthrough(id) decompose(id)
## 点遮罩 / 右上角 × / 底部按钮（确定）关闭。

signal closed

## 画布坐标（1080 宽）。弹窗框 x 60 宽 960；分区 x 90 宽 900（框内左右各 30）。
const LAYOUT := {
	"frame_x": 60.0, "frame_w": 960.0, "pad_x": 30.0, "pad_top": 76.0, "pad_bottom": 44.0, "shift_y": 10.0,
	"section_w": 900.0, "section_gap": 24.0, "button_gap": 30.0,
	"ribbon_dy": -56.0, "ribbon_w": 280.0, "ribbon_font": 62,
	"close_x": 958.0, "close_dy": -30.0, "close_size": 84.0,
	"foot_dy": 40.0, "foot_w": 400.0, "foot_h": 60.0,
	"head_h": 252.0, "slot": Rect2(26, 28, 196, 196), "name_pos": Vector2(252, 30), "chips_y": 110.0, "info_y": 172.0,
	"plate": Rect2(694, 40, 184, 136),
	"row_x": 20.0, "row_w": 860.0, "row_h": 74.0, "row_step": 88.0, "worn_row_h": 70.0, "worn_row_step": 80.0,
	"cmp_head_y": 86.0, "cmp_rows_y": 128.0, "col_this": 270.0, "col_worn": 490.0, "col_arrow": 658.0, "col_delta_r": 820.0,
	"attr_head_y": 28.0, "attr_rows_y": 72.0, "col_base": 350.0, "col_to": 500.0, "col_after": 650.0,
	"enh_h": 372.0, "enh_h_max": 140.0, "bar": Rect2(26, 152, 848, 40), "enh_btn_w": 409.0, "enh_btn_h": 100.0,
	"btn_h": 124.0, "btn2_w": 420.0, "btn3_w": 273.0, "btn1_w": 560.0,
	"max_frame_frac": 0.86,
}
const COLORS := {
	"text": Color("4a3a33"), "muted": Color("9a8478"), "warn": Color("b0614a"), "orange": Color("e07b24"), "arrow": Color("ff9f43"),
	"ok": Color("3c9a4e"), "bad": Color("d93a3f"), "plate_label": Color("9a6a3a"), "foot_bg": Color(0.157, 0.11, 0.086, 0.65), "foot_text": Color("fff8ec"),
	"up": Color("7ed36a"), "up_line": Color("2f7a3c"), "down": Color("ff5e5e"), "down_line": Color("a8323a"),
	"attack": Color("ff8a2a"), "defense": Color("2e7fc4"), "hp": Color("ff5a5f"), "speed": Color("3c9a4e"), "power": Color("e07b24"),
}
const RARITY_CHIP: Array[String] = ["grey", "green", "blue", "purple", "orange"]
const HY_FONT := "res://assets/fonts/ZCOOLQingKeHuangYou-Regular.subset.woff2"

var view: Dictionary = {}
var _handlers: Dictionary = {}
var _dim: ColorRect
var _frame: PanelContainer
var _column: VBoxContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _buttons: Control
var _reason: Label
var _ribbon: Control
var _ribbon_text: Label
var _close: Button
var _foot: Control
var _inset_top := 0.0
var _hy: Font


func _init() -> void:
	name = "ItemDetailPopup"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hy = load(HY_FONT) as Font if ResourceLoader.exists(HY_FONT) else ArtLib.title_font()
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close_popup())
	add_child(_dim)
	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var box: StyleBox
	if ArtLib.qui("popup_frame") != null:
		box = ArtLib.q_nine("popup_frame")
	else:
		box = QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 6, 48, 12, 0, 0)
	box.content_margin_left = LAYOUT.pad_x
	box.content_margin_right = LAYOUT.pad_x
	box.content_margin_top = LAYOUT.pad_top
	box.content_margin_bottom = LAYOUT.pad_bottom
	_frame.add_theme_stylebox_override("panel", box)
	add_child(_frame)
	_column = UiKit.vbox(int(LAYOUT.button_gap))
	_frame.add_child(_column)
	_scroll = ScrollContainer.new()
	_scroll.name = "BodyScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.add_child(_scroll)
	_body = UiKit.vbox(int(LAYOUT.section_gap))
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_buttons = Control.new()
	_buttons.name = "Buttons"
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_buttons)
	_reason = _label("", ArtLib.bold_font(), 30, COLORS.warn, HORIZONTAL_ALIGNMENT_CENTER)
	_reason.name = "Reason"
	_reason.visible = false
	_column.add_child(_reason)
	_ribbon = QKit.ribbon("", int(LAYOUT.ribbon_font), int(LAYOUT.ribbon_w), true)
	_ribbon.name = "Ribbon"
	_ribbon_text = _ribbon.find_child("RibbonText", true, false) as Label
	add_child(_ribbon)
	_close = Button.new()
	_close.name = "CloseButton"
	_close.focus_mode = Control.FOCUS_NONE
	var close_tex := ArtLib.qui("btn_close")
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		if close_tex != null and key != "focus":
			var tex_box := StyleBoxTexture.new()
			tex_box.texture = close_tex
			_close.add_theme_stylebox_override(key, tex_box)
		else:
			_close.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	if close_tex == null:
		_close.text = "✕"
	_close.pressed.connect(close_popup)
	add_child(_close)
	var pill := PanelContainer.new()
	pill.name = "FootPill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", QSkin.custom(COLORS.foot_bg, Color(0, 0, 0, 0), 0, 30, 0, 20, 0))
	var foot_label := _label("点击空白处关闭", ArtLib.bold_font(), 32, COLORS.foot_text, HORIZONTAL_ALIGNMENT_CENTER)
	foot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill.add_child(foot_label)
	_foot = pill
	add_child(pill)


func set_safe_top(inset_top: float) -> void:
	_inset_top = inset_top
	if visible:
		_layout()


func handlers() -> Dictionary:
	return _handlers


func show_view(data: Dictionary, handler_map: Dictionary) -> void:
	view = data
	_handlers = handler_map
	_ribbon_text.text = str(view.get("title", "物品详情"))
	UiKit.clear(_body)
	UiKit.clear(_buttons)
	_reason.visible = false
	_body.add_child(_head())
	match str(view.get("type", "")):
		"equip", "equip_worn":
			if view.has("compare"):
				_body.add_child(_compare_section(view.compare))
			else:
				_body.add_child(_attrs_section(view.attrs, str(view.type) == "equip_worn"))
			if not (view.get("set", {}) as Dictionary).is_empty():
				_body.add_child(_set_section(view.set))
			var enh: Dictionary = view.get("enhance_block", {})
			if str(enh.get("mode", "none")) != "none":
				_body.add_child(_enhance_section(enh))
			_gear_buttons()
		"book":
			_body.add_child(_book_section())
			if not (view.get("sources", []) as Array).is_empty():
				_body.add_child(_source_row())
			_single_button("使 用", "o", func() -> void: _fire("use", [view.id]))
		_:
			_body.add_child(_material_section())
			if not (view.get("sources", []) as Array).is_empty():
				_body.add_child(_source_section())
			_single_button("确 定", "o", close_popup)
	visible = true
	move_to_front()
	_layout()
	await get_tree().process_frame
	_layout()
	_pop_in()


func close_popup() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func button_named(text: String) -> Button:
	for node in _buttons.find_children("*", "Button", true, false):
		if str((node as Button).get_meta(&"label", (node as Button).text)) == text:
			return node as Button
	for node in _body.find_children("*", "Button", true, false):
		if str((node as Button).get_meta(&"label", (node as Button).text)) == text:
			return node as Button
	return null


func texts() -> Array[String]:
	var out: Array[String] = []
	for node in find_children("*", "Label", true, false):
		if (node as Label).is_visible_in_tree() and not (node as Label).text.is_empty():
			out.append((node as Label).text)
	return out


func frame_rect() -> Rect2:
	return _frame.get_global_rect()


func _fire(key: String, args: Array) -> void:
	close_popup()
	var callback: Variant = _handlers.get(key, null)
	if callback is Callable:
		(callback as Callable).callv(args)


func _layout() -> void:
	var vp := get_viewport_rect().size if is_inside_tree() else UiTokens.BASE_SIZE
	var body_h := _body.get_combined_minimum_size().y
	var rest := float(LAYOUT.pad_top) + float(LAYOUT.pad_bottom) + LAYOUT.button_gap + _buttons.custom_minimum_size.y
	if _reason.visible:
		rest += LAYOUT.button_gap + _reason.get_combined_minimum_size().y
	var max_h := vp.y * float(LAYOUT.max_frame_frac) - _inset_top
	_scroll.custom_minimum_size = Vector2(LAYOUT.section_w, minf(body_h, max_h - rest))
	var frame_h := _scroll.custom_minimum_size.y + rest
	var top := maxf((vp.y - frame_h) / 2.0 + float(LAYOUT.shift_y), _inset_top + 80.0)
	_frame.position = Vector2(LAYOUT.frame_x, top)
	_frame.size = Vector2(LAYOUT.frame_w, frame_h)
	_ribbon.position = Vector2(540.0 - _ribbon.custom_minimum_size.x / 2.0, top + float(LAYOUT.ribbon_dy))
	_close.position = Vector2(LAYOUT.close_x, top + float(LAYOUT.close_dy))
	_close.size = Vector2(LAYOUT.close_size, LAYOUT.close_size)
	_foot.position = Vector2(540.0 - float(LAYOUT.foot_w) / 2.0, top + frame_h + float(LAYOUT.foot_dy))
	_foot.size = Vector2(LAYOUT.foot_w, LAYOUT.foot_h)
	_foot.visible = _foot.position.y + LAYOUT.foot_h < vp.y - 20.0


func _pop_in() -> void:
	_frame.pivot_offset = _frame.size / 2.0
	_frame.scale = Vector2(0.92, 0.92)
	var tween := create_tween()
	tween.tween_property(_frame, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------- 小部件 ----------

func _label(text: String, font: Font, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, outline: Color = Color(0, 0, 0, 0), outline_size: int = 0) -> Label:
	var node := Label.new()
	node.text = text
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.horizontal_alignment = align as HorizontalAlignment
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font != null:
		node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if outline_size > 0:
		node.add_theme_color_override("font_outline_color", outline)
		node.add_theme_constant_override("outline_size", outline_size)
	return node


## 绝对定位放一个控件（分区里的表格按设计稿坐标排）。
func _put(parent: Control, node: Control, rect: Rect2) -> Control:
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node


## x 是中心或右边缘：align CENTER → 以 x 为中心；RIGHT → 右边缘在 x。
func _text_at(parent: Control, text: String, font: Font, size: int, color: Color, x: float, y: float, h: float, align: int, w: float = 300.0, outline: Color = Color(0, 0, 0, 0), outline_size: int = 0) -> Label:
	var node := _label(text, font, size, color, align, outline, outline_size)
	var left := x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		left = x - w / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		left = x - w
	_put(parent, node, Rect2(left, y, w, h))
	return node


func _section(height: float, cut: String = "well_apricot") -> Control:
	var holder := Panel.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(LAYOUT.section_w, height)
	var box: StyleBox = ArtLib.q_nine(cut) if ArtLib.qui(cut) != null else QSkin.custom(Color("fcebd0"), Color(0, 0, 0, 0), 0, 30, 0, 0, 0)
	holder.add_theme_stylebox_override("panel", box)
	return holder


func _row_bg(parent: Control, y: float, h: float, gold: bool = false) -> Panel:
	var row := Panel.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cut := "row_gold_74" if gold else "row_cream_74"
	var box: StyleBox
	if ArtLib.qui(cut) != null:
		box = ArtLib.q_nine(cut)
	else:
		box = QSkin.custom(Color("fff2cf") if gold else UiTokens.Q_CREAM, UiTokens.Q_COCOA, 3, int(h / 2.0), 0, 0, 0)
	row.add_theme_stylebox_override("panel", box)
	_put(parent, row, Rect2(LAYOUT.row_x, y, LAYOUT.row_w, h))
	return row


func _slot(item: Dictionary, size: float, show_badges: bool = true) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(size, size)
	var rarity := clampi(int(item.get("rarity", 0)), 0, 5)
	var back := TextureRect.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.texture = ArtLib.qui("slot_" + ItemDetailView.QUALITY_KEYS[rarity])
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(back)
	var art := KitStyle.icon_for(item)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = art.get("texture", null) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := size * 0.16
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
	holder.add_child(icon)
	if show_badges:
		var enhance := int(item.get("enhance", 0))
		if enhance > 0:
			_put(holder, _label("+%d" % enhance, ArtLib.title_font(), 30, UiTokens.Q_WHITE, HORIZONTAL_ALIGNMENT_LEFT, UiTokens.Q_COCOA, 8), Rect2(12, 4, 120, 44)).name = "EnhanceBadge"
		var qty := int(item.get("qty", 1))
		if qty > 1:
			_put(holder, _label("%d" % qty, ArtLib.title_font(), 36, UiTokens.Q_WHITE, HORIZONTAL_ALIGNMENT_RIGHT, UiTokens.Q_COCOA, 8), Rect2(size - 132, size - 54, 120, 50)).name = "QtyBadge"
	return holder


func _chip(text: String, fill: String) -> Control:
	var chip := QKit.tag(text, fill, 30, 16)
	chip.custom_minimum_size = Vector2(112, 44)
	return chip


func _arrow(parent: Control, delta: int, y: float) -> void:
	if delta == 0:
		_text_at(parent, "－ 持平", ArtLib.bold_font(), 32, COLORS.muted, LAYOUT.col_delta_r, y, LAYOUT.row_h, HORIZONTAL_ALIGNMENT_RIGHT, 200.0)
		return
	var up := delta > 0
	var cut := "arrow_up_green" if up else "arrow_down_red"
	var arrow := QKit.cut_rect(cut, Vector2(30, 44))
	arrow.name = "ArrowUp" if up else "ArrowDown"
	_put(parent, arrow, Rect2(LAYOUT.col_arrow, y + 14.0, 30, 44))
	var text := ("+%d" % delta) if up else ("%d" % delta)
	var label := _text_at(parent, text, _hy, 46, COLORS.up if up else COLORS.down, LAYOUT.col_delta_r, y, LAYOUT.row_h, HORIZONTAL_ALIGNMENT_RIGHT, 122.0, COLORS.up_line if up else COLORS.down_line, 8)
	label.name = "Delta"


func _button(text: String, kind: String, height: int, font_size: int, sub: String = "") -> Button:
	var button := QKit.button(text if sub.is_empty() else "", kind, height, font_size)
	button.set_meta(&"label", text)
	button.name = "Btn_" + text.replace(" ", "")
	if not sub.is_empty():
		var column := UiKit.vbox(0)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.set_anchors_preset(Control.PRESET_FULL_RECT)
		column.offset_bottom = -8
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(_label(text, ArtLib.title_font(), font_size, Color("f6f1ec") if kind == "g" else UiTokens.Q_WHITE, HORIZONTAL_ALIGNMENT_CENTER, UiTokens.Q_COCOA, 10))
		var sub_label := _label(sub, ArtLib.bold_font(), 30, Color("f6f1ec") if kind == "g" else UiTokens.Q_WHITE, HORIZONTAL_ALIGNMENT_CENTER, UiTokens.Q_COCOA, 6)
		sub_label.name = "Sub"
		column.add_child(sub_label)
		button.add_child(column)
	return button


# ---------- 分区 ----------

func _head() -> Control:
	var section := _section(LAYOUT.head_h)
	section.name = "HeadSection"
	var item: Dictionary = view.get("item", {})
	var slot_rect: Rect2 = LAYOUT.slot
	var slot := _slot(item, slot_rect.size.x)
	slot.name = "BigSlot"
	_put(section, slot, slot_rect)
	var has_plate := str(view.type).begins_with("equip")
	var name_w := 430.0 if has_plate else 620.0
	var title := _label(str(view.name), ArtLib.title_font(), 54, view.name_color as Color)
	title.name = "ItemName"
	title.clip_text = true
	_put(section, title, Rect2(LAYOUT.name_pos, Vector2(name_w, 70)))
	var chips := UiKit.hbox(12)
	chips.name = "Chips"
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_child(_chip(str(view.rarity_name), RARITY_CHIP[clampi(int(view.rarity), 0, RARITY_CHIP.size() - 1)]))
	chips.add_child(_chip(str(view.kind_text), "cream"))
	if bool(view.get("worn_chip", false)):
		chips.add_child(_chip("已穿戴", "mint"))
	_put(section, chips, Rect2(LAYOUT.name_pos.x, LAYOUT.chips_y, name_w, 44))
	var info := _label(str(view.get("info", "")), ArtLib.bold_font(), 32, COLORS.muted)
	info.name = "Info"
	_put(section, info, Rect2(LAYOUT.name_pos.x, LAYOUT.info_y, name_w, 56))
	if has_plate:
		var plate_rect: Rect2 = LAYOUT.plate
		var plate := Panel.new()
		plate.name = "PowerPlate"
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_theme_stylebox_override("panel", ArtLib.q_nine("plate_gold_r30") if ArtLib.qui("plate_gold_r30") != null else QSkin.custom(Color("ffe39a"), UiTokens.Q_COCOA, 4, 30, 6, 0, 0))
		_put(section, plate, plate_rect)
		_put(plate, _label("战力", ArtLib.bold_font(), 30, COLORS.plate_label, HORIZONTAL_ALIGNMENT_CENTER), Rect2(0, 10, plate_rect.size.x, 40))
		var value := _label(str(int(view.power)), _hy, 56, UiTokens.Q_WHITE, HORIZONTAL_ALIGNMENT_CENTER, COLORS.orange, 9)
		value.name = "PowerValue"
		_put(plate, value, Rect2(0, 48, plate_rect.size.x, 72))
	return section


func _stat_color(key: String) -> Color:
	return COLORS.get(key, COLORS.text) as Color


func _compare_section(data: Dictionary) -> Control:
	var rows: Array = data.get("rows", [])
	var n := rows.size() + 1
	var section := _section(LAYOUT.cmp_rows_y + n * LAYOUT.row_step + 10.0)
	section.name = "CompareSection"
	_put(section, _label("属性对比", ArtLib.title_font(), 34, COLORS.muted), Rect2(26, 14, 300, 52))
	var worn_text := "身上：[color=#%s]%s%s[/color]" % [ItemDetailView.quality_dark(int(data.worn_rarity), true).to_html(false), str(data.worn_name), (" +%d" % int(data.worn_enhance)) if int(data.worn_enhance) > 0 else ""]
	var worn := RichTextLabel.new()
	worn.name = "WornName"
	worn.bbcode_enabled = true
	worn.fit_content = true
	worn.scroll_active = false
	worn.autowrap_mode = TextServer.AUTOWRAP_OFF
	worn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	worn.add_theme_font_override("normal_font", ArtLib.bold_font())
	worn.add_theme_font_size_override("normal_font_size", 32)
	worn.add_theme_color_override("default_color", COLORS.muted)
	worn.text = "[right]%s[/right]" % worn_text
	_put(section, worn, Rect2(220, 22, 560, 48))
	var mini := _slot(data.get("worn_item", {}), 68, false)
	mini.name = "WornSlot"
	_put(section, mini, Rect2(800, 10, 68, 68))
	for spec in [["本件", LAYOUT.col_this, HORIZONTAL_ALIGNMENT_CENTER], ["身上", LAYOUT.col_worn, HORIZONTAL_ALIGNMENT_CENTER], ["变化", LAYOUT.col_delta_r, HORIZONTAL_ALIGNMENT_RIGHT]]:
		_text_at(section, str(spec[0]), ArtLib.bold_font(), 30, COLORS.muted, float(spec[1]), LAYOUT.cmp_head_y - 6.0, 44, int(spec[2]), 160.0)
	var all_rows: Array = rows.duplicate()
	var power: Dictionary = data.get("power", {})
	all_rows.append({"key": "power", "label": "战力", "value": int(power.get("value", 0)), "other": int(power.get("other", 0)), "delta": int(power.get("delta", 0))})
	for i in all_rows.size():
		var row: Dictionary = all_rows[i]
		var y: float = LAYOUT.cmp_rows_y + i * LAYOUT.row_step
		var is_power := str(row.key) == "power"
		var bg := _row_bg(section, y, LAYOUT.row_h, is_power)
		bg.name = "Row_" + str(row.key)
		_text_at(section, str(row.label), ArtLib.title_font(), 36, COLORS.power if is_power else COLORS.text, 54, y, LAYOUT.row_h, HORIZONTAL_ALIGNMENT_LEFT, 160.0)
		_text_at(section, str(row.value), ArtLib.title_font(), 44, _stat_color(str(row.key)), LAYOUT.col_this, y, LAYOUT.row_h, HORIZONTAL_ALIGNMENT_CENTER, 180.0).name = "This_" + str(row.key)
		_text_at(section, str(row.other), ArtLib.title_font(), 34, COLORS.muted, LAYOUT.col_worn, y, LAYOUT.row_h, HORIZONTAL_ALIGNMENT_CENTER, 180.0).name = "Worn_" + str(row.key)
		var cell := Control.new()
		cell.name = "Change_" + str(row.key)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_put(section, cell, Rect2(0, 0, LAYOUT.section_w, 1))
		_arrow(cell, int(row.delta), y)
	return section


func _attrs_section(data: Dictionary, worn: bool) -> Control:
	var rows: Array = (data.get("rows", []) as Array).duplicate()
	rows.append({"key": "power", "label": "战力", "base": -1, "value": int(data.get("power", 0))})
	var h: float = LAYOUT.attr_rows_y + rows.size() * LAYOUT.worn_row_step + 2.0
	var section := _section(h)
	section.name = "AttrSection"
	_put(section, _label("属性", ArtLib.title_font(), 34, COLORS.muted), Rect2(26, 14, 200, 52))
	var enhance := int(data.get("enhance", 0))
	_text_at(section, "基础", ArtLib.bold_font(), 30, COLORS.muted, LAYOUT.col_base, LAYOUT.attr_head_y - 6.0, 44, HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	_text_at(section, ("强化 +%d 后" % enhance) if enhance > 0 else "当前", ArtLib.bold_font(), 30, COLORS.muted, LAYOUT.col_after, LAYOUT.attr_head_y - 6.0, 44, HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	for i in rows.size():
		var row: Dictionary = rows[i]
		var y: float = LAYOUT.attr_rows_y + i * LAYOUT.worn_row_step
		var is_power := str(row.key) == "power"
		_row_bg(section, y, LAYOUT.worn_row_h, is_power).name = "Row_" + str(row.key)
		_text_at(section, str(row.label), ArtLib.title_font(), 36, COLORS.power if is_power else COLORS.text, 54, y, LAYOUT.worn_row_h, HORIZONTAL_ALIGNMENT_LEFT, 160.0)
		_text_at(section, "—" if int(row.base) < 0 else str(row.base), ArtLib.title_font(), 34, COLORS.muted, LAYOUT.col_base, y, LAYOUT.worn_row_h, HORIZONTAL_ALIGNMENT_CENTER, 180.0).name = "Base_" + str(row.key)
		_text_at(section, "➜", ArtLib.title_font(), 40, COLORS.arrow, LAYOUT.col_to, y, LAYOUT.worn_row_h, HORIZONTAL_ALIGNMENT_CENTER, 60.0)
		_text_at(section, str(row.value), ArtLib.title_font(), 44, _stat_color(str(row.key)), LAYOUT.col_after, y, LAYOUT.worn_row_h, HORIZONTAL_ALIGNMENT_CENTER, 180.0).name = "After_" + str(row.key)
	return section


func _enhance_section(data: Dictionary) -> Control:
	var mode := str(data.get("mode", ""))
	var cap := int(data.get("cap", 0))
	var level := int(data.get("level", 0))
	if mode == "max":
		var done := _section(LAYOUT.enh_h_max)
		done.name = "EnhanceSection"
		_put(done, _label("强化", ArtLib.title_font(), 34, COLORS.muted), Rect2(26, 14, 200, 52))
		_put(done, _label("已强化到上限 +%d" % cap, ArtLib.title_font(), 36, COLORS.orange), Rect2(26, 70, 600, 52))
		return done
	var id := str(view.id)
	var pending: Dictionary = data.get("pending", {})
	var materials: Array = pending.get("materials", [])
	var h: float = LAYOUT.enh_h
	if mode == "break":
		h = maxf(h, 76.0 + materials.size() * 84.0 + 20.0 + LAYOUT.enh_btn_h + 70.0)
	var section := _section(h)
	section.name = "EnhanceSection"
	_put(section, _label("强化", ArtLib.title_font(), 34, COLORS.muted), Rect2(26, 14, 200, 52))
	var levels := UiKit.hbox(8)
	levels.name = "Levels"
	levels.alignment = BoxContainer.ALIGNMENT_END
	levels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	levels.add_child(_label("+%d" % level, ArtLib.title_font(), 40, COLORS.text))
	levels.add_child(_label("➜", ArtLib.title_font(), 40, COLORS.arrow))
	levels.add_child(_label("+%d" % (level + 1), ArtLib.title_font(), 40, COLORS.orange))
	levels.add_child(_label("  上限 +%d" % cap, ArtLib.bold_font(), 30, COLORS.muted))
	_put(section, levels, Rect2(300, 12, 574, 56))
	if mode == "break":
		var y := 76.0
		for material in materials:
			var enough := int(material.have) >= int(material.need)
			_row_bg(section, y, LAYOUT.row_h)
			_text_at(section, str(material.name), ArtLib.title_font(), 34, COLORS.text, 54, y, LAYOUT.row_h, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
			_text_at(section, "%s %d / %d" % ["✓" if enough else "✗", int(material.have), int(material.need)], ArtLib.title_font(), 36, COLORS.ok if enough else COLORS.bad, 840, y, LAYOUT.row_h, HORIZONTAL_ALIGNMENT_RIGHT, 300.0)
			y += 84.0
		var ready := bool(pending.get("ready", false))
		var go := _button("突 破", "o" if ready else "g", int(LAYOUT.enh_btn_h), 40)
		go.disabled = not ready
		go.pressed.connect(func() -> void: _fire("breakthrough", [id]))
		_put(section, go, Rect2(26, y + 20.0, 848, LAYOUT.enh_btn_h))
		var note := "已到突破节点 +%d：交齐材料突破后才能继续强化（突破不会失败）" % level if ready else "材料不足，凑齐后才能突破"
		_put(section, _label(note, ArtLib.bold_font(), 30, COLORS.muted if ready else COLORS.warn), Rect2(26, y + 20.0 + LAYOUT.enh_btn_h + 10.0, 848, 44))
		return section
	var icon := QKit.cut_rect("icon_enhance_exp", Vector2(60, 60))
	_put(section, icon, Rect2(22, 76, 60, 60))
	_put(section, _label("强化经验", ArtLib.bold_font(), 32, COLORS.muted), Rect2(94, 80, 300, 52))
	var enough := bool(data.get("enough", false))
	var pool_row := UiKit.hbox(6)
	pool_row.name = "Pool"
	pool_row.alignment = BoxContainer.ALIGNMENT_END
	pool_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pool_row.add_child(_label(str(int(data.pool)), ArtLib.title_font(), 42, COLORS.ok if enough else COLORS.warn))
	pool_row.add_child(_label("/ %d" % int(data.cost), ArtLib.bold_font(), 32, COLORS.muted))
	_put(section, pool_row, Rect2(474, 76, 400, 60))
	var bar_rect: Rect2 = LAYOUT.bar
	var track := Panel.new()
	track.name = "ExpBar"
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_theme_stylebox_override("panel", ArtLib.q_nine("bar_bg_40") if ArtLib.qui("bar_bg_40") != null else QSkin.custom(UiTokens.Q_TRACK, UiTokens.Q_COCOA, 3, 20, 0, 0, 0))
	_put(section, track, bar_rect)
	var ratio := float(data.get("ratio", 0.0))
	if ratio > 0.0:
		var fill := Panel.new()
		fill.name = "ExpFill"
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill_cut := "bar_fill_gold_32" if enough else "bar_fill_mint_32"
		fill.add_theme_stylebox_override("panel", ArtLib.q_nine(fill_cut) if ArtLib.qui(fill_cut) != null else QSkin.custom(UiTokens.Q_GOLD if enough else UiTokens.Q_MINT, Color(0, 0, 0, 0), 0, 16, 0, 0, 0))
		_put(track, fill, Rect2(4, 4, maxf(32.0, (bar_rect.size.x - 8.0) * ratio), bar_rect.size.y - 8.0))
	var one := _button("强 化", "m" if enough else "g", int(LAYOUT.enh_btn_h), 40)
	one.disabled = not enough
	one.pressed.connect(func() -> void: _fire("enhance", [id, false]))
	_put(section, one, Rect2(26, 214, LAYOUT.enh_btn_w, LAYOUT.enh_btn_h))
	var many := _button("一键强化", "m" if enough else "g", int(LAYOUT.enh_btn_h), 40)
	many.disabled = not enough
	many.pressed.connect(func() -> void: _fire("enhance", [id, true]))
	_put(section, many, Rect2(465, 214, LAYOUT.enh_btn_w, LAYOUT.enh_btn_h))
	var foot := str(data.get("next_text", ""))
	if not enough:
		foot = "强化经验不足：分解不用的装备可以获得强化经验" if foot.is_empty() else foot
	_put(section, _label(foot, ArtLib.bold_font(), 30, COLORS.muted), Rect2(26, 322, 848, 44)).name = "EnhanceFoot"
	return section


func _gear_buttons() -> void:
	var id := str(view.id)
	var decompose: Dictionary = view.get("decompose", {})
	var blocked := str(decompose.get("blocked", ""))
	var h := int(LAYOUT.btn_h)
	if str(view.type) == "equip_worn":
		_buttons.custom_minimum_size = Vector2(LAYOUT.section_w, h + 6)
		var w: float = LAYOUT.btn3_w
		var gap := (LAYOUT.section_w - 20.0 - w * 3.0) / 2.0
		var split := _button("分 解", "g", h, 46, "已穿戴")
		split.disabled = true
		_put(_buttons, split, Rect2(10, 0, w, h))
		var swap := _button("换一件", "m", h, 46)
		swap.pressed.connect(func() -> void: _fire("swap", [id]))
		_put(_buttons, swap, Rect2(10 + w + gap, 0, w, h))
		var off := _button("卸 下", "o", h, 54)
		off.pressed.connect(func() -> void: _fire("unequip", [id]))
		_put(_buttons, off, Rect2(10 + (w + gap) * 2.0, 0, w, h))
		if not blocked.is_empty():
			_reason.text = "已穿戴的装备不能分解，请先卸下" if blocked == "已穿戴，无法分解" else blocked
			_reason.visible = true
		return
	_buttons.custom_minimum_size = Vector2(LAYOUT.section_w, h + 6)
	var w2: float = LAYOUT.btn2_w
	var split2 := _button("分 解", "m" if blocked.is_empty() else "g", h, 46, ("+%d 强化经验" % int(decompose.get("exp", 0))) if blocked.is_empty() else blocked)
	split2.disabled = not blocked.is_empty()
	split2.pressed.connect(func() -> void: _fire("decompose", [id]))
	_put(_buttons, split2, Rect2(10, 0, w2, h))
	var ok := bool(view.get("equip_ok", true))
	var wear := _button("穿 戴", "o" if ok else "g", h, 54)
	wear.disabled = not ok
	wear.pressed.connect(func() -> void: _fire("equip", [id]))
	_put(_buttons, wear, Rect2(LAYOUT.section_w - 10.0 - w2, 0, w2, h))
	if not ok:
		_reason.text = ("需要 %s 才能穿戴" % str(view.get("realm_need", ""))) if not bool(view.get("realm_ok", true)) else "这个部位暂未开放"
		_reason.visible = true


func _single_button(text: String, kind: String, action: Callable) -> void:
	var h := int(LAYOUT.btn_h)
	_buttons.custom_minimum_size = Vector2(LAYOUT.section_w, h + 6)
	var button := _button(text, kind, h, 56)
	button.pressed.connect(action)
	_put(_buttons, button, Rect2((LAYOUT.section_w - LAYOUT.btn1_w) / 2.0, 0, LAYOUT.btn1_w, h))


## 容器版分区（说明 / 用途 / 来源：文字长短不定，用容器排）。
func _flow_section(title: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(LAYOUT.section_w, 0)
	var box: StyleBox = (ArtLib.q_nine("well_apricot") if ArtLib.qui("well_apricot") != null else QSkin.custom(Color("fcebd0"), Color(0, 0, 0, 0), 0, 30, 0, 0, 0)).duplicate()
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 18
	box.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", box)
	var column := UiKit.vbox(14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	if not title.is_empty():
		column.add_child(_label(title, ArtLib.title_font(), 34, COLORS.muted))
	return {"panel": panel, "body": column}


func _wrap(text: String, font: Font, size: int, color: Color) -> Label:
	var node := _label(text, font, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size = Vector2(LAYOUT.section_w - 52.0, 0)
	return node


func _flow_row(left: Control, right: Control, width: float = 0.0) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: StyleBox = (ArtLib.q_nine("row_cream_74") if ArtLib.qui("row_cream_74") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 3, 37, 0, 0, 0)).duplicate()
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(width, LAYOUT.row_h)
	var row := UiKit.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	if right != null:
		row.add_child(right)
	return panel


func _book_section() -> Control:
	var skill: Dictionary = view.get("skill", {})
	var flow := _flow_section("说明")
	(flow.panel as Control).name = "DescSection"
	var desc := str(view.get("desc", ""))
	if not desc.is_empty():
		(flow.body as VBoxContainer).add_child(_wrap(desc, ArtLib.bold_font(), 34, COLORS.text))
	if not str(skill.get("name", "")).is_empty():
		var left := UiKit.hbox(12)
		left.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var book_icon := TextureRect.new()
		book_icon.texture = KitStyle.icon_for(view.get("item", {})).get("texture", null) as Texture2D
		book_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		book_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		book_icon.custom_minimum_size = Vector2(56, 56)
		book_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		book_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left.add_child(book_icon)
		left.add_child(_label("%s · %s" % [str(skill.name), str(skill.role)], ArtLib.title_font(), 34, COLORS.text))
		var bonus := _label(str(skill.get("bonus", "")), ArtLib.bold_font(), 32, COLORS.ok, HORIZONTAL_ALIGNMENT_RIGHT)
		bonus.name = "SkillBonus"
		var skill_row := _flow_row(left, bonus)
		skill_row.name = "SkillRow"
		(flow.body as VBoxContainer).add_child(skill_row)
		var now := UiKit.hbox(10)
		now.mouse_filter = Control.MOUSE_FILTER_IGNORE
		now.add_child(_label("当前", ArtLib.bold_font(), 32, COLORS.muted))
		now.add_child(_label(str(skill.now_text), ArtLib.title_font(), 36, COLORS.text))
		now.add_child(_label("➜", ArtLib.title_font(), 36, COLORS.arrow))
		now.add_child(_label(str(skill.next_text), ArtLib.title_font(), 36, COLORS.orange))
		var level_row := _flow_row(now, _label("最多 %d 层" % int(skill.max), ArtLib.bold_font(), 30, COLORS.muted, HORIZONTAL_ALIGNMENT_RIGHT))
		level_row.name = "LevelRow"
		(flow.body as VBoxContainer).add_child(level_row)
		(flow.body as VBoxContainer).add_child(_wrap(str(skill.hint), ArtLib.bold_font(), 30, COLORS.muted))
	return flow.panel


func _source_row() -> Control:
	var panel := PanelContainer.new()
	panel.name = "SourceRow"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(LAYOUT.section_w, 96)
	panel.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 4, 48, 0, 30, 10))
	var row := UiKit.hbox(20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	row.add_child(_label("来源", ArtLib.title_font(), 32, COLORS.muted))
	var text := _label("；".join(view.get("sources", [])), ArtLib.bold_font(), 36, COLORS.text)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	return panel


func _material_section() -> Control:
	var flow := _flow_section("说明")
	(flow.panel as Control).name = "DescSection"
	var body := flow.body as VBoxContainer
	var desc := str(view.get("desc", ""))
	if not desc.is_empty():
		body.add_child(_wrap(desc, ArtLib.bold_font(), 34, COLORS.text))
	var usage: Dictionary = view.get("usage", {})
	if not usage.is_empty():
		body.add_child(_label(str(usage.title), ArtLib.title_font(), 34, COLORS.muted))
		var grid := GridContainer.new()
		grid.name = "UsageGrid"
		grid.columns = 2
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_theme_constant_override("h_separation", 20)
		grid.add_theme_constant_override("v_separation", 14)
		for row in usage.rows:
			var name_label := _label(str(row.name), ArtLib.title_font(), 34, ItemDetailView.quality_dark(int(row.rarity)))
			var count := _label("×%d" % int(row.count), ArtLib.title_font(), 40, COLORS.text, HORIZONTAL_ALIGNMENT_RIGHT)
			grid.add_child(_flow_row(name_label, count, (LAYOUT.section_w - 52.0 - 20.0) / 2.0))
		body.add_child(grid)
		if not str(usage.get("note", "")).is_empty():
			body.add_child(_wrap(str(usage.note), ArtLib.bold_font(), 30, COLORS.muted))
	if desc.is_empty() and usage.is_empty():
		body.add_child(_label("暂无说明", ArtLib.bold_font(), 32, COLORS.muted))
	return flow.panel


## 套装（批次②）：套装名 + 已有 / 穿戴件数、成员（✓ 穿着、○ 已有未穿、· 没有）、各档加成（穿够的亮绿色）。
func _set_section(data: Dictionary) -> Control:
	var flow := _flow_section("")
	(flow.panel as Control).name = "SetSection"
	var body := flow.body as VBoxContainer
	var head := UiKit.hbox(16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label("套装 · %s" % str(data.name), ArtLib.title_font(), 36, COLORS.orange)
	title.name = "SetName"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var count := _label(str(data.summary), ArtLib.bold_font(), 30, COLORS.muted, HORIZONTAL_ALIGNMENT_RIGHT)
	count.name = "SetCount"
	head.add_child(count)
	body.add_child(head)
	var grid := GridContainer.new()
	grid.name = "SetMembers"
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	for member in data.members:
		var mark := "✓" if bool(member.worn) else ("○" if bool(member.owned) else "·")
		var color: Color = COLORS.ok if bool(member.worn) else (COLORS.text if bool(member.owned) else COLORS.muted)
		var text := _label("%s %s · %s" % [mark, str(member.slot_name), str(member.name)], ArtLib.bold_font(), 30, color)
		text.custom_minimum_size = Vector2((LAYOUT.section_w - 52.0 - 20.0) / 2.0, 0)
		text.clip_text = true
		grid.add_child(text)
	body.add_child(grid)
	for tier in data.tiers:
		var line := _wrap(("● " if bool(tier.active) else "○ ") + str(tier.text), ArtLib.bold_font(), 32, COLORS.ok if bool(tier.active) else COLORS.muted)
		line.name = "SetTier%d" % int(tier.pieces)
		body.add_child(line)
	return flow.panel


func _source_section() -> Control:
	var flow := _flow_section("来源")
	(flow.panel as Control).name = "SourceSection"
	(flow.body as VBoxContainer).add_child(_wrap("；".join(view.get("sources", [])), ArtLib.bold_font(), 32, COLORS.text))
	return flow.panel
