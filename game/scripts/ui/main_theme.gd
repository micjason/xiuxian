class_name MainTheme
extends RefCounted

const INK := Color(0.027, 0.039, 0.043, 1)
const CARD := Color(0.086, 0.129, 0.122, 0.92)
const CARD_INNER := Color(0.047, 0.078, 0.074, 0.9)
const CARD_FOOTER := Color(0.04, 0.055, 0.053, 0.78)
const JADE := Color(0.68, 0.84, 0.72, 1)
const JADE_DEEP := Color(0.31, 0.5, 0.41, 1)
const GOLD := Color(0.86, 0.74, 0.44, 1)
const IVORY := Color(0.93, 0.91, 0.84, 1)
const MUTED := Color(0.58, 0.64, 0.61, 1)


static func body_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"PingFang SC",
		"Hiragino Sans GB",
		"Noto Sans CJK SC",
		"Source Han Sans SC",
		"Noto Sans SC",
		"sans-serif",
	])
	return font


static func title_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Songti SC",
		"STSong",
		"Noto Serif CJK SC",
		"Source Han Serif SC",
		"Noto Serif SC",
		"serif",
	])
	return font


static func make() -> Theme:
	var theme := Theme.new()
	var text_font := body_font()
	theme.set_default_font(text_font)
	theme.set_font("font", "Label", text_font)
	theme.set_font("font", "Button", text_font)
	theme.set_color("font_color", "Label", IVORY)
	theme.set_color("font_color", "Button", Color(0.12, 0.1, 0.06, 1))
	theme.set_color("font_hover_color", "Button", Color(0.12, 0.1, 0.06, 1))
	theme.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.05, 1))
	theme.set_color("font_disabled_color", "Button", Color(0.6, 0.63, 0.61, 1))
	theme.set_stylebox("panel", "PanelContainer", hero_panel())
	theme.set_stylebox("normal", "Button", _box(GOLD, Color(0.52, 0.41, 0.18, 1), 2, 24, 6, 18, 16))
	theme.set_stylebox("hover", "Button", _box(Color(0.93, 0.83, 0.54, 1), GOLD, 2, 24, 8, 18, 16))
	theme.set_stylebox("pressed", "Button", _box(Color(0.7, 0.58, 0.3, 1), Color(0.4, 0.31, 0.12, 1), 2, 24, 3, 18, 16))
	theme.set_stylebox("disabled", "Button", _box(Color(0.18, 0.22, 0.21, 1), Color(0.14, 0.18, 0.17, 1), 1, 24, 0, 18, 16))
	theme.set_stylebox("background", "ProgressBar", _box(Color(0.06, 0.08, 0.08, 1), Color(0.24, 0.34, 0.28, 1), 1, 18, 0, 2, 2))
	theme.set_stylebox("fill", "ProgressBar", _box(Color(0.46, 0.68, 0.52, 1), GOLD, 1, 18, 0, 2, 2))
	theme.set_stylebox("embedded_border", "Window", _box(CARD, Color(0.42, 0.5, 0.36, 0.7), 2, 24, 10, 22, 20))
	theme.set_stylebox("embedded_unfocused_border", "Window", _box(CARD, Color(0.32, 0.4, 0.3, 0.55), 2, 24, 6, 22, 20))
	theme.set_color("title_color", "Window", GOLD)
	theme.set_font_size("title_font_size", "Window", 28)
	return theme


static func hero_panel() -> StyleBoxFlat:
	return _box(CARD, Color(0.42, 0.5, 0.36, 0.7), 2, 32, 14, 10, 10)


static func inner_panel() -> StyleBoxFlat:
	return _box(CARD_INNER, Color(0.24, 0.34, 0.3, 0.85), 1, 20, 0, 8, 8)


static func footer_panel() -> StyleBoxFlat:
	return _box(CARD_FOOTER, Color(0.18, 0.24, 0.22, 0.7), 1, 20, 0, 8, 8)


static func ghost_button() -> StyleBoxFlat:
	return _box(Color(0.07, 0.1, 0.09, 0.95), Color(0.55, 0.48, 0.28, 0.85), 1, 20, 0, 14, 12)


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


static func progress_fill(ready: bool) -> StyleBoxFlat:
	if ready:
		return _box(GOLD, Color(0.93, 0.86, 0.58, 1), 1, 18, 0, 2, 2)
	return _box(Color(0.46, 0.68, 0.52, 1), GOLD, 1, 18, 0, 2, 2)


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
	box.shadow_color = Color(0, 0, 0, 0.32)
	box.shadow_size = shadow_size
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	box.anti_aliasing = true
	return box
