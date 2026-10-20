class_name QKit
extends RefCounted
## Q 版（2026-10-20 设计稿）常用小部件：描边字、胶囊、圆形侧边按钮、品质格、进度条、开关、绶带标题、红点。
## 颜色和尺寸照设计稿（/workspace/q_design/src/common.py），框体走 QSkin / ArtLib.nine，换美术切图不用改这里的调用方。


## 白字可可描边（设计稿 .ol）。font_title=true 用快乐体。
static func outlined(text: String, size: int, color: Color = UiTokens.Q_WHITE, outline: Color = UiTokens.Q_COCOA, outline_size: int = 10, align: int = HORIZONTAL_ALIGNMENT_LEFT, font_title: bool = true) -> Label:
	var node := UiKit.label(text, size, color, align)
	if font_title:
		node.add_theme_font_override("font", ArtLib.title_font())
	node.add_theme_color_override("font_outline_color", outline)
	node.add_theme_constant_override("outline_size", outline_size)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return node


## 快乐体普通字（不描边）。
static func title(text: String, size: int, color: Color = UiTokens.TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := UiKit.label(text, size, color, align)
	node.add_theme_font_override("font", ArtLib.title_font())
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return node


## 胶囊底板（PanelContainer）。child 可为空，之后自己往里加。
static func pill(fill: Color, child: Control = null, border_width: int = 4, shadow: int = 5, pad_x: int = 22, pad_y: int = 6) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", QSkin.custom(fill, UiTokens.Q_COCOA, border_width, 999, shadow, pad_x, pad_y))
	if child != null:
		panel.add_child(child)
	return panel


## 带描边字的彩色胶囊（「已通关 ✓」「挑战中」「修炼中」…）。
## fill 可以是颜色，也可以是美术胶囊名（"mint" "orange" "red" "green" "blue" "grey" "dark" "cream" "teal"
## → ui/chip_<名>.png，高 44 只横向拉伸）。
static func tag(text: String, fill: Variant, size: int = UiTokens.FS_MICRO, pad_x: int = 18) -> PanelContainer:
	var dark := typeof(fill) == TYPE_STRING and str(fill) == "cream"
	var label := outlined(text, size, UiTokens.TEXT if dark else UiTokens.Q_WHITE, UiTokens.Q_COCOA, 0 if dark else 8, HORIZONTAL_ALIGNMENT_CENTER, false)
	if typeof(fill) == TYPE_STRING:
		var cut := "chip_" + str(fill)
		if ArtLib.qui(cut) != null:
			var panel := PanelContainer.new()
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var box := ArtLib.q_nine(cut)
			box.content_margin_left = pad_x
			box.content_margin_right = pad_x
			box.content_margin_top = 0
			box.content_margin_bottom = 4
			panel.add_theme_stylebox_override("panel", box)
			panel.custom_minimum_size = Vector2(0, 44)
			label.custom_minimum_size = Vector2(0, 40)
			panel.add_child(label)
			return panel
		fill = {"mint": UiTokens.Q_MINT, "orange": UiTokens.Q_ORANGE, "red": UiTokens.Q_RED, "blue": UiTokens.Q_BLUE}.get(str(fill), UiTokens.Q_GREY)
	return pill(fill, label, 3, 0, pad_x, 2)


## 圆角卡片（奶油底 / 卡片底），body 是里面的 VBox。cut 给美术九宫格名（panel_cream / panel_apricot /
## card_apricot / card_current_gold / card_locked / popup_frame / well_*），有切图就用切图。
static func panel(fill: Color = UiTokens.Q_CREAM, radius: int = 34, pad_x: int = 26, pad_y: int = 22, border: int = 4, shadow: int = 6, cut: String = "") -> Dictionary:
	var box := PanelContainer.new()
	if cut.is_empty():
		cut = "panel_cream" if fill == UiTokens.Q_CREAM and border > 0 else ""
	box.add_theme_stylebox_override("panel", cut_box(cut, pad_x, pad_y) if not cut.is_empty() and ArtLib.qui(cut) != null else QSkin.custom(fill, UiTokens.Q_COCOA, border, radius, shadow, pad_x, pad_y))
	var body := UiKit.vbox(UiTokens.SP_2)
	box.add_child(body)
	return {"panel": box, "body": body}


## 美术九宫格 + 指定内容边距（切图下方的投影另加 6）。
static func cut_box(cut: String, pad_x: int, pad_y: int) -> StyleBoxTexture:
	var box := ArtLib.q_nine(cut)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y + 6
	return box


## 无描边的内嵌底（设计稿 #FCEBD0 圆角块：掉落行、条件区……）。
static func inset(fill: Color = UiTokens.Q_CARD, radius: int = 24, pad_x: int = 22, pad_y: int = 14) -> Dictionary:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", QSkin.custom(fill, Color(0, 0, 0, 0), 0, radius, 0, pad_x, pad_y))
	var body := UiKit.vbox(UiTokens.SP_1)
	box.add_child(body)
	return {"panel": box, "body": body}


## Q 版按钮：kind = "o" 橙 / "m" 薄荷 / "g" 灰（不可用）/ "c" 奶油 / "r" 红。文字白色可可描边（奶油按钮用深色字）。
## 橙/薄荷/灰用美术切图（btn_<色>_<档>_normal/pressed，档 = 60/100/124/150，取最接近 height 的一档，
## 按钮高度 = 档高 + 6 投影）；radius 30 的方角橙钮用 btn_orange_r30_*。奶油/红没有切图，代码画。
const BTN_TIERS := [60, 100, 124, 150]


static func button(text: String, kind: String = "o", height: int = 100, font_size: int = UiTokens.FS_BODY, radius: int = 999) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.custom_minimum_size = Vector2(0, height)
	style_button(node, kind, font_size, radius)
	return node


static func _btn_cut(kind: String, height: int, radius: int) -> Dictionary:
	if kind == "o" and radius < 100 and ArtLib.qui("btn_orange_r30_normal") != null:
		return {"normal": "btn_orange_r30_normal", "pressed": "btn_orange_r30_pressed", "off": "btn_grey_disabled_100", "h": 104}
	var colour: String = {"o": "orange", "m": "mint", "g": "grey"}.get(kind, "")
	if colour == "":
		return {}
	var best := 100
	for tier in BTN_TIERS:
		if absi(tier - height) < absi(best - height):
			best = tier
	var tiers := BTN_TIERS.duplicate()
	if colour != "orange":
		tiers.erase(150)
		if best == 150:
			best = 124
	var off := "btn_grey_disabled_%d" % best if best != 150 else "btn_grey_disabled_124"
	if colour == "grey":
		return {"normal": off, "pressed": off, "off": off, "h": best + 6} if ArtLib.qui(off) != null else {}
	var normal := "btn_%s_%d_normal" % [colour, best]
	if ArtLib.qui(normal) == null:
		return {}
	return {"normal": normal, "pressed": "btn_%s_%d_pressed" % [colour, best], "off": off, "h": best + 6}


static func style_button(node: Button, kind: String, font_size: int = UiTokens.FS_BODY, radius: int = 999) -> void:
	var fills := {
		"o": [UiTokens.Q_ORANGE, UiTokens.Q_ORANGE_DARK],
		"m": [UiTokens.Q_MINT, UiTokens.Q_MINT_DARK],
		"g": [Color("dcd4cb"), Color("c4b9ad")],
		"c": [UiTokens.Q_CARD, Color("f2d9b4")],
		"r": [Color("ff7a7e"), UiTokens.Q_RED],
	}
	var cut := _btn_cut(kind, int(node.custom_minimum_size.y), radius)
	var normal: StyleBox
	var pressed: StyleBox
	var off: StyleBox
	if not cut.is_empty():
		node.custom_minimum_size.y = int(cut["h"])
		normal = _btn_box(str(cut["normal"]), 0)
		pressed = _btn_box(str(cut["pressed"]), 6)
		off = _btn_box(str(cut["off"]), 0)
		node.set_meta(&"q_cut", str(cut["normal"]))
	else:
		var pair: Array = fills.get(kind, fills["o"])
		normal = QSkin.custom(pair[0], UiTokens.Q_COCOA, 4, radius, 6, 24, 8)
		pressed = QSkin.custom(pair[1], UiTokens.Q_COCOA, 4, radius, 2, 24, 8)
		off = QSkin.custom(Color("e2dad1"), Color("8a7c70"), 4, radius, 4, 24, 8)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", normal)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("disabled", off)
	node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	node.add_theme_font_override("font", ArtLib.title_font())
	node.add_theme_font_size_override("font_size", font_size)
	var light := kind != "c"
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		node.add_theme_color_override(key, UiTokens.Q_WHITE if light else UiTokens.TEXT)
	node.add_theme_color_override("font_disabled_color", Color("f6f1ec"))
	node.add_theme_color_override("font_outline_color", UiTokens.Q_COCOA if light else Color(0, 0, 0, 0))
	node.add_theme_constant_override("outline_size", 10 if light else 0)


## 按钮切图：只横向拉伸；内容边距小（切图边距含圆头），按下态文字下移 6（SPEC_Q：按下下沉 6px）。
static func _btn_box(cut: String, shift: int) -> StyleBoxTexture:
	var box := ArtLib.q_nine(cut)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 2 + shift
	box.content_margin_bottom = 8 - shift
	return box


## 圆形侧边按钮（设计稿 .side，132px，美术 side_entry.png）+ 下面描边字。返回 {root, button, caption, dot}。
static func side_button(icon_name: String, text: String, size: int = 132, icon_size: int = 108) -> Dictionary:
	var root := UiKit.vbox(0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.alignment = BoxContainer.ALIGNMENT_BEGIN
	var button := Button.new()
	button.custom_minimum_size = Vector2(size, size + 7)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	var tex := ArtLib.qui("side_entry")
	if tex != null:
		var disc := StyleBoxTexture.new()
		disc.texture = tex
		var down := StyleBoxTexture.new()
		down.texture = tex
		down.modulate_color = Color(0.93, 0.9, 0.86)
		for state in ["normal", "hover", "disabled"]:
			button.add_theme_stylebox_override(state, disc)
		button.add_theme_stylebox_override("pressed", down)
	else:
		var flat := QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 5, 999, 7, 0, 0)
		for state in ["normal", "hover", "disabled", "pressed"]:
			button.add_theme_stylebox_override(state, flat)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var icon := UiKit.icon(icon_name, icon_size)
	center_in(icon, Vector2(icon_size, icon_size))
	icon.offset_top -= 3
	icon.offset_bottom -= 3
	button.add_child(icon)
	var dot := reddot(38)
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = -38
	dot.offset_right = 0
	dot.offset_top = -6
	dot.offset_bottom = 32
	dot.visible = false
	button.add_child(dot)
	root.add_child(button)
	var caption := outlined(text, 34, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 12, HORIZONTAL_ALIGNMENT_CENTER)
	caption.custom_minimum_size = Vector2(size + 60, 48)
	caption.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(caption)
	return {"root": root, "button": button, "caption": caption, "dot": dot}


## 把 control 放在父节点正中，大小固定。
static func center_in(control: Control, size: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_CENTER)
	control.offset_left = -size.x / 2.0
	control.offset_right = size.x / 2.0
	control.offset_top = -size.y / 2.0
	control.offset_bottom = size.y / 2.0


## 设计稿的红点（美术 red_dot.png 52x54，含 7px 外溢；size = 红点本体直径）。
static func reddot(size: int = 38) -> Control:
	var dot := Control.new()
	dot.name = "RedDot"
	dot.custom_minimum_size = Vector2(size, size)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := ArtLib.qui("red_dot")
	if tex != null:
		var scale := float(size) / 38.0
		var rect := TextureRect.new()
		rect.texture = tex
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.position = Vector2(-7, -7) * scale
		rect.size = Vector2(52, 54) * scale
		dot.add_child(rect)
		return dot
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.Q_RED
	style.border_color = Color.WHITE
	style.set_border_width_all(4)
	style.set_corner_radius_all(999)
	panel.add_theme_stylebox_override("panel", style)
	dot.add_child(panel)
	return dot


## 品质格（设计稿 slot）：美术 slot_<品质>.png（160x166 含投影，整张缩放）+ 图标 + 角标。返回固定大小的 Control。
## rarity 0..5（白绿蓝紫橙红），-1 = 空格/锁定格（slot_empty + slot_locked_overlay）。tex 可为空。
const SLOT_CUTS := ["slot_white", "slot_green", "slot_blue", "slot_purple", "slot_orange", "slot_red"]


static func slot(tex: Texture2D, rarity: int, size: int, count_text: String = "", level_text: String = "", tint: Color = Color.WHITE, locked: bool = false) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(size, size)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cut := "slot_empty" if rarity < 0 else str(SLOT_CUTS[clampi(rarity, 0, 5)])
	var frame_tex := ArtLib.qui(cut)
	if frame_tex != null:
		var frame := TextureRect.new()
		frame.name = "SlotFrame"
		frame.texture = frame_tex
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.offset_bottom = float(size) * float(frame_tex.get_height() - 160) / 160.0
		box.add_child(frame)
	else:
		var flat := Panel.new()
		flat.set_anchors_preset(Control.PRESET_FULL_RECT)
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := Color("e3d9cc") if rarity < 0 else UiTokens.rarity_fill(rarity).lerp(Color.WHITE, 0.25)
		flat.add_theme_stylebox_override("panel", QSkin.custom(fill, UiTokens.Q_COCOA, 4, int(round(size * 0.24)), 5, 0, 0))
		box.add_child(flat)
	if tex != null:
		var icon := UiKit.icon_from(tex, int(size * 0.8), tint)
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		var inset := float(size) * 0.1
		icon.offset_left = inset
		icon.offset_top = inset
		icon.offset_right = -inset
		icon.offset_bottom = -inset
		if locked:
			icon.modulate = Color(0.6, 0.6, 0.6, 0.5)
		box.add_child(icon)
	if locked:
		var overlay_tex := ArtLib.qui("slot_locked_overlay")
		if overlay_tex != null:
			var overlay := TextureRect.new()
			overlay.texture = overlay_tex
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			overlay.stretch_mode = TextureRect.STRETCH_SCALE
			overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			box.add_child(overlay)
		var lock := lock_icon(int(size * 0.36))
		center_in(lock, lock.custom_minimum_size)
		box.add_child(lock)
	if not count_text.is_empty():
		var count := outlined(count_text, maxi(UiTokens.FS_MICRO, int(size * 0.26)), UiTokens.Q_WHITE, UiTokens.Q_COCOA, 9, HORIZONTAL_ALIGNMENT_RIGHT)
		count.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		count.offset_top = -44
		count.offset_right = -8
		count.offset_bottom = -2
		box.add_child(count)
	if not level_text.is_empty():
		var level := outlined(level_text, UiTokens.FS_MICRO, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 9)
		level.set_anchors_preset(Control.PRESET_TOP_LEFT)
		level.offset_left = 10
		level.offset_top = 2
		level.offset_right = 120
		level.offset_bottom = 42
		box.add_child(level)
	return box


## 小锁（美术 lock.png 52x60）；没有切图退回旧图标染可可色。
static func lock_icon(height: int = 48) -> Control:
	var tex := ArtLib.qui("lock")
	if tex == null:
		return UiKit.icon("ui_lock", height, UiTokens.Q_COCOA)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(round(height * 52.0 / 60.0), height)
	return rect


## 美术切图原尺寸（或指定尺寸）的 TextureRect。没有切图返回空 Control。
static func cut_rect(cut: String, size: Vector2 = Vector2.ZERO) -> Control:
	var tex := ArtLib.qui(cut)
	if tex == null:
		var empty := Control.new()
		empty.custom_minimum_size = size
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return empty
	var rect := TextureRect.new()
	rect.name = cut.to_pascal_case()
	rect.texture = tex
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = size if size != Vector2.ZERO else Vector2(tex.get_size())
	return rect


## 圆角进度条（设计稿 bar）。height 52/40/30 用美术切图（cut_color：mint/gold/red/blue，修为条 52 用 xiuwei），
## 其它高度代码画。segments>1 时画分段线。
static func bar(ratio: float, fill: Color = UiTokens.Q_MINT, height: int = 40, segments: int = 1, track: Color = UiTokens.Q_TRACK, cut_color: String = "") -> Control:
	var root := QBar.new()
	root.custom_minimum_size = Vector2(0, height)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.setup(ratio, fill, segments, track, cut_color)
	return root


## 绶带标题（美术 ribbon_title_104 / ribbon_title_78，只横向拉伸）+ 白字描边。big=true 用 104 档。
static func ribbon(text: String, font_size: int = 44, min_width: int = 300, big: bool = true) -> Control:
	var cut := "ribbon_title_104" if big else "ribbon_title_78"
	var plate := PanelContainer.new()
	plate.name = "RibbonPlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tex := ArtLib.qui(cut)
	if tex != null:
		var box := ArtLib.q_nine(cut)
		box.content_margin_left = 96
		box.content_margin_right = 96
		box.content_margin_top = 0
		box.content_margin_bottom = 18 if big else 14
		plate.add_theme_stylebox_override("panel", box)
		plate.custom_minimum_size = Vector2(min_width + 120, tex.get_height())
	else:
		plate.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_ORANGE, UiTokens.Q_COCOA, 5, 24, 7, 60, 4))
		plate.custom_minimum_size = Vector2(min_width + 120, 94)
	var label := outlined(text, font_size, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 12, HORIZONTAL_ALIGNMENT_CENTER)
	label.name = "RibbonText"
	plate.add_child(label)
	return plate


