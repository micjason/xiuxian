class_name MainTheme
extends RefCounted

# 颜色、字号、间距的唯一来源是 UiTokens；下面保留原有常量名，指向令牌，避免改动调用方。
const INK := UiTokens.INK
const CARD := UiTokens.SURFACE
const CARD_INNER := UiTokens.SURFACE_INNER
const CARD_FOOTER := UiTokens.SURFACE_FOOTER
const JADE := UiTokens.JADE
const JADE_DEEP := UiTokens.JADE_DEEP
const GOLD := UiTokens.GOLD
const IVORY := UiTokens.TEXT
const MUTED := UiTokens.TEXT_MUTED

const SIZE_DISPLAY := UiTokens.FS_DISPLAY
const SIZE_NUMBER := 56
const SIZE_HERO := UiTokens.FS_HERO
const SIZE_BODY := UiTokens.FS_BODY_L
const SIZE_UI := UiTokens.FS_BODY
const SIZE_CAPTION := UiTokens.FS_CAPTION
const SIZE_MICRO := UiTokens.FS_MICRO
const SIZE_TAB := UiTokens.FS_CAPTION

const H_CTA := 128
const H_TAB := UiTokens.H_TAB
const H_ROW := 80
const H_CELL := 80
const ICON_TAB := 96
const ICON_CHROME := 64
const ICON_SLOT := 72
const H_ACTION := 72
const H_BAR := UiTokens.H_BAR
const H_SLOT := 128
const H_DOLL := 620
const BAG_COLUMNS := 8
const BAG_CELL_GAP := 6

## 主题类型变体名。在场景或脚本里写 control.theme_type_variation = MainTheme.VAR_PRIMARY 即可套用。
const VAR_PRIMARY := &"PrimaryButton"
const VAR_SECONDARY := &"SecondaryButton"
const VAR_GHOST := &"GhostButton"
const VAR_JADE := &"JadeButton"
const VAR_DANGER := &"DangerButton"
const VAR_TAB := &"TabButton"
const VAR_TAB_ACTIVE := &"TabButtonActive"
const VAR_CHOICE := &"ChoiceButton"
const VAR_CHOICE_SELECTED := &"ChoiceButtonSelected"
const VAR_INNER_PANEL := &"InnerPanel"
const VAR_TITLE := &"TitleLabel"
const VAR_SUBTLE := &"SubtleLabel"
const VAR_CAPTION := &"CaptionLabel"
const VAR_ACCENT := &"AccentLabel"
const VAR_DANGER_LABEL := &"DangerLabel"
const VAR_SUCCESS_LABEL := &"SuccessLabel"
const VAR_VALUE := &"ValueLabel"

const THEME_PATH := "res://resources/theme/xiuxian_theme.tres"


static func body_font() -> Font:
	return ArtLib.body_font()


static func title_font() -> Font:
	return ArtLib.title_font()


## 构建完整主题。运行时使用的是由本函数导出的 THEME_PATH（见 scripts/dev/export_theme.gd）；
## 改了令牌或这里的样式后需要重新导出，tests/unit/test_ui_theme.gd 会检查两者是否一致。
static func make() -> Theme:
	var theme := Theme.new()
	var text_font := body_font()
	theme.set_default_font(text_font)
	theme.set_default_font_size(UiTokens.FS_BODY)
	_make_labels(theme)
	_make_buttons(theme)
	_make_containers(theme)
	_make_inputs(theme)
	_make_dialogs(theme)
	return theme


static func _make_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", UiTokens.TEXT)
	theme.set_font_size("font_size", "Label", UiTokens.FS_BODY_L)
	theme.set_constant("line_spacing", "Label", 8)
	_label_variation(theme, VAR_TITLE, UiTokens.GOLD, UiTokens.FS_H1, title_font())
	_label_variation(theme, VAR_VALUE, UiTokens.TEXT, UiTokens.FS_VALUE, null)
	_label_variation(theme, VAR_SUBTLE, UiTokens.TEXT_MUTED, UiTokens.FS_CAPTION, null)
	_label_variation(theme, VAR_CAPTION, UiTokens.TEXT_MUTED, UiTokens.FS_MICRO, null)
	_label_variation(theme, VAR_ACCENT, UiTokens.GOLD, UiTokens.FS_BODY, null)
	_label_variation(theme, VAR_DANGER_LABEL, UiTokens.DANGER, UiTokens.FS_CAPTION, null)
	_label_variation(theme, VAR_SUCCESS_LABEL, UiTokens.SUCCESS, UiTokens.FS_CAPTION, null)


