extends Control
## 迷雾秘境地图定妆换皮验收 4 图（本机 MOCK，不连 tip / 不打 APK）。
##   HOME=/tmp/fogcap XIUXIAN_UPDATE_CHECK=0 \
##   xvfb-run -a /path/to/Godot --path game --rendering-driver opengl3 \
##     --resolution 1080x2340 res://scenes/dev/capture_fog_reskin.tscn -- /out/dir

const W := 1080
const H := 2340

var _out := "/tmp/fog_reskin_shots"
var _map: Control

func _ready() -> void:
	OS.set_environment("XIUXIAN_UPDATE_CHECK", "0")
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else _out
	DirAccess.make_dir_recursive_absolute(_out)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(W, H)
	set_deferred("size", Vector2(W, H))
	DisplayServer.window_set_size(Vector2i(W, H))

	var bg := ColorRect.new()
	bg.color = Color("CDEFEA")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var map_script: Script = load("res://scripts/ui/pages/fog_map_page.gd")
	if map_script == null:
		printerr("FOG_RESKIN MISSING fog_map_page.gd")
		get_tree().quit(1)
		return
	_map = (map_script as GDScript).new() as Control
	_map.name = "FogMapPage"
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.set_deferred("size", Vector2(W, H))
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame
	print("FOG_RESKIN page ready kids=", _map.get_child_count())
	await _settle(12)
	await _run()
	print("FOG_RESKIN capture done out=", _out)
	get_tree().quit()


func _run() -> void:
	# 1 刚进大雾（对照 B1）
	_map.call("bind_fog", {"fog": _payload_initial()})
	await _settle(30)
	await _shot("01_b1_just_entered.png")

	# 2 探索中含物件（对照 B2）
	_map.call("bind_fog", {"fog": _payload_revealed()})
	await _settle(30)
	await _shot("02_b2_exploring_objects.png")

	# 3 点怪确认气泡（对照 B4）— 邻格点怪
	_map.call("bind_fog", {"fog": _payload_at_slime()})
	await _settle(20)
	# 直接弹出确认（绕过点击，稳定验收）
	var confirm: PanelContainer = _map.get_node_or_null("FogConfirm")
	var label: Label = null
	if confirm:
		label = confirm.find_child("FogConfirm", true, false) as Label
		# label is named via _confirm_label without node name override — find by walking
		for c in _find_labels(confirm):
			if "遭遇" in c.text or c.text.is_empty():
				pass
		# set via page internals
	_map.set("_confirm_obj", {"id": "m_slime", "kind": "monster", "name": "浊气小妖", "x": 2, "y": 8})
	var cl: Label = _map.get("_confirm_label") as Label
	if cl:
		cl.text = "遭遇「浊气小妖」，确认进入异空间开战？"
	if confirm:
		confirm.visible = true
	await _settle(24)
	await _shot("03_b4_monster_confirm.png")
	if confirm:
		confirm.visible = false

	# 4 游历用尽 + 顶栏双收集（对照 B3）
	_map.call("bind_fog", {"fog": _payload_travel_empty()})
	await _settle(30)
	await _shot("04_b3_travel_empty.png")


func _find_labels(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_labels(c))
	return out


func _blocks() -> Array:
	return [
		{"x": 0, "y": 2}, {"x": 0, "y": 3}, {"x": 0, "y": 4}, {"x": 0, "y": 5},
		{"x": 1, "y": 3}, {"x": 1, "y": 4},
		{"x": 2, "y": 0}, {"x": 3, "y": 0}, {"x": 5, "y": 0}, {"x": 6, "y": 0},
		{"x": 2, "y": 5}, {"x": 5, "y": 4},
		{"x": 6, "y": 6}, {"x": 6, "y": 8}, {"x": 7, "y": 5}, {"x": 7, "y": 6}, {"x": 7, "y": 7},
	]


