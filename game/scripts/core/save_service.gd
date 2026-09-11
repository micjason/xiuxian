class_name SaveService
extends RefCounted

const SAVE_SCHEMA_VERSION := 3
const PREVIOUS_SCHEMA_VERSION := 2
const LEGACY_SCHEMA_VERSION := 1
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

	var payload := _payload_from_state(state)
	var envelope := {
		"schema_version": SAVE_SCHEMA_VERSION,
		"app_version": app_version,
		"content_version": content_version,
		"saved_at_unix": saved_at_unix,
		"payload": payload,
		"checksum": _checksum_payload(payload),
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


func export_text() -> String:
	if FileAccess.file_exists(save_path):
		return FileAccess.get_file_as_string(save_path)
	return ""


func _load_from_path(path: String) -> CultivationState:
	if not FileAccess.file_exists(path):
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	if typeof(parser.data) != TYPE_DICTIONARY:
		return null

	var envelope: Dictionary = parser.data
	var schema := int(envelope.get("schema_version", 0))
	var payload: Variant = envelope.get("payload", {})
	if typeof(payload) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = payload
	if schema == LEGACY_SCHEMA_VERSION:
		return _state_from_legacy(envelope, data)
	if schema == PREVIOUS_SCHEMA_VERSION:
		if str(envelope.get("checksum", "")) != _checksum_payload_v2(data):
			return null
		return _state_from_payload(data)
	if schema != SAVE_SCHEMA_VERSION:
		return null
	if str(envelope.get("checksum", "")) != _checksum_payload(data):
		return null
	return _state_from_payload(data)


func _state_from_legacy(envelope: Dictionary, data: Dictionary) -> CultivationState:
	var state := CultivationState.new()
	state.cultivation = snappedf(float(data.get("cultivation", -1.0)), 0.000001)
	state.realm_id = str(data.get("realm_id", "")).strip_edges()
	state.last_settled_unix = int(data.get("last_settled_unix", -1))
	if state.cultivation < 0.0 or state.realm_id.is_empty() or state.last_settled_unix < 0:
		return null
	if str(envelope.get("checksum", "")) != _legacy_checksum(
		state.cultivation,
		state.realm_id,
		state.last_settled_unix
	):
		return null
	return state


func _state_from_payload(data: Dictionary) -> CultivationState:
	var state := CultivationState.new()
	state.cultivation = snappedf(float(data.get("cultivation", -1.0)), 0.000001)
	state.realm_id = str(data.get("realm_id", "")).strip_edges()
	state.last_settled_unix = int(data.get("last_settled_unix", -1))
	if state.cultivation < 0.0 or state.realm_id.is_empty() or state.last_settled_unix < 0:
		return null
	state.inventory_capacity = maxi(int(data.get("inventory_capacity", CultivationState.DEFAULT_CAPACITY)), 8)
	state.next_item_uid = maxi(int(data.get("next_item_uid", 0)), 0)
	state.current_stage_id = str(data.get("current_stage_id", CultivationState.DEFAULT_STAGE)).strip_edges()
	state.loot_seed = maxi(int(data.get("loot_seed", 1)), 1)
	state.combat_remainder = maxf(float(data.get("combat_remainder", 0.0)), 0.0)
	state.equipped = EquipmentLoadout.from_dictionary(data.get("equipped", {}))
	state.settings = GameSettings.from_dictionary(data.get("settings", {}))
	state.learned_skill_ids = _string_array(data.get("learned_skill_ids", []))
	state.skill_ranks = _int_dictionary(data.get("skill_ranks", {}))
	state.unlocked_stage_ids = _string_array(data.get("unlocked_stage_ids", [CultivationState.DEFAULT_STAGE]))
	state.battle_log = _string_array(data.get("battle_log", []))
	state.stage_layers = _int_dictionary(data.get("stage_layers", {}))
	state.layer_kills = _int_dictionary(data.get("layer_kills", {}))
	state.qi_pill_until = maxi(int(data.get("qi_pill_until", 0)), 0)
	state.body_pill_until = maxi(int(data.get("body_pill_until", 0)), 0)
	var raw_items: Variant = data.get("inventory", [])
	if typeof(raw_items) == TYPE_ARRAY:
		for entry in raw_items:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var stack := ItemStack.from_dictionary(entry)
			if stack != null:
				state.inventory.append(stack)
	if state.unlocked_stage_ids.is_empty():
		state.unlocked_stage_ids = PackedStringArray([CultivationState.DEFAULT_STAGE])
	if state.current_stage_id.is_empty():
		state.current_stage_id = CultivationState.DEFAULT_STAGE
	return state


func _payload_from_state(state: CultivationState) -> Dictionary:
	var items: Array = []
	for stack in state.inventory:
		items.append(stack.to_dictionary())
	return {
		"cultivation": state.cultivation,
		"realm_id": state.realm_id,
		"last_settled_unix": state.last_settled_unix,
		"inventory": items,
		"inventory_capacity": state.inventory_capacity,
		"next_item_uid": state.next_item_uid,
		"equipped": state.equipped.to_dictionary(),
		"learned_skill_ids": Array(state.learned_skill_ids),
		"skill_ranks": state.skill_ranks.duplicate(),
		"current_stage_id": state.current_stage_id,
		"unlocked_stage_ids": Array(state.unlocked_stage_ids),
		"battle_log": Array(state.battle_log),
		"loot_seed": state.loot_seed,
		"combat_remainder": snappedf(state.combat_remainder, 0.000001),
		"settings": state.settings.to_dictionary(),
		"stage_layers": state.stage_layers.duplicate(),
		"layer_kills": state.layer_kills.duplicate(),
		"qi_pill_until": state.qi_pill_until,
		"body_pill_until": state.body_pill_until,
	}


func _checksum_payload(payload: Dictionary) -> String:
	var inventory: Array = payload.get("inventory", [])
	var item_parts: PackedStringArray = PackedStringArray()
	if typeof(inventory) == TYPE_ARRAY:
		var copies: Array = inventory.duplicate()
		copies.sort_custom(func(left: Variant, right: Variant) -> bool:
			return int(left.get("uid", 0)) < int(right.get("uid", 0))
		)
		for entry in copies:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			item_parts.append("%d:%s:%d:%s:%d:%s" % [
				int(entry.get("uid", 0)),
				str(entry.get("item_id", "")),
				int(entry.get("count", 0)),
				str(entry.get("locked", false)),
				int(entry.get("merge_level", 0)),
				str(entry.get("tempered", false)),
			])
	var equipped: Dictionary = payload.get("equipped", {})
	var settings: Dictionary = payload.get("settings", {})
	var text := "|".join(PackedStringArray([
		"%.6f" % float(payload.get("cultivation", 0.0)),
		str(payload.get("realm_id", "")),
		str(int(payload.get("last_settled_unix", 0))),
		str(int(payload.get("inventory_capacity", 0))),
		str(int(payload.get("next_item_uid", 0))),
		str(payload.get("current_stage_id", "")),
		str(int(payload.get("loot_seed", 0))),
		"%.6f" % float(payload.get("combat_remainder", 0.0)),
		",".join(_string_array(payload.get("learned_skill_ids", []))),
		",".join(_string_array(payload.get("unlocked_stage_ids", []))),
		str(int(equipped.get("weapon", 0))),
		str(int(equipped.get("helmet", 0))),
		str(int(equipped.get("clothes", 0))),
		str(int(equipped.get("shoes", 0))),
		str(int(equipped.get("accessory", 0))),
		str(settings.get("battle_log_enabled", true)),
		str(settings.get("bag_full_policy", "")),
		"%.2f" % float(settings.get("sound_volume", 1.0)),
		";".join(item_parts),
		_dict_fingerprint(payload.get("skill_ranks", {})),
		_dict_fingerprint(payload.get("stage_layers", {})),
		_dict_fingerprint(payload.get("layer_kills", {})),
		str(int(payload.get("qi_pill_until", 0))),
		str(int(payload.get("body_pill_until", 0))),
	]))
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()


func _checksum_payload_v2(payload: Dictionary) -> String:
	var inventory: Array = payload.get("inventory", [])
	var item_parts: PackedStringArray = PackedStringArray()
	if typeof(inventory) == TYPE_ARRAY:
		var copies: Array = inventory.duplicate()
		copies.sort_custom(func(left: Variant, right: Variant) -> bool:
			return int(left.get("uid", 0)) < int(right.get("uid", 0))
		)
		for entry in copies:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			item_parts.append("%d:%s:%d:%s" % [
				int(entry.get("uid", 0)),
				str(entry.get("item_id", "")),
				int(entry.get("count", 0)),
				str(entry.get("locked", false)),
			])
	var equipped: Dictionary = payload.get("equipped", {})
	var settings: Dictionary = payload.get("settings", {})
	var text := "|".join(PackedStringArray([
		"%.6f" % float(payload.get("cultivation", 0.0)),
		str(payload.get("realm_id", "")),
		str(int(payload.get("last_settled_unix", 0))),
		str(int(payload.get("inventory_capacity", 0))),
		str(int(payload.get("next_item_uid", 0))),
		str(payload.get("current_stage_id", "")),
		str(int(payload.get("loot_seed", 0))),
		"%.6f" % float(payload.get("combat_remainder", 0.0)),
		",".join(_string_array(payload.get("learned_skill_ids", []))),
		",".join(_string_array(payload.get("unlocked_stage_ids", []))),
		str(int(equipped.get("weapon", 0))),
		str(int(equipped.get("helmet", 0))),
		str(int(equipped.get("clothes", 0))),
		str(int(equipped.get("shoes", 0))),
		str(int(equipped.get("accessory", 0))),
		str(settings.get("battle_log_enabled", true)),
		str(settings.get("bag_full_policy", "")),
		"%.2f" % float(settings.get("sound_volume", 1.0)),
		";".join(item_parts),
	]))
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()


func _int_dictionary(raw: Variant) -> Dictionary:
	var values := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return values
	for key in raw.keys():
		values[str(key)] = int(raw[key])
	return values


func _dict_fingerprint(raw: Variant) -> String:
	var values := _int_dictionary(raw)
	var keys: Array = values.keys()
	keys.sort()
	var parts := PackedStringArray()
	for key in keys:
		parts.append("%s:%d" % [str(key), int(values[key])])
	return ",".join(parts)


func _legacy_checksum(cultivation: float, realm_id: String, last_settled_unix: int) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(("%.6f|%s|%d" % [cultivation, realm_id, last_settled_unix]).to_utf8_buffer())
	return context.finish().hex_encode()


func _string_array(raw: Variant) -> PackedStringArray:
	var values := PackedStringArray()
	if typeof(raw) != TYPE_ARRAY:
		return values
	for item in raw:
		var text := str(item).strip_edges()
		if not text.is_empty():
			values.append(text)
	return values


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
