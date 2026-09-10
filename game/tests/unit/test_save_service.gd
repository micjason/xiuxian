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
	assert_eq(int(saved.get("schema_version", 0)), 2)
	assert_eq(again.current_stage_id, "grove")
