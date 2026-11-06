class_name FogLevelTiles
extends RefCounted
## 问心谷地块类型（只读，真源 = fog_art_delivery meta/level_objects.json）。
## 服务端 DTO 只下发 blocks；贴图区分 grass/path/pond/rock 用本表。

const LEVEL_PATH := "res://assets/art/fog/level_objects.json"

static var _tiles: Array = []
static var _loaded := false

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(LEVEL_PATH):
		push_warning("FogLevelTiles missing %s" % LEVEL_PATH)
		return
	var raw := FileAccess.get_file_as_string(LEVEL_PATH)
	var data: Variant = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var t: Variant = (data as Dictionary).get("tiles", [])
	if typeof(t) == TYPE_ARRAY:
		_tiles = t as Array


static func tile_at(x: int, y: int) -> String:
	ensure_loaded()
	if y < 0 or y >= _tiles.size():
		return "grass"
	var row: Variant = _tiles[y]
	if typeof(row) != TYPE_ARRAY:
		return "grass"
	var cols := row as Array
	if x < 0 or x >= cols.size():
		return "grass"
	return str(cols[x])


static func is_water(x: int, y: int) -> bool:
	return tile_at(x, y) == "water"


static func is_rock(x: int, y: int) -> bool:
	return tile_at(x, y) == "rock"