## 开关（设计稿 toggle）。返回 Button（toggle_mode）；外观随 button_pressed 变。
static func toggle(on: bool, width: int = 112, height: int = 64) -> Button:
	var node := QToggle.new()
	node.custom_minimum_size = Vector2(width, height)
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.set_on(on)
	return node


## 小圆勾 / 叉（突破条件；美术 check_ok / check_no 56px）。
static func check(ok: bool, size: int = 56) -> Control:
	var tex := ArtLib.qui("check_ok" if ok else "check_no")
	if tex != null:
		var rect := cut_rect("check_ok" if ok else "check_no", Vector2(size, size))
		rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return rect
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(size, size)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_MINT if ok else UiTokens.Q_RED, UiTokens.Q_COCOA, 4, 999, 0, 0, 0))
	var mark := outlined("✓" if ok else "✕", int(size * 0.62), UiTokens.Q_WHITE, UiTokens.Q_COCOA, 6, HORIZONTAL_ALIGNMENT_CENTER, false)
	panel.add_child(mark)
	return panel


## 小锁 + 文字（「未获得」「暂未开放」）。
static func lock_row(text: String, size: int = UiTokens.FS_CAPTION) -> HBoxContainer:
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lock := lock_icon(48)
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lock)
	row.add_child(title(text, size, UiTokens.TEXT_DISABLED))
	return row


