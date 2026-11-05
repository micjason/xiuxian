extends Control
## 迷雾秘境 P0 灰盒验收 4 图（本机 MOCK，不连 tip）。
## 用法：
##   HOME=/tmp/fogcap XIUXIAN_UPDATE_CHECK=0 \
##   xvfb-run -a Godot --path game --rendering-driver opengl3 --resolution 1080x2340 \
##     res://scenes/dev/capture_fog_p0.tscn -- /out/dir

const W := 1080
const H := 2340

var _out := "/tmp/fog_p0_shots"
var _map: Control
var _battle: Control

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
	bg.name = "Bg"
	bg.color = Color(0.12, 0.14, 0.18, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var map_script: Script = load("res://scripts/ui/pages/fog_map_page.gd")
	var battle_script: Script = load("res://scripts/ui/pages/fog_battle_page.gd")
	if map_script == null or battle_script == null:
		printerr("FOG_P0 MISSING page scripts map=", map_script, " battle=", battle_script)
		get_tree().quit(1)
		return

	_map = (map_script as GDScript).new() as Control
	_map.name = "FogMapPage"
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.set_deferred("size", Vector2(W, H))
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame

	_battle = (battle_script as GDScript).new() as Control
	_battle.name = "FogBattlePage"
	_battle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle.set_deferred("size", Vector2(W, H))
	_battle.visible = false
	add_child(_battle)
	await get_tree().process_frame
	await get_tree().process_frame

	print("FOG_P0 pages ready map_kids=", _map.get_child_count(), " battle_kids=", _battle.get_child_count())
	await _settle(12)
	await _run()
	print("FOG_P0 capture done out=", _out)
	get_tree().quit()


func _run() -> void:
	_show_map()
	_map.call("bind_fog", {"fog": _payload_initial()})
	await _settle(24)
	await _shot("01_unrevealed_travel.png")

	_map.call("bind_fog", {"fog": _payload_revealed()})
	await _settle(24)
	await _shot("02_revealed_objects.png")

	_show_battle()
	_battle.call("open_battle", _battle_payload())
	_battle.call("_toggle_speed")
	for i in 90:
		await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	await _shot("03_fog_battle.png")

	_show_map()
	_map.call("bind_fog", {"fog": _payload_after_battle()})
	await _settle(24)
	await _shot("04_back_to_map.png")


func _show_map() -> void:
	_map.visible = true
	_battle.visible = false


func _show_battle() -> void:
	_map.visible = false
	_battle.visible = true


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
		"rows": 12,
		"cols": 8,
		"pos": {"x": 3, "y": 10},
		"revealed": _reveal_union([[3, 10]], 1),
		"blocks": _blocks(),
		"objects": _base_objects(),
		"travelPoints": 20,
		"travelPointsMax": 20,
		"travelDay": "2026-11-05",
		"collect": {"chestsOpened": 0, "chestsTotal": 3, "monstersDefeated": 0, "monstersTotal": 3},
	}


func _payload_revealed() -> Dictionary:
	var path := [
		[3, 10], [3, 9], [4, 9], [4, 8], [3, 8], [2, 8], [2, 7], [1, 7], [1, 6],
		[3, 7], [3, 6], [4, 6], [5, 6],
	]
	return {
		"mapId": "fog_wenxin_valley",
		"displayName": "问心谷",
		"rows": 12,
		"cols": 8,
		"pos": {"x": 2, "y": 8},
		"revealed": _reveal_union(path, 1),
		"blocks": _blocks(),
		"objects": _base_objects(),
		"travelPoints": 12,
		"travelPointsMax": 20,
		"travelDay": "2026-11-05",
		"collect": {"chestsOpened": 0, "chestsTotal": 3, "monstersDefeated": 0, "monstersTotal": 3},
	}


func _payload_after_battle() -> Dictionary:
	var path := [
		[3, 10], [3, 9], [4, 9], [4, 8], [3, 8], [2, 8], [2, 7], [1, 7], [1, 6],
		[3, 7], [3, 6], [4, 6], [5, 6],
	]
	return {
		"mapId": "fog_wenxin_valley",
		"displayName": "问心谷",
		"rows": 12,
		"cols": 8,
		"pos": {"x": 2, "y": 8},
		"revealed": _reveal_union(path, 1),
		"blocks": _blocks(),
		"objects": _base_objects({"c_near": true}, {"m_slime": true}, {}),
		"travelPoints": 12,
		"travelPointsMax": 20,
		"travelDay": "2026-11-05",
		"collect": {"chestsOpened": 1, "chestsTotal": 3, "monstersDefeated": 1, "monstersTotal": 3},
	}


func _battle_payload() -> Dictionary:
	return {
		"win": true,
		"monster": {"name": "浊气小妖", "hp": 30},
		"player": {"hp": 120},
		"log": [
			{"t": 0.0, "side": "player", "damage": 18, "targetHpAfter": 12},
			{"t": 0.8, "side": "enemy", "damage": 6, "targetHpAfter": 114},
			{"t": 1.6, "side": "player", "damage": 12, "targetHpAfter": 0},
		],
		"gained": [{"itemSlug": "herb_lingcao", "displayName": "灵草", "quantity": 1}],
		"fog": _payload_after_battle(),
	}


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [_out, name]
	img.save_png(path)
	var sz := FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
	print("shot ", name, " size=", img.get_size(), " bytes=", sz)
