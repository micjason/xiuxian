class_name ItemFlags
extends RefCounted
## 客户端本地的物品标记：已看过（用来显示"新"角标）。保存在本机（user://item_flags.json）。

var path := "user://item_flags.json"
var seen: Dictionary = {}
var _loaded_once := false


static func at(file_path: String) -> ItemFlags:
	var flags := ItemFlags.new()
	flags.path = file_path
	flags.load_file()
	return flags


func load_file() -> void:
	seen = {}
	_loaded_once = false
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_loaded_once = true
	for id in (parsed as Dictionary).get("seen", []):
		seen[str(id)] = true


func save_file() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"seen": seen.keys()}))


## 第一次启动没有记录时，把当前所有物品都当作已看过，避免满屏"新"。
func adopt_if_first_run(ids: Array) -> void:
	if _loaded_once or not seen.is_empty():
		return
	for id in ids:
		seen[str(id)] = true
	_loaded_once = true
	save_file()


func mark_seen(ids: Array) -> void:
	var changed := false
	for id in ids:
		if not seen.has(str(id)):
			seen[str(id)] = true
			changed = true
	if changed:
		save_file()


## 清理服务器上已经不存在的物品，避免文件越来越大。
func prune(existing_ids: Array) -> void:
	var keep := {}
	for id in existing_ids:
		keep[str(id)] = true
	var changed := false
	for id in seen.keys():
		if not keep.has(id):
			seen.erase(id)
			changed = true
	if changed:
		save_file()
