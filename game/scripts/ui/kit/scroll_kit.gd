class_name ScrollKit
extends Node
## 全局滚动助手（v14）：所有 ScrollContainer 统一
##   1. 不显示滚动条（横竖都 SCROLL_MODE_SHOW_NEVER，照样能滚；主题里滚动条样式也是空的，双保险）；
##   2. 手指拖动跟手 + 松手惯性滑行（Godot 自带的触屏拖动只在事件能冒泡到 ScrollContainer 时才生效，
##      而格子 / 关卡卡都是 Button（MOUSE_FILTER_STOP），按在上面拖就滚不动——这是「背包经常滚不动」的根因）；
##   3. 拖动超过死区后不会再触发点击：开始拖动时给内容发 NOTIFICATION_SCROLL_BEGIN（Godot 的 BaseButton
##      收到后取消这次按下），另外 tap_blocked() 给自己处理点击的地方再兜一层。
## 用法：ScrollKit.install(root) 一次（PlayScreen 启动时调用），之后树里新加的 ScrollContainer 自动接管；
## 单独用：ScrollKit.setup(scroll)。
## 实现：在 _input 里看鼠标事件（手机上触摸默认会模拟成鼠标事件，input_devices/pointing/emulate_mouse_from_touch），
## 不依赖 DisplayServer.is_touchscreen_available()，所以桌面和测试里也是同一套逻辑。
## ScrollContainer 自己设成 MOUSE_FILTER_IGNORE，避免自带的触屏拖动 / 惯性和这里叠加（滚轮也由这里处理）。

const META := &"scroll_kit"
## 死区（画布像素，1080 宽 ≈ 3px/dp → 约 6dp）：手指移动不到这个距离算点击。
const DEADZONE := 18.0
## 惯性：速度按 e^(-FRICTION·t) 衰减；低于 MIN_FLING 停。
const FRICTION := 4.0
const MIN_FLING := 40.0
const MAX_FLING := 12000.0
## 用最近这么多毫秒的移动估算松手速度；手指停住超过 STALE_MS 再松手就不滑。
const SAMPLE_MS := 100
const STALE_MS := 80
const WHEEL_STEP := 160.0

## 当前这次按下是否已经拖动过（拖过就不算点击，直到下一次按下）。
static var _gesture_dragged := false
static var _gesture_press: InputEvent = null
## 当前接管这次手势的助手（嵌套滚动时只有一个能接管）。
static var _owner: ScrollKit = null
static var drag_count := 0
static var _installed: Dictionary = {}

var scroll: ScrollContainer
var _pressing := false
var _dragging := false
var _gave_up := false
var _press_pos := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _samples: Array[Vector3] = []  # (ticks_ms, x, y)
var _pos := 0.0
var _velocity := 0.0
var _flinging := false
## 最近一次拖动 / 惯性里每帧的耗时（毫秒，测量用）。
var frame_ms: PackedFloat32Array = PackedFloat32Array()


## 在 root 所在的场景树上接管所有 ScrollContainer（已有的 + 以后加进来的）。重复调用无害。
static func install(root: Node) -> void:
	if root == null or not root.is_inside_tree():
		return
	var tree := root.get_tree()
	var key := tree.get_instance_id()
	if not _installed.has(key):
		_installed[key] = true
		tree.node_added.connect(_on_node_added)
	_walk(root)


static func _walk(node: Node) -> void:
	if node is ScrollContainer:
		setup(node as ScrollContainer)
	for child in node.get_children():
		_walk(child)


static func _on_node_added(node: Node) -> void:
	if node is ScrollContainer:
		setup(node as ScrollContainer)


static func setup(target: ScrollContainer) -> ScrollKit:
	if target.has_meta(META):
		var existing: Variant = target.get_meta(META)
		if existing is ScrollKit and is_instance_valid(existing):
			return existing as ScrollKit
	hide_bars(target)
	var kit := ScrollKit.new()
	kit.name = "ScrollKit"
	kit.scroll = target
	target.set_meta(META, kit)
	target.add_child(kit, false, Node.INTERNAL_MODE_BACK)
	return kit


