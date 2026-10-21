class_name BossHpBar
extends Control
## 首领大血条（SPEC_Q §17.1）：底槽 ui/bar_boss_bg_64（高 64，只横向拉伸），内侧 8px 处
## 下层 ui/bar_boss_trail_48（掉血残影：受击后延迟 0.35s 再 0.4s 缓降），上层 ui/bar_boss_fill_48（当前气血），
## 25/50/75% 处 4px 竖分隔，中间「当前 / 最大」白字描边。没有切图时代码画同样的形状。

const HEIGHT := 64.0
const INSET := 8.0
const TRAIL_DELAY := 0.35
const TRAIL_TIME := 0.4

var ratio := 1.0
var trail_ratio := 1.0
var _text: Label
var _bg: NinePatchRect
var _trail: NinePatchRect
var _fill: NinePatchRect
var _ticks: Control
var _tween: Tween


func _init() -> void:
	name = "BossHpBar"
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = _patch("bar_boss_bg_64", 32)
	_bg.name = "Bg"
	_trail = _patch("bar_boss_trail_48", 24)
	_trail.name = "Trail"
	_fill = _patch("bar_boss_fill_48", 24)
	_fill.name = "Fill"
	_ticks = Control.new()
	_ticks.name = "Ticks"
	_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticks.draw.connect(_draw_ticks)
	add_child(_ticks)
	_text = QKit.outlined("", 36, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 7, HORIZONTAL_ALIGNMENT_CENTER, false)
	_text.name = "HpText"
	_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	resized.connect(_layout)


func _patch(cut: String, margin: int) -> NinePatchRect:
	var rect := NinePatchRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = ArtLib.qui(cut)
	rect.patch_margin_left = margin
	rect.patch_margin_right = margin
	rect.patch_margin_top = margin
	rect.patch_margin_bottom = margin
	if rect.texture == null:
		# 没有切图：代码画（深棕底 / 金白残影 / 红色当前）
		rect.draw.connect(func() -> void:
			var color := Color("3a1e14") if cut.begins_with("bar_boss_bg") else (Color("fff1c4") if cut.contains("trail") else UiTokens.Q_RED)
			rect.draw_rect(Rect2(Vector2.ZERO, rect.size), color))
	add_child(rect)
	return rect


## 设当前气血。animate=true 时残影延迟后缓降；回血 / 重开直接对齐。
func set_hp(current: float, maximum: float, animate: bool = true) -> void:
	var next := clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	_text.text = "%s / %s" % [QKit.grouped(BagModel.shown(maxf(current, 0.0))), QKit.grouped(BagModel.shown(maximum))]
	var dropped := next < ratio - 0.0001
	ratio = next
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animate and dropped and is_inside_tree():
		_tween = create_tween()
		_tween.tween_interval(TRAIL_DELAY)
		_tween.tween_method(_set_trail, trail_ratio, ratio, TRAIL_TIME)
	else:
		trail_ratio = ratio
	_layout()


func text() -> String:
	return _text.text


func _set_trail(value: float) -> void:
	trail_ratio = value
	_layout()


func _layout() -> void:
	_bg.position = Vector2.ZERO
	_bg.size = Vector2(size.x, HEIGHT)
	var inner := Rect2(INSET, INSET, maxf(size.x - INSET * 2.0, 0.0), HEIGHT - INSET * 2.0)
	# 九宫格左右各 24：宽度小于 48 时干脆不画，免得两头的圆角挤在一起
	for pair in [[_trail, trail_ratio], [_fill, ratio]]:
		var rect := pair[0] as NinePatchRect
		var w := inner.size.x * float(pair[1])
		rect.visible = w >= 1.0
		rect.position = inner.position
		rect.size = Vector2(maxf(w, 48.0) if w >= 1.0 else 0.0, inner.size.y)
	_ticks.position = inner.position
	_ticks.size = inner.size
	_ticks.queue_redraw()


func _draw_ticks() -> void:
	for k in [0.25, 0.5, 0.75]:
		var x := _ticks.size.x * float(k)
		_ticks.draw_rect(Rect2(x - 2.0, 0, 4.0, _ticks.size.y), Color(58.0 / 255.0, 30.0 / 255.0, 20.0 / 255.0, 0.35))