func _base_objects(opened: Dictionary = {}, defeated: Dictionary = {}, done: Dictionary = {}) -> Array:
	return [
		{"id": "m_slime", "kind": "monster", "x": 2, "y": 8, "name": "浊气小妖", "defeated": bool(defeated.get("m_slime", false))},
		{"id": "m_wolf", "kind": "monster", "x": 5, "y": 6, "name": "影狼", "defeated": bool(defeated.get("m_wolf", false))},
		{"id": "m_guard", "kind": "monster", "x": 4, "y": 1, "name": "谷口护卫", "defeated": bool(defeated.get("m_guard", false))},
		{"id": "c_near", "kind": "chest", "x": 4, "y": 9, "opened": bool(opened.get("c_near", false))},
		{"id": "c_mid", "kind": "chest", "x": 1, "y": 6, "opened": bool(opened.get("c_mid", false))},
		{"id": "c_high", "kind": "chest", "x": 6, "y": 3, "opened": bool(opened.get("c_high", false))},
		{
			"id": "e_herb", "kind": "event", "x": 3, "y": 4, "title": "仙草争执",
			"done": bool(done.get("e_herb", false)),
			"options": [
				{"id": "A", "label": "上前理论", "effect": "battle"},
				{"id": "B", "label": "转身离开", "effect": "none"},
			],
		},
	]


func _reveal_union(centers: Array, radius: int = 1) -> Array:
	var set := {}
	for c in centers:
		var cx := int(c[0])
		var cy := int(c[1])
		for y in range(12):
			for x in range(8):
				if absi(x - cx) + absi(y - cy) <= radius:
					set["%d,%d" % [x, y]] = true
	return set.keys()


func _payload_initial() -> Dictionary:
	return {
		"mapId": "fog_wenxin_valley",
		"displayName": "问心谷",
		"rows": 12, "cols": 8,
		"pos": {"x": 3, "y": 10},
		"revealed": _reveal_union([[3, 10]], 1),
		"blocks": _blocks(),
		"objects": _base_objects(),
		"travelPoints": 20, "travelPointsMax": 20,
		"collect": {"chestsOpened": 0, "chestsTotal": 3, "monstersDefeated": 0, "monstersTotal": 3},
	}


func _payload_revealed() -> Dictionary:
	var path := [
		[3, 10], [3, 9], [4, 9], [4, 8], [3, 8], [2, 8], [2, 7], [1, 7], [1, 6],
		[3, 7], [3, 6], [4, 6], [5, 6], [3, 5], [3, 4],
	]
	return {
		"mapId": "fog_wenxin_valley",
		"displayName": "问心谷",
		"rows": 12, "cols": 8,
		"pos": {"x": 3, "y": 6},
		"revealed": _reveal_union(path, 1),
		"blocks": _blocks(),
		"objects": _base_objects({"c_near": true}, {}, {}),
		"travelPoints": 12, "travelPointsMax": 20,
		"collect": {"chestsOpened": 1, "chestsTotal": 3, "monstersDefeated": 0, "monstersTotal": 3},
	}


func _payload_at_slime() -> Dictionary:
	var path := [
		[3, 10], [3, 9], [4, 9], [4, 8], [3, 8], [2, 8], [2, 7],
	]
	return {
		"mapId": "fog_wenxin_valley",
		"displayName": "问心谷",
		"rows": 12, "cols": 8,
		"pos": {"x": 2, "y": 7},
		"revealed": _reveal_union(path, 1),
		"blocks": _blocks(),
		"objects": _base_objects(),
		"travelPoints": 14, "travelPointsMax": 20,
		"collect": {"chestsOpened": 0, "chestsTotal": 3, "monstersDefeated": 0, "monstersTotal": 3},
	}


func _payload_travel_empty() -> Dictionary:
	var path := [
		[3, 10], [3, 9], [4, 9], [4, 8], [3, 8], [2, 8], [2, 7], [1, 7], [1, 6],
		[3, 7], [3, 6], [4, 6], [5, 6], [3, 5], [3, 4], [4, 4], [4, 3], [5, 3], [6, 3],
	]
	return {
		"mapId": "fog_wenxin_valley",
		"displayName": "问心谷",
		"rows": 12, "cols": 8,
		"pos": {"x": 3, "y": 6},
		"revealed": _reveal_union(path, 1),
		"blocks": _blocks(),
		"objects": _base_objects({"c_near": true, "c_mid": true}, {"m_slime": true}, {}),
		"travelPoints": 0, "travelPointsMax": 20,
		"collect": {"chestsOpened": 2, "chestsTotal": 3, "monstersDefeated": 1, "monstersTotal": 3},
	}


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [_out, name]
	img.save_png(path)
	var sz := FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
	print("shot ", name, " size=", img.get_size(), " bytes=", sz)