static func of(target: ScrollContainer) -> ScrollKit:
	var kit: Variant = target.get_meta(META, null)
	return kit as ScrollKit if kit is ScrollKit and is_instance_valid(kit) else null


## 横竖滚动条都不显示，滚动功能保留（禁用的方向保持禁用）。
static func hide_bars(target: ScrollContainer) -> void:
	if target.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		target.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	if target.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		target.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	target.get_v_scroll_bar().visible = false
	target.get_h_scroll_bar().visible = false
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 这次按下拖动过（或者按下时打断了惯性）→ 松手不算点击。自己处理点击的地方在回调开头判断。
static func tap_blocked() -> bool:
	return _gesture_dragged


static func _end_gesture() -> void:
	_gesture_dragged = false


## 给按钮的 pressed 回调包一层：拖动后的松手不触发。
static func guard(callback: Callable) -> Callable:
	return func() -> void:
		if not _gesture_dragged:
			callback.call()


func _ready() -> void:
	set_process(false)
	for bar: ScrollBar in [scroll.get_v_scroll_bar(), scroll.get_h_scroll_bar()]:
		bar.visibility_changed.connect(_on_bar_visibility.bind(bar))
	hide_bars.call_deferred(scroll)


func _on_bar_visibility(bar: ScrollBar) -> void:
	if bar.visible:
		hide_bars.call_deferred(scroll)


func vertical() -> bool:
	return scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED


func _bar() -> ScrollBar:
	return scroll.get_v_scroll_bar() if vertical() else scroll.get_h_scroll_bar()


func max_scroll() -> float:
	var bar := _bar()
	return maxf(0.0, bar.max_value - bar.page)


func is_dragging() -> bool:
	return _dragging


func is_flinging() -> bool:
	return _flinging


func _axis(v: Vector2) -> float:
	return v.y if vertical() else v.x


func _cross(v: Vector2) -> float:
	return v.x if vertical() else v.y


func _screen_rect() -> Rect2:
	var xform := scroll.get_global_transform_with_canvas()
	return Rect2(xform.origin, scroll.size * xform.get_scale())


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and event != _gesture_press:
		_gesture_press = event
		_gesture_dragged = false
		_owner = null
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and _gesture_dragged:
		# 松手这一帧里按钮的回调还能看到「拖过」，帧末清掉，之后代码里直接 emit 的点击不受影响。
		_end_gesture.call_deferred()
	if scroll == null or not scroll.is_visible_in_tree():
		if _pressing or _flinging:
			_stop()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb)
			else:
				_on_release(mb.position)
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			_on_wheel(mb)
	elif event is InputEventMouseMotion and _pressing:
		_on_motion((event as InputEventMouseMotion).position)


func _on_press(mb: InputEventMouseButton) -> void:
	if not _screen_rect().has_point(mb.position):
		return
	if _flinging:
		# 按住正在滑的列表 = 停下来，这一下不算点击（和手机系统列表一致）。
		_flinging = false
		set_process(false)
		_gesture_dragged = true
		# 视口处理完这次按下（按钮进入按下状态）之后再取消，按钮就不会在松手时触发。
		scroll.propagate_notification.call_deferred(Control.NOTIFICATION_SCROLL_BEGIN)
	_pressing = true
	_dragging = false
	_gave_up = false
	_press_pos = mb.position
	_last_pos = mb.position
	_pos = _bar().value
	_samples.clear()
	_sample(mb.position)


