extends GutTest


func _config() -> IdleConfig:
	return IdleConfig.from_json(JSON.stringify({
		"schema_version": 1,
		"offline_cap_seconds": 100,
		"realms": [
			{
				"id": "mortal",
				"display_name": "凡人",
				"order": 0,
				"gain_per_second": 1.0,
				"breakthrough_cost": 10,
				"next_id": "qi_early",
			},
			{
				"id": "qi_early",
				"display_name": "炼气初期",
				"order": 1,
				"gain_per_second": 2.0,
				"breakthrough_cost": 100,
				"next_id": "",
			},
		],
	}))


func _session(clock: TimeService, save: SaveService) -> CultivationSession:
	return CultivationSession.new(clock, save, _config(), "0.1.2")


func _save() -> SaveService:
	var stamp := str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	return SaveService.new(
		"user://tests/session_%s.json" % stamp,
		"user://tests/session_%s.bak.json" % stamp,
		"user://tests/session_%s.json.tmp" % stamp
	)


func test_first_start_is_mortal_with_zero_cultivation() -> void:
	var clock := TimeService.new()
	clock.set_unix(1_000)
	var session := _session(clock, _save())
	assert_true(session.start())
	assert_eq(session.state.realm_id, "mortal")
	assert_almost_eq(session.state.cultivation, 0.0, 0.0001)
	assert_true(session.journal.as_text().contains("凡人"))


func test_offline_gain_is_applied_once() -> void:
	var clock := TimeService.new()
	clock.set_unix(1_000)
	var save := _save()
	var first := _session(clock, save)
	assert_true(first.start())
	clock.set_unix(1_040)
	var second := _session(clock, save)
	assert_true(second.start())
	assert_almost_eq(second.state.cultivation, 40.0, 0.0001)
	assert_almost_eq(second.last_offline_result.gained, 40.0, 0.0001)
	var third := _session(clock, save)
	assert_true(third.start())
	assert_almost_eq(third.state.cultivation, 40.0, 0.0001)
	assert_almost_eq(third.last_offline_result.gained, 0.0, 0.0001)


func test_offline_cap_and_breakthrough_use_config() -> void:
	var clock := TimeService.new()
	clock.set_unix(2_000)
	var save := _save()
	var session := _session(clock, save)
	assert_true(session.start())
	clock.set_unix(2_400)
	var resumed := _session(clock, save)
	assert_true(resumed.start())
	assert_true(resumed.last_offline_result.hit_cap)
	assert_almost_eq(resumed.state.cultivation, 100.0, 0.0001)
	assert_true(resumed.try_breakthrough())
	assert_eq(resumed.state.realm_id, "qi_early")
	assert_almost_eq(resumed.state.cultivation, 90.0, 0.0001)
	assert_true(resumed.journal.as_text().contains("突破成功"))
