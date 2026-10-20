class_name TabBarView
extends Control
## 底部标签栏（Q 版设计稿）：五格 —— 修炼 / 历练 / 【突破】/ 功法 / 背包。
## 中间是凸出底栏的「突破」大圆钮（QBreakButton），下面一行小字写下一境界名；点它发 center_pressed，
## 由外壳决定打开突破弹窗还是提示还差什么（见 set_center）。其余四格点击发 page_selected(页面 id)。
## 选中格：浅金圆角底板 + 图标放大上浮 + 白字描边；未选中：图标偏灰 + 灰字。红点 set_dot。
## 整块（底栏 + 下方同色填充）贴屏幕最底边，见 apply_safe_area。
## 不叫 TabBar：避免和 Godot 内置的 TabBar 控件重名。图标在 assets/art/q/icons/tab_*.png（彩色，不染色）。

signal page_selected(page: String)
signal center_pressed

const HEIGHT := 168
## 标签栏下面的同色填充（手势条 / Home 指示条的位置）：至少 48 画布像素，系统手势条更高时取系统值。
const SAFE_FILL_MIN := 48
const FILL_COLOR := Color("f6deb9")
## 中间大圆钮的圆心相对底栏上沿的高度（负数 = 在上沿之上，设计稿 TT-14）。
const CENTER_Y := -14.0

## 页签 id → 美术底栏图标切图前缀（ui/<前缀>_active 112x118 / _normal 96x96）。
const TAB_CUTS := {"cultivate": "tab_cultivate", "adventure": "tab_adventure", "skill": "tab_techniques", "bag": "tab_bag"}

var _tabs: Array[Dictionary] = []
var _buttons: Dictionary = {}
var _dots: Dictionary = {}
var _bgs: Dictionary = {}
var _icons: Dictionary = {}
var _labels: Dictionary = {}
var _center_id := ""
var _center: QBreakButton
var _center_sub: Label
var current := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dock := Panel.new()
	dock.name = "DockArt"
	dock.set_anchors_preset(Control.PRESET_FULL_RECT)
	dock.offset_left = -6
	dock.offset_right = 6
	dock.mouse_filter = Control.MOUSE_FILTER_STOP
	var bar_tex := ArtLib.qui("tabbar_bg")
	if bar_tex != null:
		# 美术底栏 1080x222：含上方 6px 投影；九宫格只横向拉伸。下方安全区填同色 #F6DEB9。
		var art := ArtLib.q_nine("tabbar_bg")
		dock.set_anchors_preset(Control.PRESET_TOP_WIDE)
		dock.offset_left = 0
		dock.offset_right = 0
		dock.offset_top = -6
		dock.offset_bottom = 222 - 6
		dock.add_theme_stylebox_override("panel", art)
		add_child(dock)
		_finish_init()
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fbe9cc")
	style.border_color = UiTokens.Q_COCOA
	style.border_width_top = 5
	style.corner_radius_top_left = 46
	style.corner_radius_top_right = 46
	style.corner_detail = 12
	style.shadow_color = Color(0.42, 0.29, 0.23, 0.12)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, -4)
	style.anti_aliasing = true
	dock.add_theme_stylebox_override("panel", style)
	add_child(dock)
	_finish_init()


func _finish_init() -> void:
	var fill := ColorRect.new()
	fill.name = "DockFill"
	fill.color = FILL_COLOR
	fill.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	fill.offset_top = -float(SAFE_FILL_MIN)
	fill.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(fill)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)


## tabs: [{id, name, icon, center?}]。center=true 的那一格是中间的大圆钮（最多一个）。
func set_tabs(tabs: Array[Dictionary], selected: String) -> void:
	_tabs = tabs
	var row := get_node("Row") as HBoxContainer
	UiKit.clear(row)
	if _center != null:
		_center.queue_free()
		_center = null
	_buttons.clear()
	_dots.clear()
	_bgs.clear()
	_icons.clear()
	_labels.clear()
	_center_id = ""
	for tab in tabs:
		var id := str(tab.get("id", ""))
		if bool(tab.get("center", false)):
			_build_center(row, id, str(tab.get("name", "突破")))
			continue
		var button := Button.new()
		button.name = "Tab_" + id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.flat = true
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.pressed.connect(_on_pressed.bind(id))
		row.add_child(button)
		_buttons[id] = button
		var bg := Panel.new()
		bg.name = "Selected"
		bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
		bg.offset_left = -84
		bg.offset_right = 84
		bg.offset_top = 8
		bg.offset_bottom = 158
		var plate_tex := ArtLib.qui("tab_sel_plate")
		if plate_tex != null:
			var plate := StyleBoxTexture.new()
			plate.texture = plate_tex
			bg.add_theme_stylebox_override("panel", plate)
			bg.offset_bottom = 8 + 155
		else:
			bg.add_theme_stylebox_override("panel", QSkin.custom(Color("ffe3a0"), UiTokens.Q_COCOA, 4, 32, 5, 0, 0))
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.visible = false
		button.add_child(bg)
		_bgs[id] = bg
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = ArtLib.icon_or(str(tab.get("icon", "")), str(tab.get("fallback", "ui_gate")))
		var cut := str(TAB_CUTS.get(id, ""))
		if not cut.is_empty() and ArtLib.qui(cut + "_active") != null and ArtLib.qui(cut + "_normal") != null:
			icon.set_meta(&"active_tex", ArtLib.qui(cut + "_active"))
			icon.set_meta(&"normal_tex", ArtLib.qui(cut + "_normal"))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not ArtLib.is_color_icon(str(tab.get("icon", ""))):
			icon.modulate = UiTokens.TEXT_MUTED
		button.add_child(icon)
		_icons[id] = icon
		var label := QKit.title(str(tab.get("name", id)), 32, Color("8e7566"), HORIZONTAL_ALIGNMENT_CENTER)
		label.name = "Label"
		label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		label.offset_left = -100
		label.offset_right = 100
		label.offset_top = 112
		label.offset_bottom = 160
		button.add_child(label)
		_labels[id] = label
		var dot := QKit.reddot(38)
		dot.set_anchors_preset(Control.PRESET_CENTER_TOP)
		dot.offset_left = 30
		dot.offset_right = 68
		dot.offset_top = 10
		dot.offset_bottom = 48
		dot.visible = false
		button.add_child(dot)
		_dots[id] = dot
	current = selected
	_refresh()