func _on_motion(pos: Vector2) -> void:
	if not _dragging:
		var moved := pos - _press_pos
		if _gave_up or _owner != null:
			if moved.length() > DEADZONE:
				_gesture_dragged = true
			return
		var along := absf(_axis(moved))
		var across := absf(_cross(moved))
		if maxf(along, across) <= DEADZONE:
			return
		_gesture_dragged = true
		if across > along or max_scroll() <= 0.0 or not _hit_ok():
			_gave_up = true  # 方向不对（让外层接）、内容没超出、或者上面盖着别的界面
			return
		_owner = self
		_dragging = true
		drag_count += 1
		frame_ms.clear()
		_last_pos = pos
		_pos = _bar().value
		# 取消这次按下在按钮上的点击（BaseButton 收到 SCROLL_BEGIN 会放弃 press_attempt）。
		scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		scroll.scroll_started.emit()
		set_process(true)
	var step := _axis(pos - _last_pos)
	_last_pos = pos
	_sample(pos)
	_set_pos(_pos - step)
	get_viewport().set_input_as_handled()


func _on_release(pos: Vector2) -> void:
	if not _pressing:
		return
	_pressing = false
	if not _dragging:
		return
	_dragging = false
	if _owner == self:
		_owner = null
	_sample(pos)
	_velocity = _release_velocity()
	scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)
	scroll.scroll_ended.emit()
	_flinging = absf(_velocity) > MIN_FLING
	set_process(_flinging)


func _on_wheel(mb: InputEventMouseButton) -> void:
	if not _screen_rect().has_point(mb.position) or max_scroll() <= 0.0:
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and not _related(hovered):
		return
	var sign := -1.0 if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1.0
	var horizontal_wheel := mb.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT] or mb.shift_pressed
	if horizontal_wheel == vertical():
		return
	_flinging = false
	_pos = _bar().value
	_set_pos(_pos + sign * WHEEL_STEP * maxf(mb.factor, 1.0))
	get_viewport().set_input_as_handled()


## 拖动是不是落在这个列表上（不是盖在上面的弹窗 / 提示）。
func _hit_ok() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered == null or _related(hovered)


func _related(node: Control) -> bool:
	return node == scroll or scroll.is_ancestor_of(node) or node.is_ancestor_of(scroll)


func _sample(pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	_samples.append(Vector3(now, pos.x, pos.y))
	while _samples.size() > 2 and now - int(_samples[0].x) > SAMPLE_MS:
		_samples.remove_at(0)


## 松手速度（内容滚动方向，像素/秒）。
func _release_velocity() -> float:
	if _samples.size() < 2:
		return 0.0
	var now := Time.get_ticks_msec()
	var last: Vector3 = _samples[_samples.size() - 1]
	var first: Vector3 = _samples[0]
	# 最后一次移动之后手指停住太久 → 不滑。
	var last_move := last
	for i in range(_samples.size() - 1, 0, -1):
		if not Vector2(_samples[i].y, _samples[i].z).is_equal_approx(Vector2(_samples[i - 1].y, _samples[i - 1].z)):
			last_move = _samples[i]
			break
	if now - int(last_move.x) > STALE_MS:
		return 0.0
	var dt := maxf(float(last.x - first.x), 16.0) / 1000.0
	var moved := _axis(Vector2(last.y - first.y, last.z - first.z))
	return clampf(-moved / dt, -MAX_FLING, MAX_FLING)


func _set_pos(value: float) -> void:
	_pos = clampf(value, 0.0, max_scroll())
	_bar().value = _pos


func _process(delta: float) -> void:
	frame_ms.append(delta * 1000.0)
	if _dragging:
		return
	if not _flinging:
		set_process(false)
		return
	var before := _pos
	_set_pos(_pos + _velocity * delta)
	_velocity *= exp(-FRICTION * delta)
	if absf(_velocity) < MIN_FLING or is_equal_approx(before, _pos):
		_flinging = false
		set_process(false)


func _stop() -> void:
	_pressing = false
	_dragging = false
	_flinging = false
	if _owner == self:
		_owner = null
	set_process(false)


## 测试 / 外部：直接滚到某处（停掉惯性）。
func jump_to(value: float) -> void:
	_flinging = false
	_set_pos(value)
