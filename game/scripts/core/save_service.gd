class_name SaveService
extends RefCounted

const SAVE_SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://saves/cultivation.json"
const DEFAULT_BACKUP_PATH := "user://saves/cultivation.bak.json"
const DEFAULT_TEMP_PATH := "user://saves/cultivation.json.tmp"

var save_path: String
var backup_path: String
var temp_path: String


func _init(
	save_file_path: String = DEFAULT_PATH,
	backup_file_path: String = DEFAULT_BACKUP_PATH,
	temp_file_path: String = DEFAULT_TEMP_PATH
) -> void:
	save_path = save_file_path
	backup_path = backup_file_path
	temp_path = temp_file_path


func load_state() -> CultivationState:
	var loaded := _load_from_path(save_path)
	if loaded != null:
		return loaded
	return _load_from_path(backup_path)


func save_state(
	state: CultivationState,
	app_version: String,
	content_version: String,
	saved_at_unix: int
) -> bool:
	if state == null or state.realm_id.is_empty() or state.cultivation < 0.0:
		return false
	state.cultivation = snappedf(state.cultivation, 0.000001)

	var directory := save_path.get_base_dir()
	if not directory.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(directory)
		)
		if directory_error != OK:
			return false

	var envelope := {
		"schema_version": SAVE_SCHEMA_VERSION,
		"app_version": app_version,
		"content_version": content_version,
		"saved_at_unix": saved_at_unix,
		"payload": _payload_from_state(state),
		"checksum": _checksum_values(state.cultivation, state.realm_id, state.last_settled_unix),
	}
	var text := JSON.stringify(envelope)
	if not _write_text(temp_path, text):
		return false
	if _load_from_path(temp_path) == null:
		_remove_if_exists(temp_path)
		return false

	if FileAccess.file_exists(save_path):
		if not _replace_file(save_path, backup_path):
			return false
	if not _replace_file(temp_path, save_path):
		return false
	return FileAccess.file_exists(save_path)


func _load_from_path(path: String) -> CultivationState:
	if not FileAccess.file_exists(path):
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	if typeof(parser.data) != TYPE_DICTIONARY:
		return null

	var envelope: Dictionary = parser.data
	if int(envelope.get("schema_version", 0)) != SAVE_SCHEMA_VERSION:
		return null
	var payload: Variant = envelope.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = payload
	var state := CultivationState.new()
	state.cultivation = snappedf(float(data.get("cultivation", -1.0)), 0.000001)
	state.realm_id = str(data.get("realm_id", "")).strip_edges()
	state.last_settled_unix = int(data.get("last_settled_unix", -1))
	if state.cultivation < 0.0 or state.realm_id.is_empty() or state.last_settled_unix < 0:
		return null
	if str(envelope.get("checksum", "")) != _checksum_values(
		state.cultivation,
		state.realm_id,
		state.last_settled_unix
	):
		return null
	return state


func _payload_from_state(state: CultivationState) -> Dictionary:
	return {
		"cultivation": state.cultivation,
		"realm_id": state.realm_id,
		"last_settled_unix": state.last_settled_unix,
	}


func _checksum_values(cultivation: float, realm_id: String, last_settled_unix: int) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(("%.6f|%s|%d" % [cultivation, realm_id, last_settled_unix]).to_utf8_buffer())
	return context.finish().hex_encode()


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	return true


func _replace_file(from_path: String, to_path: String) -> bool:
	_remove_if_exists(to_path)
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path),
		ProjectSettings.globalize_path(to_path)
	) == OK


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
