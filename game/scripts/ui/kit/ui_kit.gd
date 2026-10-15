class_name UiKit
extends RefCounted
## 构建界面用的小工具：统一字号、触控尺寸、卡片样式，页面里不再手写重复代码。


static func label(text: String, size: int = UiTokens.FS_BODY, color: Color = UiTokens.TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var node := Label.new()
	node.text = text
	node.horizontal_alignment = align as HorizontalAlignment
	node.add_theme_font_size_override("font_size", maxi(size, UiTokens.FS_MICRO))
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func wrap_label(text: String, size: int = UiTokens.FS_CAPTION, color: Color = UiTokens.TEXT_MUTED) -> Label:
	var node := label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func button(text: String, variation: StringName = MainTheme.VAR_SECONDARY, min_height: int = UiTokens.H_TOUCH) -> Button:
	var node := Button.new()
	node.text = text
	node.theme_type_variation = variation
	node.custom_minimum_size = Vector2(0, min_height)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size", UiTokens.FS_BODY)
	return node


static func vbox(separation: int = UiTokens.SP_2) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func hbox(separation: int = UiTokens.SP_2) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func spacer(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 带内边距的卡片（九宫格框）。内容请加到返回的 body（VBox）里。有标题时标题下面带一条金线。
static func card(title: String = "") -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_card"))
	var body := vbox(UiTokens.SP_2)
	panel.add_child(body)
	if not title.is_empty():
		body.add_child(section_title(title))
	return {"panel": panel, "body": body}


## 小节标题：金色文字 + 细金线。
static func section_title(text: String) -> Control:
	var box := vbox(6)
	var head := label(text, UiTokens.FS_BODY, UiTokens.GOLD)
	head.theme_type_variation = MainTheme.VAR_ACCENT
	box.add_child(head)
	box.add_child(divider())
	return box


static func divider() -> TextureRect:
	var node := TextureRect.new()
	node.texture = ArtLib.ui("divider")
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.custom_minimum_size = Vector2(0, 10)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 图标（白色剪影按 tint 染色）。size 是正方形边长。
static func icon(name: String, size: int, tint: Color = UiTokens.TEXT) -> TextureRect:
	var node := TextureRect.new()
	node.texture = ArtLib.icon(name)
	node.custom_minimum_size = Vector2(size, size)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.modulate = tint
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func icon_from(tex: Texture2D, size: int, tint: Color = Color.WHITE) -> TextureRect:
	var node := TextureRect.new()
	node.texture = tex
	node.custom_minimum_size = Vector2(size, size)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.modulate = tint
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


## 图标 + 文字的小胶囊（资源数、战力等）。
static func chip(icon_name: String, text: String, color: Color = UiTokens.TEXT) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ArtLib.nine("chip"))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)
	row.add_child(icon(icon_name, 44, color))
	var text_label := label(text, UiTokens.FS_CAPTION, color)
	text_label.name = "Text"
	row.add_child(text_label)
	return panel


## 红点（右上角角标）。放进任意 Control 里，自己贴右上角。
static func reddot(count: int = 0) -> Control:
	var node := TextureRect.new()
	node.texture = ArtLib.ui("reddot")
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.custom_minimum_size = Vector2(36, 36)
	node.size = Vector2(36, 36)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if count > 0:
		var number := label(str(mini(count, 99)), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		number.set_anchors_preset(Control.PRESET_FULL_RECT)
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		node.custom_minimum_size = Vector2(44, 44)
		node.size = Vector2(44, 44)
		node.add_child(number)
	return node


## 横向进度条（占比）。fill_art 取 bar_fill_jade / bar_fill_gold / bar_fill_cin / bar_fill_blue。
const FILL_INSET_Y := 3.0


static func ratio_bar(ratio: float, fill_art: String = "bar_fill_jade", height: int = 28) -> Control:
	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(0, maxi(height, 44))
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.add_theme_stylebox_override("panel", ArtLib.nine("bar_frame"))
	# PanelContainer 会把子控件撑满，所以先放一个撑满的空 Control，填充条按比例锚定在它里面。
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(inner)
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", ArtLib.nine(fill_art))
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_left = 0.0
	fill.anchor_right = clampf(ratio, 0.06, 1.0)
	fill.offset_left = 2
	fill.offset_right = -2
	# 填充条在框里上下各缩进约 3px（bar_frame 内容边距为 0，不缩进会压到框线）
	fill.offset_top = FILL_INSET_Y
	fill.offset_bottom = -FILL_INSET_Y
	inner.add_child(fill)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return track


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## 页面标题牌（缎带框 + 金色标题字），居中。
static func page_title(text: String) -> Control:
	var holder := HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ArtLib.nine("page_title_plate"))
	panel.custom_minimum_size = Vector2(560, 100)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := label(text, UiTokens.FS_H1, UiTokens.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", ArtLib.title_font())
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 8)
	panel.add_child(title)
	holder.add_child(panel)
	return holder


## 两行的大按钮：第一行大字，第二行小字（金色主按钮上的文字用 ON_GOLD）。
## 文字用 set_meta 里的两个 Label 改：button.get_meta("title") / get_meta("sub")。
static func cta_button(title_text: String, sub_text: String, variation: StringName = MainTheme.VAR_PRIMARY, height: int = 168) -> Button:
	var node := Button.new()
	node.theme_type_variation = variation
	node.custom_minimum_size = Vector2(0, height)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.focus_mode = Control.FOCUS_NONE
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(column)
	var color := UiTokens.ON_GOLD if variation == MainTheme.VAR_PRIMARY else UiTokens.TEXT
	var first := label(title_text, UiTokens.FS_H1, color, HORIZONTAL_ALIGNMENT_CENTER)
	first.add_theme_font_override("font", ArtLib.title_font())
	column.add_child(first)
	var second := label(sub_text, UiTokens.FS_MICRO, color, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(second)
	node.set_meta("title", first)
	node.set_meta("sub", second)
	return node


static func set_cta(node: Button, title_text: String, sub_text: String) -> void:
	(node.get_meta("title") as Label).text = title_text
	(node.get_meta("sub") as Label).text = sub_text
	(node.get_meta("sub") as Label).visible = not sub_text.is_empty()