## 透明可点层：铺满父节点，点了发 pressed。给“整块区域可点”的卡片用。
static func hit_area(parent: Control) -> Button:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	parent.add_child(button)
	return button


## 物品 / 功法 slug → {name, rarity, texture, tint}（掉落、奖励格子用；名字和品质读后台配置）。
static func reward_view(content: Dictionary, slug: String) -> Dictionary:
	for row in content.get("items", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			var item := BagModel.normalize({"itemSlug": slug}, row as Dictionary, {})
			var icon := ArtLib.item_icon(item)
			return {"name": str(item.name), "rarity": int(item.rarity), "texture": icon.texture, "tint": bool(icon.tint), "kind": "item"}
	for row in content.get("skills", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			var tex: Texture2D = ArtLib.q("items/book_other") if ArtLib.has_q("items/book_other.png") else ArtLib.icon("cat_scroll")
			return {"name": str((row as Dictionary).get("displayName", slug)), "rarity": 3, "texture": tex, "tint": false, "kind": "skill"}
	return {"name": "名称缺失", "rarity": 0, "texture": null, "tint": false, "kind": ""}


## 物品格（品质框 + 图标 + 数量），给奖励 / 掉落行用。
static func reward_slot(content: Dictionary, slug: String, size: int, count: int = 0) -> Control:
	var view := reward_view(content, slug)
	var tint := UiTokens.rarity_fill(int(view.rarity)).darkened(0.35) if bool(view.tint) else Color.WHITE
	var node := slot(view.texture, int(view.rarity), size, "×%d" % count if count > 1 else "", "", tint)
	node.tooltip_text = str(view.name)
	return node


## 怪物 / 首领圆头像（设计稿关卡卡里的 150 圆）：Q 版立绘（狼/狐/蛇/蟒/熊），没有立绘的退回旧剪影图标。
static func portrait(monster_name: String, size: int, ring: Color = UiTokens.Q_MINT, locked: bool = false) -> Control:
	var disc := Panel.new()
	disc.name = "Portrait"
	disc.custom_minimum_size = Vector2(size, size)
	disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	disc.add_theme_stylebox_override("panel", QSkin.custom(Color("eaf6ee") if not locked else Color("dcd4cb"), ring, 6, 999, 0, 0, 0))
	var sprite_id := ArtLib.monster_sprite_id(monster_name)
	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := float(size) * 0.08
	art.offset_left = inset
	art.offset_top = inset
	art.offset_right = -inset
	art.offset_bottom = inset * 0.5
	if not sprite_id.is_empty():
		art.texture = ArtLib.q("sprites/" + sprite_id)
	else:
		art.texture = ArtLib.icon(ArtLib.boss_icon_name(monster_name))
		art.modulate = UiTokens.Q_COCOA
	if locked:
		art.modulate = Color(0.35, 0.33, 0.32, 0.7)
	disc.add_child(art)
	var rim := Panel.new()
	rim.name = "Rim"
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rim_box := QSkin.custom(Color(0, 0, 0, 0), ring, 6, 999, 0, 0, 0)
	rim_box.draw_center = false
	rim.add_theme_stylebox_override("panel", rim_box)
	disc.add_child(rim)
	return disc


## 数字千分位（12,580）。
static func grouped(value: float) -> String:
	return OfflineView.grouped(value)
