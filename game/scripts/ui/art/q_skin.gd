class_name QSkin
extends RefCounted
## Q 版框体的代码占位：美术的九宫格切图（res://assets/art/q/ui/<id>.png）还没交付时，ArtLib.nine(id) 用这里画的
## 圆角描边样式顶上（奶油底 + 可可色描边 + 底部投影），按钮/格子/进度条等每个 id 一种样式。
## 美术交付后同名文件放进 assets/art/q/ui/、九宫格边距写进 ArtLib.Q_NINE，这里就不再用到，业务代码不用动。

## id → [底色, 描边色, 描边宽, 圆角, 投影高, 内容横向边距, 内容纵向边距]
const SPECS := {
	"panel_card": ["fff8ec", "6b4a3a", 4, 30, 6, 28, 24],
	"panel_popup": ["fff8ec", "6b4a3a", 5, 40, 8, 36, 32],
	"panel_popup_scroll": ["fff8ec", "6b4a3a", 5, 40, 8, 36, 28],
	"panel_inset": ["f7e8cf", "00000000", 0, 22, 0, 20, 16],
	"panel_sheet": ["9fd8ce", "ffffffbf", 5, 60, 0, 24, 24],
	"ribbon_title": ["ff9f43", "6b4a3a", 5, 24, 7, 56, 12],
	"page_title_plate": ["ff9f43", "6b4a3a", 5, 24, 7, 56, 12],
	"battle_log_panel": ["fdf0da", "6b4a3a", 3, 22, 0, 20, 16],
	"guide_bubble": ["ffffff", "6b4a3a", 4, 28, 5, 28, 20],
	"guide_highlight": ["00000000", "ff9f43", 6, 28, 0, 0, 0],
	"chip": ["fffffff5", "6b4a3a", 4, 999, 5, 22, 8],
	"chip_dark": ["6b5241", "6b4a3a", 0, 999, 0, 22, 8],
	"chip_mint": ["5cc9a7", "6b4a3a", 4, 999, 5, 22, 8],
	"chip_orange": ["ff9f43", "6b4a3a", 4, 999, 5, 22, 8],
	"chip_sky": ["dff3ff", "6b4a3a", 3, 999, 0, 22, 8],
	"toast": ["fff8ec", "6b4a3a", 4, 999, 6, 36, 18],
	"row_bg": ["fff8ec", "6b4a3a", 4, 26, 6, 24, 18],
	"row_selected": ["fff1c9", "e07b24", 5, 26, 6, 24, 18],
	"row_locked": ["efe6da", "9a8478", 4, 26, 0, 24, 18],
	"btn_primary_normal": ["ff9f43", "6b4a3a", 4, 999, 6, 28, 16],
	"btn_primary_pressed": ["f08a30", "6b4a3a", 4, 999, 2, 28, 16],
	"btn_primary_disabled": ["d9cfc4", "8a7c70", 4, 999, 4, 28, 16],
	"btn_secondary_normal": ["fff8ec", "6b4a3a", 4, 999, 6, 28, 16],
	"btn_secondary_pressed": ["f4e4c9", "6b4a3a", 4, 999, 2, 28, 16],
	"btn_secondary_disabled": ["e9e2da", "a89a8e", 4, 999, 4, 28, 16],
	"btn_danger_normal": ["ff8a80", "6b4a3a", 4, 999, 6, 28, 16],
	"btn_danger_pressed": ["f07068", "6b4a3a", 4, 999, 2, 28, 16],
	"btn_danger_disabled": ["e9e2da", "a89a8e", 4, 999, 4, 28, 16],
	"btn_jade_normal": ["5cc9a7", "6b4a3a", 4, 999, 6, 28, 16],
	"btn_jade_pressed": ["48b493", "6b4a3a", 4, 999, 2, 28, 16],
	"btn_jade_disabled": ["d9cfc4", "8a7c70", 4, 999, 4, 28, 16],
	"btn_ghost_normal": ["00000000", "00000000", 0, 20, 0, 20, 12],
	"btn_ghost_pressed": ["6b4a3a1a", "00000000", 0, 20, 0, 20, 12],
	"btn_ghost_disabled": ["00000000", "00000000", 0, 20, 0, 20, 12],
	"bar_frame": ["f1e2c6", "6b4a3a", 4, 999, 0, 0, 0],
	"bar_fill_jade": ["5cc9a7", "00000000", 0, 999, 0, 0, 0],
	"bar_fill_gold": ["ff9f43", "00000000", 0, 999, 0, 0, 0],
	"bar_fill_cin": ["ff5a5f", "00000000", 0, 999, 0, 0, 0],
	"bar_fill_blue": ["5aaeff", "00000000", 0, 999, 0, 0, 0],
	"slot_empty": ["efe3cf", "cdb89f", 3, 24, 0, 0, 0],
	"slot_locked": ["e3d9cc", "9a8478", 4, 24, 0, 0, 0],
	"slot_selected": ["fff1c9", "e07b24", 6, 24, 5, 0, 0],
	"slot_r0": ["dfe2e7", "6b4a3a", 4, 24, 5, 0, 0],
	"slot_r1": ["b6e8a8", "6b4a3a", 4, 24, 5, 0, 0],
	"slot_r2": ["a9d4ff", "6b4a3a", 4, 24, 5, 0, 0],
	"slot_r3": ["d8bcff", "6b4a3a", 4, 24, 5, 0, 0],
	"slot_r4": ["ffcf8f", "6b4a3a", 4, 24, 5, 0, 0],
	"slot_r5": ["ffa8a8", "6b4a3a", 4, 24, 5, 0, 0],
	"disc": ["fff8ec", "6b4a3a", 5, 999, 7, 0, 0],
	"tab_dock": ["f9e4c4", "6b4a3a", 4, 0, 0, 0, 0],
	"tab_selected": ["ffe09c", "6b4a3a", 4, 26, 4, 0, 0],
}


static func has(id: String) -> bool:
	return SPECS.has(id)


static func box(id: String, modulate: Color = Color.WHITE) -> StyleBoxFlat:
	var spec: Array = SPECS.get(id, SPECS["panel_card"])
	var style := StyleBoxFlat.new()
	style.bg_color = Color(str(spec[0])) * modulate
	style.border_color = Color(str(spec[1]))
	style.set_border_width_all(int(spec[2]))
	style.set_corner_radius_all(int(spec[3]))
	style.corner_detail = 10
	if int(spec[4]) > 0:
		style.shadow_color = Color(0.42, 0.29, 0.23, 0.26)
		style.shadow_size = 1
		style.shadow_offset = Vector2(0, int(spec[4]))
	style.content_margin_left = int(spec[5])
	style.content_margin_right = int(spec[5])
	style.content_margin_top = int(spec[6])
	style.content_margin_bottom = int(spec[6])
	style.anti_aliasing = true
	return style


## 任意颜色的圆角描边盒（页面里少量特殊块用）。
static func custom(fill: Color, border: Color = UiTokens.Q_COCOA, width: int = 4, radius: int = 26, shadow: int = 6, pad_x: int = 20, pad_y: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.corner_detail = 10
	if shadow > 0:
		style.shadow_color = Color(0.42, 0.29, 0.23, 0.26)
		style.shadow_size = 1
		style.shadow_offset = Vector2(0, shadow)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	style.anti_aliasing = true
	return style


## 白字 + 可可色描边（设计稿的标题、按钮大字、数字）。
static func outline(label: Label, size: int = 8, color: Color = UiTokens.Q_WHITE) -> Label:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", UiTokens.Q_COCOA)
	label.add_theme_constant_override("outline_size", size)
	return label