static func _label_variation(theme: Theme, variation: StringName, color: Color, size: int, font: Font) -> void:
	theme.set_type_variation(variation, "Label")
	theme.set_color("font_color", variation, color)
	theme.set_font_size("font_size", variation, size)
	if font != null:
		theme.set_font("font", variation, font)


static func _make_buttons(theme: Theme) -> void:
	# 默认按钮 = 次要按钮（深玉底金边）；整屏只允许一个主按钮（PrimaryButton，金色实心）。
	_button_variation(theme, "Button", UiTokens.TEXT, UiTokens.FS_BODY,
		ArtLib.nine("btn_secondary_normal"),
		ArtLib.nine("btn_secondary_normal", Color(1.14, 1.14, 1.14)),
		ArtLib.nine("btn_secondary_pressed"),
		ArtLib.nine("btn_secondary_disabled"),
		UiTokens.TEXT, UiTokens.TEXT)
	_variation_of(theme, VAR_SECONDARY, "Button")
	_button_variation(theme, VAR_PRIMARY, UiTokens.ON_PRIMARY, UiTokens.FS_HERO,
		ArtLib.nine("btn_primary_normal"),
		ArtLib.nine("btn_primary_normal", Color(1.1, 1.1, 1.1)),
		ArtLib.nine("btn_primary_pressed"),
		ArtLib.nine("btn_primary_disabled"),
		UiTokens.ON_PRIMARY, UiTokens.ON_PRIMARY)
	theme.set_font("font", VAR_PRIMARY, ArtLib.bold_font())
	theme.set_color("font_disabled_color", VAR_PRIMARY, UiTokens.TEXT_DISABLED)
	# 青玉按钮：强化、运转等"正向但不是本屏唯一主操作"的按钮。
	_button_variation(theme, VAR_JADE, UiTokens.TEXT, UiTokens.FS_BODY,
		ArtLib.nine("btn_jade_normal"),
		ArtLib.nine("btn_jade_normal", Color(1.12, 1.12, 1.12)),
		ArtLib.nine("btn_jade_pressed"),
		ArtLib.nine("btn_jade_disabled"),
		UiTokens.TEXT, UiTokens.TEXT)
	_button_variation(theme, VAR_GHOST, UiTokens.TEXT_MUTED, UiTokens.FS_CAPTION,
		_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, UiTokens.R_MD, 0, 20, 12),
		_box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, UiTokens.R_MD, 0, 20, 12),
		_box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, UiTokens.R_MD, 0, 20, 12),
		_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, UiTokens.R_MD, 0, 20, 12),
		UiTokens.TEXT, UiTokens.GOLD)
	_button_variation(theme, VAR_DANGER, UiTokens.TEXT, UiTokens.FS_BODY,
		ArtLib.nine("btn_danger_normal"),
		ArtLib.nine("btn_danger_normal", Color(1.1, 1.1, 1.1)),
		ArtLib.nine("btn_danger_pressed"),
		ArtLib.nine("btn_danger_disabled"),
		UiTokens.TEXT, UiTokens.TEXT)
	# 底部页签由 TabBarView 自己绘制；这两个变体只给旧节点和测试保留。
	var tab_idle := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 8, 8)
	var tab_hover := _box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 0, 0, 8, 8)
	_button_variation(theme, VAR_TAB, UiTokens.TEXT_MUTED, UiTokens.FS_BODY, tab_idle, tab_hover, tab_hover, tab_idle, UiTokens.TEXT, UiTokens.GOLD)
	var tab_active := _box(Color(UiTokens.Q_ORANGE, 0.18), Color(UiTokens.Q_ORANGE_DARK, 1), 0, 0, 0, 8, 8)
	tab_active.border_width_top = 6
	_button_variation(theme, VAR_TAB_ACTIVE, UiTokens.GOLD, UiTokens.FS_BODY, tab_active, tab_active, tab_active, tab_active, UiTokens.GOLD, UiTokens.GOLD)
	# 列表项（关卡、物品、功法）：整行可点，选中时金边发光。
	_button_variation(theme, VAR_CHOICE, UiTokens.TEXT, UiTokens.FS_BODY,
		ArtLib.nine("row_bg"), ArtLib.nine("row_bg", Color(1.2, 1.2, 1.2)), ArtLib.nine("row_selected"), ArtLib.nine("row_bg"),
		UiTokens.TEXT, UiTokens.GOLD)
	var picked := ArtLib.nine("row_selected")
	_button_variation(theme, VAR_CHOICE_SELECTED, UiTokens.GOLD, UiTokens.FS_BODY, picked, picked, picked, picked, UiTokens.GOLD, UiTokens.GOLD)
	theme.set_font_size("font_size", "CheckButton", UiTokens.FS_BODY_L)
	theme.set_color("font_color", "CheckButton", UiTokens.TEXT)


