class_name QBreakButton
extends Button
## 底栏正中的「突破」大圆钮（设计稿 q_cultivate 底栏）：外圈奶油盘 + 橙色圆钮 + 光晕 + 虚线环 + 红点。
## 三种状态（state）：ready = 能突破（亮、带光晕和红点）；hint = 还差条件（变淡，点了提示差什么）；
## max = 已到最高境界（灰、不可点）。
## 外观用美术切图（SPEC_Q：orb_glow 320 呼吸 → orb_ring_dashed 252 慢转 → orb_normal/pressed 220）：
## ready 用带字的 orb_normal / orb_pressed；hint 用 orb_normal_notext 调淡 + 代码字「突破」；max 灰化 + 「已圆满」。
## 没有切图时退回 _draw 画的圆盘。
## 2026-10-20 起优先用动画交付的 ui_fx/ui_break_orb.tscn（README 2c）：idle 循环（外圈光晕呼吸、虚线圈慢转、星星闪、金色光点），
## 按下 / 松开播 PressPlayer 的 press / release。三种状态照旧：ready 全套光效；hint 收起光效、圆钮调淡；max 灰化 + 「已圆满」。

const SIZE := 220.0
const DISC := 192.0

var state := "hint"
var _label: Label
var _dot: Control
var _art: TextureRect
var _t := 0.0
var _glow: Texture2D
var _ring: Texture2D
var _orb: Control
const ORB_SIZE := 420.0
const ORB_GLOW_NODES := ["Glow", "Halo", "Ring", "Star1", "Star2", "Star3", "Sparkles"]


func _init() -> void:
	name = "BreakthroughCenter"
	custom_minimum_size = Vector2(SIZE, SIZE)
	focus_mode = Control.FOCUS_NONE
	flat = true
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(key, StyleBoxEmpty.new())
	_art = TextureRect.new()
	_art.name = "Art"
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	_art.offset_bottom = 4  # 切图 220x224，下方 4px 是投影
	add_child(_art)
	_glow = ArtLib.qui("orb_glow")
	_ring = ArtLib.qui("orb_ring_dashed")
	_orb = QFx.make(QFx.BREAK_ORB) as Control
	if _orb != null:
		_orb.name = "Orb"
		_orb.position = Vector2(SIZE - ORB_SIZE, SIZE - ORB_SIZE) / 2.0  # 圆心对齐按钮中心
		_orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hit := _orb.get_node_or_null("Hit") as Button
		if hit != null:  # 点击由本按钮处理（三种状态、禁用），场景自带的透明按钮不接手指
			hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hit.disabled = true
		add_child(_orb)
	_label = QKit.outlined("突破", 66, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 16, HORIZONTAL_ALIGNMENT_CENTER)
	_label.name = "Title"
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_bottom = -8
	add_child(_label)
	_dot = QKit.reddot(44)
	_dot.set_anchors_preset(Control.PRESET_CENTER)
	_dot.offset_left = 62
	_dot.offset_right = 106
	_dot.offset_top = -100
	_dot.offset_bottom = -56
	_dot.visible = false
	add_child(_dot)


func set_state(value: String) -> void:
	state = value
	disabled = value == "max"
	_label.text = "已圆满" if value == "max" else "突破"
	_label.add_theme_font_size_override("font_size", 50 if value == "max" else 66)
	_dot.visible = value == "ready"
	_update_art()
	set_process(value == "ready" and _ring != null and _orb == null)
	queue_redraw()


func _update_art() -> void:
	if _orb != null:
		_update_orb()
		return
	var baked := ArtLib.qui("orb_pressed" if (button_pressed or is_pressed()) else "orb_normal")
	var plain := ArtLib.qui("orb_normal_notext")
	_art.visible = plain != null
	if not _art.visible:
		_label.visible = true
		return
	if state == "ready" and baked != null:
		_art.texture = baked
		_art.modulate = Color.WHITE
		_label.visible = false
	else:
		_art.texture = plain
		_art.modulate = Color(1.0, 0.92, 0.85, 0.78) if state == "hint" else Color(0.72, 0.7, 0.68, 1.0)
		_label.visible = true


