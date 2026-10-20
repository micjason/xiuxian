extends Control
## 血条「白色延迟残影」：血条一掉，白色的一段先停 0.3 秒，再平滑追上。
## 用法：放进血条容器里，铺满，排在血条之后、气血文字之前；每次刷新血条时调用 set_ratio(新比例)。
## 只在数值变化时重画；残影追上后自动停止 _process，平时零开销。

@export var inset := Vector2(2, 3)      ## 和 UiKit.ratio_bar 的填充条缩进一致（左右 2、上下 3）
@export var min_ratio := 0.06           ## ratio_bar 的填充条最短 6%
@export var hold := 0.3
@export var follow_speed := 7.0
@export var color := Color(1, 1, 1, 0.95)

var _ratio := 1.0
var _lag := 1.0
var _hold_t := 0.0
var _sb: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_sb = StyleBoxFlat.new()
	_sb.bg_color = color
	_sb.corner_radius_top_right = 12
	_sb.corner_radius_bottom_right = 12
	set_process(false)


## 立即对齐（开战前 / 换关卡时）。
func reset(ratio: float = 1.0) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_lag = _ratio
	set_process(false)
	queue_redraw()


func set_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if ratio >= _lag:
		reset(ratio)
		return
	if is_equal_approx(ratio, _ratio):
		return
	_ratio = ratio
	_hold_t = hold
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _hold_t > 0.0:
		_hold_t -= delta
		return
	_lag = lerpf(_lag, _ratio, 1.0 - exp(-delta * follow_speed))
	if _lag - _ratio < 0.003:
		_lag = _ratio
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _lag <= _ratio + 0.001:
		return
	var w := size.x
	var x0 := w * maxf(_ratio, min_ratio) - inset.x
	var x1 := w * _lag - inset.x
	if x1 - x0 < 1.0:
		return
	draw_style_box(_sb, Rect2(x0, inset.y, x1 - x0, size.y - inset.y * 2.0))