static func _variation_of(theme: Theme, variation: StringName, base: StringName) -> void:
	theme.set_type_variation(variation, base)


static func _button_variation(
	theme: Theme,
	type_name: StringName,
	font_color: Color,
	font_size: int,
	normal: StyleBox,
	hover: StyleBox,
	pressed: StyleBox,
	disabled: StyleBox,
	hover_font: Color,
	pressed_font: Color
) -> void:
	if type_name != &"Button":
		theme.set_type_variation(type_name, "Button")
	theme.set_stylebox("normal", type_name, normal)
	theme.set_stylebox("hover", type_name, hover)
	theme.set_stylebox("pressed", type_name, pressed)
	theme.set_stylebox("disabled", type_name, disabled)
	theme.set_stylebox("focus", type_name, _focus_ring())
	theme.set_color("font_color", type_name, font_color)
	theme.set_color("font_hover_color", type_name, hover_font)
	theme.set_color("font_pressed_color", type_name, pressed_font)
	theme.set_color("font_focus_color", type_name, font_color)
	theme.set_color("font_disabled_color", type_name, UiTokens.TEXT_DISABLED)
	theme.set_font_size("font_size", type_name, font_size)


static func _focus_ring() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = Color(UiTokens.GOLD, 0.9)
	box.set_border_width_all(3)
	box.set_corner_radius_all(UiTokens.R_MD)
	return box


static func _make_containers(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", hero_panel())
	theme.set_type_variation(VAR_INNER_PANEL, "PanelContainer")
	theme.set_stylebox("panel", VAR_INNER_PANEL, inner_panel())
	theme.set_stylebox("background", "ProgressBar", ArtLib.nine("bar_frame"))
	theme.set_stylebox("fill", "ProgressBar", ArtLib.nine("bar_fill_jade"))
	theme.set_color("font_color", "ProgressBar", UiTokens.TEXT)
	theme.set_font_size("font_size", "ProgressBar", UiTokens.FS_MICRO)
	# 触屏滚动条：窄但可见。
	var track := _box(Color(UiTokens.Q_COCOA, 0.06), Color(0, 0, 0, 0), 0, UiTokens.R_SM, 0, 6, 6)
	var grabber := _box(Color(UiTokens.Q_COCOA, 0.35), Color(0, 0, 0, 0), 0, UiTokens.R_SM, 0, 6, 6)
	var grabber_hot := _box(Color(UiTokens.Q_COCOA, 0.6), Color(0, 0, 0, 0), 0, UiTokens.R_SM, 0, 6, 6)
	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, track)
		theme.set_stylebox("grabber", bar, grabber)
		theme.set_stylebox("grabber_highlight", bar, grabber_hot)
		theme.set_stylebox("grabber_pressed", bar, grabber_hot)
	var rule := StyleBoxFlat.new()
	rule.bg_color = Color(UiTokens.GOLD, 0.35)
	rule.content_margin_top = 1
	theme.set_stylebox("separator", "HSeparator", rule)
	theme.set_constant("separation", "HSeparator", UiTokens.SP_2)


