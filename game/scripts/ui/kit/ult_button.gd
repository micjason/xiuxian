class_name UltButton
extends Control
## 大招圆钮：金边红底、外圈冷却环（代码画，没有正式切图时就是最终效果；N128/N131 交付后可换图）。
## ratio 0..1 = 冷却进度（1 = 冷却完毕）；ready 时按钮亮并有呼吸光；sub_text 写“1.8s”之类。
## 只在 ready 时响应点击，点击发 tapped。

signal tapped

const SIZE := 232.0

var ratio := 0.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
var ready_now := false:
	set(value):
		ready_now = value
		queue_redraw()
var title := "大招":
	set(value):
		title = value
		queue_redraw()
var sub_text := "":
	set(value):
		sub_text = value
		queue_redraw()
var enabled := true:
	set(value):
		enabled = value
		queue_redraw()
var _pulse := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _process(delta: float) -> void:
	if ready_now and enabled:
		_pulse = fmod(_pulse + delta * 3.0, TAU)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed and ready_now and enabled:
		tapped.emit()
		accept_event()


func _draw() -> void:
	var center := size / 2.0
	var outer := minf(size.x, size.y) / 2.0
	var ring_w := 14.0
	var ring_r := outer - ring_w / 2.0 - 2.0
	var live := ready_now and enabled
	if live:
		draw_circle(center, outer, Color(UiTokens.GOLD, 0.10 + 0.10 * (0.5 + 0.5 * sin(_pulse))))
	draw_arc(center, ring_r, 0.0, TAU, 96, Color(0.05, 0.08, 0.08, 0.9), ring_w, true)
	draw_arc(center, ring_r, -PI / 2.0, -PI / 2.0 + TAU * ratio, 96, UiTokens.GOLD_HOVER if live else UiTokens.GOLD_PRESSED, ring_w, true)
	var inner := ring_r - ring_w / 2.0 - 6.0
	draw_circle(center, inner + 4.0, UiTokens.GOLD_BORDER)
	draw_circle(center, inner, Color(0.62, 0.12, 0.10) if live else Color(0.28, 0.1, 0.09))
	draw_circle(center, inner - 12.0, Color(0.78, 0.17, 0.13, 0.55) if live else Color(0.22, 0.08, 0.07, 0.6))
	var font := ArtLib.title_font()
	var color := Color(1.0, 0.92, 0.7) if live else Color(0.78, 0.7, 0.62)
	var title_size := 64
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	draw_string_outline(font, Vector2(center.x - title_width / 2.0, center.y + 6.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, 8, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(center.x - title_width / 2.0, center.y + 6.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, color)
	if not sub_text.is_empty():
		var body := ArtLib.body_font()
		var sub_size := 34
		var sub_width := body.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
		draw_string(body, Vector2(center.x - sub_width / 2.0, center.y + 56.0), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, color)
