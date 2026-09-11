extends GutTest


func _paths() -> Dictionary:
	var stamp := str(Time.get_ticks_usec())
	return {
		"save": "user://tests/cultivation_%s.json" % stamp,
		"backup": "user://tests/cultivation_%s.bak.json" % stamp,
		"temp": "user://tests/cultivation_%s.json.tmp" % stamp,
	}


func _service() -> SaveService:
	var paths: Dictionary = _paths()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	return SaveService.new(paths.save, paths.backup, paths.temp)


func _state(cultivation: float = 12.5) -> CultivationState:
	var state := CultivationState.new()
	state.cultivation = cultivation
	state.realm_id = "qi_early"
	state.last_settled_unix = 1_700_000_000
	return state


func test_round_trip_preserves_payload() -> void:
	var service := _service()
	var original := _state()
	assert_true(service.save_state(original, "0.1.2", "0.1.2", 1_700_000_010))
	var loaded := service.load_state()
	assert_not_null(loaded)
	assert_eq(loaded.realm_id, "qi_early")
	assert_almost_eq(loaded.cultivation, 12.5, 0.0001)
	assert_eq(loaded.last_settled_unix, 1_700_000_000)


func test_corrupt_save_falls_back_to_backup() -> void:
	var service := _service()
	assert_true(service.save_state(_state(8.0), "0.1.2", "0.1.2", 10))
	assert_true(service.save_state(_state(20.0), "0.1.2", "0.1.2", 11))
	var broken := FileAccess.open(service.save_path, FileAccess.WRITE)
	broken.store_string("{broken")
	broken.close()
	var loaded := service.load_state()
	assert_not_null(loaded)
	assert_almost_eq(loaded.cultivation, 8.0, 0.0001)


func test_tampered_checksum_is_rejected() -> void:
	var service := _service()
	assert_true(service.save_state(_state(3.0), "0.1.2", "0.1.2", 12))
	var file := FileAccess.open(service.save_path, FileAccess.READ)
	var raw: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	raw["payload"]["cultivation"] = 9999.0
	var writer := FileAccess.open(service.save_path, FileAccess.WRITE)
	writer.store_string(JSON.stringify(raw))
	writer.close()
	assert_null(service.load_state())


func test_legacy_v1_save_migrates_cultivation_and_starts_grove() -> void:
	var service := _service()
	var state := _state(12.5)
	var checksum_source := "%.6f|%s|%d" % [state.cultivation, state.realm_id, state.last_settled_unix]
	var context := HashingContext.new()
	assert_eq(context.start(HashingContext.HASH_SHA256), OK)
	context.update(checksum_source.to_utf8_buffer())
	var envelope := {
		"schema_version": 1,
		"app_version": "0.1.5",
		"content_version": "0.1.5",
		"saved_at_unix": 1_700_000_010,
		"payload": {
			"cultivation": state.cultivation,
			"realm_id": state.realm_id,
			"last_settled_unix": state.last_settled_unix,
		},
		"checksum": context.finish().hex_encode(),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(service.save_path.get_base_dir()))
	var writer := FileAccess.open(service.save_path, FileAccess.WRITE)
	writer.store_string(JSON.stringify(envelope))
	writer.close()
	var loaded := service.load_state()
	assert_not_null(loaded)
	assert_eq(loaded.realm_id, "qi_early")
	assert_almost_eq(loaded.cultivation, 12.5, 0.0001)
	assert_eq(loaded.current_stage_id, "grove")
	assert_eq(loaded.inventory.size(), 0)
	assert_true(service.save_state(loaded, "0.1.6", "0.1.6", 1_700_000_020))
	var again := service.load_state()
	assert_not_null(again)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(service.save_path))
	assert_eq(int(saved.get("schema_version", 0)), 3)
	assert_eq(again.current_stage_id, "grove")


