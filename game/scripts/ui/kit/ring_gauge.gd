class_name RingGauge
extends Control
## 环形进度（代码画，不用图）：底环 + 进度弧，从正上方顺时针。子控件放中间（比如百分比文字）。
## 突破流程界面的「战力提升」「成功率」环用它。

var ratio := 0.0:
	set(value):
		ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
var color := UiTokens.JADE_FILL:
	set(value):
		color = value
		queue_redraw()
var track_color := Color(1, 1, 1, 0.14)
var thickness := 18.0


func _init(diameter: float = 200.0) -> void:
	custom_minimum_size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - thickness / 2.0
	draw_circle(center, radius + thickness / 2.0 - 2.0, Color(0.03, 0.06, 0.06, 0.78))
	draw_arc(center, radius, 0.0, TAU, 96, track_color, thickness, true)
	if ratio > 0.0:
		draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * ratio, 96, color, thickness, true)