static func _make_inputs(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", input_normal())
	theme.set_stylebox("focus", "LineEdit", input_focus())
	theme.set_stylebox("read_only", "LineEdit", input_normal())
	theme.set_color("font_color", "LineEdit", UiTokens.TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", UiTokens.TEXT_MUTED)
	theme.set_color("caret_color", "LineEdit", UiTokens.GOLD)
	theme.set_color("selection_color", "LineEdit", Color(UiTokens.GOLD, 0.35))
	theme.set_font_size("font_size", "LineEdit", UiTokens.FS_BODY)
	theme.set_color("default_color", "RichTextLabel", UiTokens.TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", UiTokens.FS_BODY)
	theme.set_font_size("bold_font_size", "RichTextLabel", UiTokens.FS_BODY)
	var slider_bg := _box(UiTokens.Q_TRACK, UiTokens.Q_COCOA, 2, UiTokens.R_SM, 0, 0, 8)
	theme.set_stylebox("slider", "HSlider", slider_bg)
	theme.set_stylebox("grabber_area", "HSlider", _box(UiTokens.JADE_FILL, UiTokens.JADE_FILL, 0, UiTokens.R_SM, 0, 0, 8))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(UiTokens.GOLD, UiTokens.GOLD, 0, UiTokens.R_SM, 0, 0, 8))
	var knob := _knob_texture()
	theme.set_icon("grabber", "HSlider", knob)
	theme.set_icon("grabber_highlight", "HSlider", knob)
	theme.set_icon("grabber_disabled", "HSlider", knob)


static func _knob_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.94, 1.0])
	gradient.colors = PackedColorArray([UiTokens.GOLD, UiTokens.GOLD, Color(UiTokens.GOLD, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


static func _make_dialogs(theme: Theme) -> void:
	# 内嵌窗口：标题画在内容区上方，所以边框要向上多扩一个标题高度，否则标题会盖在页面上。
	var title_height := 96
	var border := ArtLib.nine("panel_popup")
	border.set("expand_margin_top", title_height)
	var border_idle := ArtLib.nine("panel_popup", Color(0.95, 0.95, 0.95))
	border_idle.set("expand_margin_top", title_height)
	theme.set_stylebox("embedded_border", "Window", border)
	theme.set_stylebox("embedded_unfocused_border", "Window", border_idle)
	theme.set_color("title_color", "Window", UiTokens.GOLD)
	theme.set_font_size("title_font_size", "Window", UiTokens.FS_HERO)
	theme.set_constant("title_height", "Window", title_height)
	theme.set_constant("close_h_offset", "Window", 28)
	theme.set_constant("close_v_offset", "Window", 52)
	theme.set_stylebox("panel", "AcceptDialog", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, UiTokens.SP_4, UiTokens.SP_3))
	theme.set_constant("buttons_separation", "AcceptDialog", UiTokens.SP_3)


static func hero_panel() -> StyleBox:
	return ArtLib.nine("panel_card")


static func inner_panel() -> StyleBox:
	return ArtLib.nine("panel_inset")


static func footer_panel() -> StyleBoxFlat:
	return _box(CARD_FOOTER, Color(0.18, 0.24, 0.22, 0.7), 1, 20, 0, 8, 8)


static func input_normal() -> StyleBox:
	var box := ArtLib.nine("panel_inset")
	if box is StyleBoxFlat:
		(box as StyleBoxFlat).bg_color = UiTokens.Q_WHITE
		(box as StyleBoxFlat).border_color = UiTokens.Q_COCOA
		(box as StyleBoxFlat).set_border_width_all(3)
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 18
	box.content_margin_bottom = 18
	return box


static func input_focus() -> StyleBox:
	var box := input_normal()
	if box is StyleBoxFlat:
		(box as StyleBoxFlat).border_color = UiTokens.Q_ORANGE_DARK
		(box as StyleBoxFlat).set_border_width_all(4)
	elif box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = Color(1.1, 1.05, 0.9)
	return box


static func secondary_button() -> StyleBoxFlat:
	return _box(UiTokens.SURFACE_INNER, Color(UiTokens.GOLD, 0.6), 2, UiTokens.R_MD, 0, 28, 18)


static func ghost_button() -> StyleBoxFlat:
	return _box(Color(0.07, 0.1, 0.09, 0.95), Color(0.55, 0.48, 0.28, 0.85), 1, 16, 0, 12, 8)


static func clear_panel() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.draw_center = false
	box.set_border_width_all(0)
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box


static func chrome_clear() -> StyleBoxFlat:
	return _box(Color(0.04, 0.05, 0.05, 0.0), Color(0, 0, 0, 0), 0, 0, 0, 8, 4)


static func cultivation_capsule() -> StyleBox:
	var box := ArtLib.nine("chip")
	box.content_margin_left = 36
	box.content_margin_right = 36
	return box


static func bag_tab_idle() -> StyleBoxFlat:
	return _box(Color(0.08, 0.1, 0.1, 0.28), Color(GOLD.r, GOLD.g, GOLD.b, 0.28), 1, 20, 0, 10, 6)


static func bag_tab_active() -> StyleBoxFlat:
	return _box(GOLD, Color(0.52, 0.41, 0.18, 1), 1, 20, 0, 10, 6)


static func bag_cell_empty() -> StyleBoxFlat:
	return _box(Color(0.05, 0.08, 0.07, 0.55), Color(GOLD.r, GOLD.g, GOLD.b, 0.28), 1, 10, 0, 2, 2)


static func tab_dock() -> StyleBox:
	var box := StyleBoxTexture.new()
	box.texture = ArtLib.ui("dock_bg")
	return box


static func circle_slot(border: Color) -> StyleBoxFlat:
	var box := _box(Color(0.06, 0.09, 0.08, 0.72), border, 2, 999, 0, 10, 10)
	box.set_corner_radius_all(999)
	return box


static func nav_tab() -> StyleBoxFlat:
	return _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 0, 4, 6)


static func stamp_label(label: Label, size: int, color: Color) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


static func seal_ring() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.16, 0.22, 0.18, 0.16)
	box.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.42)
	box.set_border_width_all(2)
	box.set_corner_radius_all(999)
	box.shadow_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.16)
	box.shadow_size = 16
	return box