func _build_center(row: HBoxContainer, id: String, sub_text: String) -> void:
	_center_id = id
	var slot := Control.new()
	slot.name = "CenterSlot"
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(slot)
	_center_sub = QKit.outlined(sub_text, 32, UiTokens.Q_WHITE, UiTokens.Q_ORANGE_DARK, 10, HORIZONTAL_ALIGNMENT_CENTER)
	_center_sub.name = "CenterSub"
	_center_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_center_sub.offset_left = -110
	_center_sub.offset_right = 110
	_center_sub.offset_top = 116
	_center_sub.offset_bottom = 160
	_center_sub.clip_text = true
	slot.add_child(_center_sub)
	_center = QBreakButton.new()
	_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_center.offset_left = -QBreakButton.SIZE / 2.0
	_center.offset_right = QBreakButton.SIZE / 2.0
	_center.offset_top = CENTER_Y - QBreakButton.SIZE / 2.0
	_center.offset_bottom = CENTER_Y + QBreakButton.SIZE / 2.0
	_center.pressed.connect(func() -> void: center_pressed.emit())
	add_child(_center)
	_buttons[id] = _center
	_dots[id] = _center.get_node("RedDot")


## 中间大圆钮：state = ready / hint / max；sub = 下面的小字（下一境界名，最高境界写「已圆满」）。
func set_center(state: String, sub: String) -> void:
	if _center == null:
		return
	_center.set_state(state)
	_center_sub.text = sub
	_center_sub.add_theme_color_override("font_outline_color", UiTokens.Q_ORANGE_DARK if state != "max" else Color("8a7c70"))


func center_button() -> QBreakButton:
	return _center


func center_state() -> String:
	return _center.state if _center != null else ""


func center_sub_text() -> String:
	return _center_sub.text if _center_sub != null else ""


## 点页签：即使已在这个页签也发信号（修炼页签下的洞府、历练页签下的首领战要靠它回到主页）。
func _on_pressed(id: String) -> void:
	select(id, false)
	page_selected.emit(id)


func select(id: String, emit: bool = false) -> void:
	if not _buttons.has(id) or id == _center_id:
		return
	var changed := id != current
	current = id
	_refresh()
	if emit and changed:
		page_selected.emit(id)


func set_dot(id: String, on: bool) -> void:
	if id == _center_id:
		return  # 中间钮的红点跟着 set_center 的 ready 状态走
	if _dots.has(id):
		(_dots[id] as CanvasItem).visible = on


func has_dot(id: String) -> bool:
	if id == _center_id and _center != null:
		return _center.has_dot()
	return _dots.has(id) and (_dots[id] as CanvasItem).visible


func button_of(id: String) -> Button:
	return _buttons.get(id, null)


## 标签栏下面的填充高度（画布像素）。
static func bottom_pad(inset: Vector4) -> float:
	return maxf(float(SAFE_FILL_MIN), inset.w)


## 整块（标签栏 + 同色填充）贴在屏幕最底边；左右安全区只缩小可点区域，底板仍然通宽。
func apply_safe_area(inset: Vector4) -> void:
	var pad := bottom_pad(inset)
	offset_left = 0.0
	offset_right = 0.0
	offset_top = -(float(HEIGHT) + pad)
	offset_bottom = 0.0
	(get_node("DockFill") as Control).offset_top = -pad
	var row := get_node("Row") as Control
	row.offset_left = inset.x
	row.offset_right = -inset.z
	row.offset_bottom = -pad


func _refresh() -> void:
	for id in _icons:
		var active: bool = id == current
		(_bgs[id] as CanvasItem).visible = active
		var icon := _icons[id] as TextureRect
		var size := 112.0 if active else 96.0
		icon.offset_left = -size / 2.0
		icon.offset_right = size / 2.0
		icon.offset_top = -8.0 if active else 18.0
		icon.offset_bottom = icon.offset_top + (118.0 if active else 96.0)
		if icon.has_meta(&"active_tex"):
			icon.texture = icon.get_meta(&"active_tex" if active else &"normal_tex")
			icon.self_modulate = Color.WHITE
		else:
			icon.offset_bottom = icon.offset_top + size
			icon.self_modulate = Color.WHITE if active else Color(0.93, 0.9, 0.88, 0.9)
		var label := _labels[id] as Label
		if active:
			QSkin.outline(label, 12)
			label.add_theme_font_size_override("font_size", 36)
			label.offset_top = 108
		else:
			label.add_theme_color_override("font_color", Color("8e7566"))
			label.add_theme_constant_override("outline_size", 0)
			label.add_theme_font_size_override("font_size", 32)
			label.offset_top = 116
