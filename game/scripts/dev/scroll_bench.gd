extends SceneTree
## 滚动性能测量（开发用）：演示数据启动主界面，在 历练 / 背包 上用模拟手指拖动 + 惯性，记录每帧耗时；
## 另外测一次心跳刷新（PlayScreen._render）耗时和历练页空闲帧耗时。只用引擎 API，旧版本也能跑（对比前后）。
## 用法：XIUXIAN_UI_MOCK=1 XIUXIAN_MOCK_SCENARIO=full godot --path game --rendering-driver opengl3 --resolution 1080x2340 \
##   --script res://scripts/dev/scroll_bench.gd -- <输出 json>

var _scene: Node
var _out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/scroll_bench.json"
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	for i in 20:
		await process_frame
	var offline := _scene.get("_offline_popup") as Control
	if offline != null and offline.visible and offline.has_method("claim_button"):
		(offline.call("claim_button") as BaseButton).pressed.emit()
	await create_timer(1.0).timeout
	var result := {}
	for page in ["adventure", "bag"]:
		_scene.call("_show_page", page)
		await create_timer(0.6).timeout
		result[page + "_idle"] = await _frames(60)
		var r := _scene.get("_stage_page" if page == "adventure" else "_bag_page") as Control
		var scroll := _first_scroll(r)
		var rect := scroll.get_global_rect() if scroll != null else Rect2(100, 1500, 800, 400)
		var from := rect.get_center() + Vector2(0, rect.size.y * 0.3)
		var to := rect.get_center() - Vector2(0, rect.size.y * 0.3)
		var before_v := scroll.scroll_vertical if scroll != null else -1
		result[page + "_drag"] = await _drag(from, to)
		result[page + "_scrolled_px"] = (scroll.scroll_vertical if scroll != null else -1) - before_v
		result[page + "_max_scroll"] = (scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page) if scroll != null else 0.0
		var cost: Array = []
		for i in 10:
			var t := Time.get_ticks_usec()
			_scene.call("_render", true)
			cost.append((Time.get_ticks_usec() - t) / 1000.0)
			await process_frame
		result[page + "_heartbeat_render_ms"] = _stats(cost)
	var f := FileAccess.open(_out, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "  "))
	print(JSON.stringify(result, "  "))
	quit()


func _first_scroll(node: Node) -> ScrollContainer:
	for n in node.find_children("*", "ScrollContainer", true, false):
		var s := n as ScrollContainer
		if s.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and s.is_visible_in_tree():
			return s
	return null


func _frames(count: int) -> Dictionary:
	var times: Array = []
	var last := Time.get_ticks_usec()
	for i in count:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	return _stats(times)


func _drag(from: Vector2, to: Vector2) -> Dictionary:
	var xf := root.get_final_transform()
	var times: Array = []
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = xf * from
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	var last := Time.get_ticks_usec()
	var steps := 8
	var prev := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / steps)
		var m := InputEventScreenDrag.new()
		m.position = xf * p
		m.relative = xf * p - xf * prev
		prev = p
		Input.parse_input_event(m)
		Input.flush_buffered_events()
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = xf * to
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	for i in 60:  # 惯性阶段
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	return _stats(times)


func _stats(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += float(v)
	return {"n": sorted.size(), "avg": snappedf(total / maxf(1, sorted.size()), 0.01), "p95": snappedf(float(sorted[int(sorted.size() * 0.95) - 1]) if sorted.size() > 1 else 0.0, 0.01), "max": snappedf(float(sorted[-1]) if not sorted.is_empty() else 0.0, 0.01)}