static func seal_inner() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = Color(JADE.r, JADE.g, JADE.b, 0.28)
	box.set_border_width_all(1)
	box.set_corner_radius_all(999)
	return box


static func fill_parent(control: Control) -> void:
	control.layout_mode = 1
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BOTH


static func place_centered(control: Control, bounds: Vector2, max_size: Vector2) -> Vector2:
	var available := bounds
	if available.x < 64.0:
		available = UiTokens.BASE_SIZE
	var margin := 36.0
	var card := Vector2(
		minf(max_size.x, maxf(280.0, available.x - margin * 2.0)),
		minf(max_size.y, maxf(280.0, available.y - margin * 2.0))
	)
	control.layout_mode = 1
	control.anchor_left = 0.5
	control.anchor_top = 0.5
	control.anchor_right = 0.5
	control.anchor_bottom = 0.5
	control.offset_left = -card.x * 0.5
	control.offset_top = -card.y * 0.5
	control.offset_right = card.x * 0.5
	control.offset_bottom = card.y * 0.5
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BOTH
	return card


static func progress_fill(ready: bool) -> StyleBox:
	return ArtLib.nine("bar_fill_gold" if ready else "bar_fill_jade")


static func _box(
	fill: Color,
	border: Color,
	border_width: int,
	radius: int,
	shadow_size: int,
	margin_x: int = 8,
	margin_y: int = 6
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color(0.42, 0.29, 0.23, 0.26)
	box.shadow_size = shadow_size
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	box.anti_aliasing = true
	return box