func test_schema_v2_save_still_loads() -> void:
	var service := _service()
	var payload := {
		"cultivation": 12.5,
		"realm_id": "qi_early",
		"last_settled_unix": 1_700_000_000,
		"inventory": [{
			"uid": 3,
			"item_id": "sword_0",
			"count": 1,
			"locked": false,
		}],
		"inventory_capacity": 36,
		"next_item_uid": 3,
		"equipped": {
			"weapon": 0,
			"helmet": 0,
			"clothes": 0,
			"shoes": 0,
			"accessory": 0,
		},
		"learned_skill_ids": ["tuna"],
		"current_stage_id": "grove",
		"unlocked_stage_ids": ["grove"],
		"battle_log": [],
		"loot_seed": 1,
		"combat_remainder": 0.0,
		"settings": {
			"battle_log_enabled": true,
			"bag_full_policy": "skip",
			"sound_volume": 1.0,
		},
	}
	var envelope := {
		"schema_version": 2,
		"app_version": "0.1.13",
		"content_version": "0.1.13",
		"saved_at_unix": 1_700_000_010,
		"payload": payload,
		"checksum": _v2_checksum(payload),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(service.save_path.get_base_dir()))
	var writer := FileAccess.open(service.save_path, FileAccess.WRITE)
	writer.store_string(JSON.stringify(envelope))
	writer.close()
	var loaded := service.load_state()
	assert_not_null(loaded)
	assert_eq(loaded.inventory.size(), 1)
	assert_eq(loaded.inventory[0].merge_level, 0)
	assert_false(loaded.inventory[0].tempered)
	assert_eq(loaded.skill_rank_of("tuna"), 1)
	assert_eq(loaded.current_layer(), StageLayer.OUTER)
	assert_eq(loaded.qi_pill_until, 0)


func test_schema_v3_round_trip_keeps_merge_and_layers() -> void:
	var service := _service()
	var state := _state(20.0)
	var stack := ItemStack.new()
	stack.uid = 8
	stack.item_id = "sword_0"
	stack.merge_level = 3
	stack.tempered = true
	state.inventory.append(stack)
	state.next_item_uid = 8
	state.set_skill_rank("tuna", 2)
	state.set_layer("grove", StageLayer.INNER)
	state.add_kills("grove", StageLayer.OUTER, 80)
	state.qi_pill_until = 1_700_000_600
	assert_true(service.save_state(state, "0.1.14", "0.1.14", 1_700_000_020))
	var loaded := service.load_state()
	assert_not_null(loaded)
	assert_eq(loaded.inventory[0].merge_level, 3)
	assert_true(loaded.inventory[0].tempered)
	assert_eq(loaded.skill_rank_of("tuna"), 2)
	assert_eq(loaded.layer_of("grove"), StageLayer.INNER)
	assert_eq(loaded.kills_of("grove", StageLayer.OUTER), 80)
	assert_eq(loaded.qi_pill_until, 1_700_000_600)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(service.save_path))
	assert_eq(int(saved.get("schema_version", 0)), 3)


func _v2_checksum(payload: Dictionary) -> String:
	var inventory: Array = payload.get("inventory", [])
	var item_parts: PackedStringArray = PackedStringArray()
	var copies: Array = inventory.duplicate()
	copies.sort_custom(func(left: Variant, right: Variant) -> bool:
		return int(left.get("uid", 0)) < int(right.get("uid", 0))
	)
	for entry in copies:
		item_parts.append("%d:%s:%d:%s" % [
			int(entry.get("uid", 0)),
			str(entry.get("item_id", "")),
			int(entry.get("count", 0)),
			str(entry.get("locked", false)),
		])
	var equipped: Dictionary = payload.get("equipped", {})
	var settings: Dictionary = payload.get("settings", {})
	var learned: PackedStringArray = PackedStringArray()
	for skill_id in payload.get("learned_skill_ids", []):
		learned.append(str(skill_id))
	var unlocked: PackedStringArray = PackedStringArray()
	for stage_id in payload.get("unlocked_stage_ids", []):
		unlocked.append(str(stage_id))
	var text := "|".join(PackedStringArray([
		"%.6f" % float(payload.get("cultivation", 0.0)),
		str(payload.get("realm_id", "")),
		str(int(payload.get("last_settled_unix", 0))),
		str(int(payload.get("inventory_capacity", 0))),
		str(int(payload.get("next_item_uid", 0))),
		str(payload.get("current_stage_id", "")),
		str(int(payload.get("loot_seed", 0))),
		"%.6f" % float(payload.get("combat_remainder", 0.0)),
		",".join(learned),
		",".join(unlocked),
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
	assert_eq(context.start(HashingContext.HASH_SHA256), OK)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()
