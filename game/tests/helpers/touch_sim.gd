class_name TouchSim
extends RefCounted
## 测试用：按手机的路径模拟手指——发 InputEventScreenTouch / ScreenDrag 给 Input，
## 由 Input 按 emulate_mouse_from_touch 转成鼠标事件（真机上也是这样），再进视口。
## 坐标用画布坐标（1080×2340），这里换算成窗口坐标。


static func _win(viewport: Viewport, canvas_pos: Vector2) -> Vector2:
	return viewport.get_final_transform() * canvas_pos


static func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


static func down(viewport: Viewport, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = true
	e.position = _win(viewport, pos)
	_send(e)


static func up(viewport: Viewport, pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = false
	e.position = _win(viewport, pos)
	_send(e)


static func move(viewport: Viewport, from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = _win(viewport, to)
	e.relative = _win(viewport, to) - _win(viewport, from)
	_send(e)


## 拖一段：steps 步，每步等一帧（step_wait 秒可选，用来模拟手指速度）。release=false 时不松手。
static func drag(tree: SceneTree, viewport: Viewport, from: Vector2, to: Vector2, steps: int = 12, release: bool = true) -> void:
	down(viewport, from)
	await tree.process_frame
	var last := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / float(steps))
		move(viewport, last, p)
		last = p
		await tree.process_frame
	if release:
		up(viewport, to)
		await tree.process_frame


static func tap(tree: SceneTree, viewport: Viewport, pos: Vector2) -> void:
	down(viewport, pos)
	await tree.process_frame
	up(viewport, pos)
	await tree.process_frame


## GUT 自己的界面（输出框等）和测试节点在同一个 CanvasLayer 里、盖在上面，会挡住"手指"。
## 测试开始前让测试节点之外的控件都不接鼠标，结束后 restore_gut_gui() 还原。
static var _muted: Dictionary = {}


static func mute_gut_gui(test: Node) -> void:
	for node in test.get_tree().root.find_children("*", "Control", true, false):
		var control := node as Control
		if test.is_ancestor_of(control) or control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		_muted[control.get_instance_id()] = control.mouse_filter
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func restore_gut_gui() -> void:
	for id in _muted:
		var control := instance_from_id(id) as Control
		if control != null:
			control.mouse_filter = _muted[id]
	_muted.clear()
