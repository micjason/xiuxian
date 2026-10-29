class_name UltChargeDisc
extends Control
## 自动技能充能圆盘（不是按钮，mouse_filter=IGNORE，没有 pressed / gui_input 释放）：
## radial_bg_176 + radial_fill_166（顺时针，value=蓄力%）+ radial_center_132 + 技能图标 + 蓄力 %。
## 下方只写「冷却完自动释放」。蓄满瞬间光效淡出，释放由战斗逻辑自动出事件，圆盘本身不能点。
## 本境界没学会：整体 modulate 0.6，% 处写「未学会」。

const SIZE := 204.0

var charge := 0.0
var learned := true
var _bar: TextureProgressBar
var _glow: TextureRect
var _pct: Label
var _icon: TextureRect


func _init() -> void:
	name = "UltChargeDisc"
	custom_minimum_size = Vector2(SIZE, SIZE + 30.0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow = _rect(ArtLib.qui("ult_ready_glow"), Vector2(220, 220))
	_glow.name = "ReadyGlow"
	_glow.modulate.a = 0.0
	_glow.pivot_offset = Vector2(110, 110)
	_glow.position = Vector2((SIZE - 220.0) / 2.0, (176.0 - 220.0) / 2.0 + 8.0)
	add_child(_glow)
	var bg := _rect(ArtLib.qui("radial_bg_176"), Vector2(176, 176))
	bg.position = Vector2((SIZE - 176.0) / 2.0, 8)
	add_child(bg)
	_bar = TextureProgressBar.new()
	_bar.name = "Charge"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	_bar.texture_progress = ArtLib.qui("radial_fill_166")
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.position = Vector2((SIZE - 166.0) / 2.0, 13)
	_bar.size = Vector2(166, 166)
	add_child(_bar)
	var center := _rect(ArtLib.qui("radial_center_132"), Vector2(132, 132))
	center.position = Vector2((SIZE - 132.0) / 2.0, 30)
	add_child(center)
	var tex: Texture2D = ArtLib.q("items/eq_sword") if ArtLib.has_q("items/eq_sword.png") else null
	_icon = _rect(tex, Vector2(80, 80))
	_icon.name = "UltIcon"
	_icon.position = Vector2((SIZE - 80.0) / 2.0, 34)
	add_child(_icon)
	_pct = QKit.outlined("0%", 36, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 7, HORIZONTAL_ALIGNMENT_CENTER, false)
	_pct.name = "ChargeText"
	_pct.position = Vector2(0, 104)
	_pct.size = Vector2(SIZE, 44)
	_pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pct)
	# 只提示冷却完会自动放，不是按钮，不接收点击。
	var auto := QKit.outlined("冷却完自动释放", 22, UiTokens.Q_WHITE, UiTokens.Q_ORANGE_DARK, 6, HORIZONTAL_ALIGNMENT_CENTER, false)
	auto.name = "AutoLabel"
	auto.position = Vector2(0, 172)
	auto.size = Vector2(SIZE, 36)
	add_child(auto)
	_ignore_mouse(self)
	if _bar.texture_progress == null:
		_bar.draw.connect(func() -> void:
			_bar.draw_arc(Vector2(83, 83), 76, -PI / 2.0, -PI / 2.0 + TAU * charge, 64, UiTokens.Q_ORANGE, 12.0, true))


## 圆盘里所有节点都不接收鼠标 / 触摸（点了也不会有任何反应）。
static func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_ignore_mouse(child)


func _rect(tex: Texture2D, box: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size = box
	rect.custom_minimum_size = box
	return rect


## 0..1 蓄力；learned=false = 本境界没有大招。
func set_charge(value: float, has_ult: bool = true) -> void:
	learned = has_ult
	charge = clampf(value, 0.0, 1.0) if has_ult else 0.0
	_bar.value = charge * 100.0
	_bar.queue_redraw()
	modulate = Color(1, 1, 1, 1) if has_ult else Color(0.6, 0.6, 0.6, 1)
	if has_ult:
		_pct.text = "%d%%" % int(floor(charge * 100.0))
		_pct.add_theme_font_size_override("font_size", 36)
	else:
		_pct.text = "未学会"
		_pct.add_theme_font_size_override("font_size", 26)


func charge_text() -> String:
	return _pct.text


## 蓄满自动施放的那一刻：金光 0.9→1.15 放大、1→0 淡出（0.45s）。
func flash_ready() -> void:
	_glow.scale = Vector2.ONE * 0.9
	_glow.modulate.a = 1.0
	if not is_inside_tree():
		_glow.modulate.a = 0.0
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_glow, "scale", Vector2.ONE * 1.15, 0.45)
	tween.tween_property(_glow, "modulate:a", 0.0, 0.45)