func _update_orb() -> void:
	_art.visible = false
	var ready := state == "ready"
	for path in ORB_GLOW_NODES:
		var node := _orb.get_node_or_null(path) as CanvasItem
		if node != null:
			node.visible = ready
			if node is CPUParticles2D:
				(node as CPUParticles2D).emitting = ready
	var base := _orb.get_node_or_null("Press/Base") as CanvasItem
	if base != null:
		base.modulate = Color.WHITE if ready else (Color(1.0, 0.92, 0.85, 0.78) if state == "hint" else Color(0.72, 0.7, 0.68, 1.0))
	var text := _orb.get_node_or_null("Press/Text") as CanvasItem
	if text != null:
		text.visible = state != "max"
		text.modulate = Color.WHITE if ready else Color(1, 1, 1, 0.85)
	_label.visible = state == "max"
	var ap := QFx.player(_orb)
	if ap != null:
		if ready and ap.has_animation("idle"):
			if ap.current_animation != "idle":
				ap.play("idle")
		else:
			ap.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		button_down.connect(_on_press_change)
		button_up.connect(_on_press_change)


func _on_press_change() -> void:
	if _orb != null:
		if not disabled:
			QFx.play(_orb, "press" if is_pressed() else "release", "PressPlayer")
		return
	_update_art()
	_label.offset_top = 6.0 if is_pressed() else 0.0
	_label.offset_bottom = -2.0 if is_pressed() else -8.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 是否用美术切图（测试用）。
func uses_art() -> bool:
	return _art.visible or _orb != null


## 用的是动画圆钮（ui_break_orb）。
func uses_orb_fx() -> bool:
	return _orb != null


func orb_animation() -> String:
	var ap := QFx.player(_orb)
	return ap.current_animation if ap != null else ""


func has_dot() -> bool:
	return _dot.visible


func title_text() -> String:
	return _label.text


func _draw() -> void:
	if _orb != null:
		return
	if _art.visible:
		if state == "ready":
			var c := size / 2.0
			if _glow != null:
				var a := 0.85 + 0.15 * sin(_t * TAU / 3.0)
				draw_texture_rect(_glow, Rect2(c - Vector2(160, 160), Vector2(320, 320)), false, Color(1, 1, 1, a))
			if _ring != null:
				draw_set_transform(c, _t * TAU / 20.0, Vector2.ONE)
				draw_texture_rect(_ring, Rect2(Vector2(-126, -126), Vector2(252, 252)), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var c := size / 2.0
	var ready := state == "ready"
	if ready:
		for i in 6:
			var r := 160.0 - float(i) * 14.0
			draw_circle(c, r, Color(1.0, 0.86, 0.45, 0.07 + 0.03 * float(i)))
		_dashed_ring(c, 126.0, Color(1.0, 0.75, 0.24, 0.95))
	draw_circle(c, SIZE / 2.0, UiTokens.Q_COCOA)
	draw_circle(c, SIZE / 2.0 - 5.0, UiTokens.Q_CREAM)
	var disc := DISC / 2.0
	var fill := UiTokens.Q_ORANGE
	var dark := UiTokens.Q_ORANGE_DARK
	var light := Color("ffd27a")
	if state == "hint":
		fill = Color("f7c48c")
		dark = Color("e2a66a")
		light = Color("fbdcb4")
	elif state == "max":
		fill = Color("cfc6bc")
		dark = Color("afa398")
		light = Color("e9e2da")
	if is_pressed() or button_pressed:
		fill = dark
	draw_circle(c + Vector2(0, 8), disc, Color(UiTokens.Q_COCOA, 0.35))
	draw_circle(c, disc, UiTokens.Q_COCOA)
	draw_circle(c, disc - 5.0, dark)
	draw_circle(c + Vector2(0, -6), disc - 9.0, fill)
	draw_circle(c + Vector2(0, -disc * 0.35), disc * 0.42, Color(light, 0.55))


func _dashed_ring(center: Vector2, radius: float, color: Color) -> void:
	var steps := 40
	for i in steps:
		if i % 2 == 1:
			continue
		var a0 := TAU * float(i) / float(steps)
		var a1 := TAU * float(i + 1) / float(steps)
		draw_arc(center, radius, a0, a1, 6, color, 5.0, true)

