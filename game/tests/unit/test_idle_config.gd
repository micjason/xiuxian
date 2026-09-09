extends GutTest


func _sample_json() -> String:
	return JSON.stringify({
		"schema_version": 1,
		"offline_cap_seconds": 28800,
		"realms": [
			{
				"id": "mortal",
				"display_name": "凡人",
				"order": 0,
				"gain_per_second": 1.0,
				"breakthrough_cost": 40,
				"next_id": "qi_early",
			},
			{
				"id": "qi_early",
				"display_name": "炼气初期",
				"order": 1,
				"gain_per_second": 2.2,
				"breakthrough_cost": 200,
				"next_id": "",
			},
		],
	})


func test_valid_config_is_loaded() -> void:
	var config := IdleConfig.from_json(_sample_json())
	assert_not_null(config)
	assert_eq(config.realms.size(), 2)
	assert_eq(config.starting_realm().id, "mortal")
	assert_eq(config.next_realm(config.starting_realm()).id, "qi_early")
	assert_eq(config.offline_cap_seconds, 28800)


func test_zero_gain_is_rejected() -> void:
	var broken := JSON.stringify({
		"schema_version": 1,
		"offline_cap_seconds": 100,
		"realms": [
			{
				"id": "mortal",
				"display_name": "凡人",
				"order": 0,
				"gain_per_second": 0,
				"breakthrough_cost": 40,
				"next_id": "",
			},
		],
	})
	assert_null(IdleConfig.from_json(broken))


func test_broken_next_link_is_rejected() -> void:
	var broken := JSON.stringify({
		"schema_version": 1,
		"offline_cap_seconds": 100,
		"realms": [
			{
				"id": "mortal",
				"display_name": "凡人",
				"order": 0,
				"gain_per_second": 1,
				"breakthrough_cost": 40,
				"next_id": "missing",
			},
		],
	})
	assert_null(IdleConfig.from_json(broken))


func test_project_idle_rules_file_is_valid() -> void:
	var config := IdleConfig.from_resource("res://resources/config/idle_rules.json")
	assert_not_null(config)
	assert_eq(config.starting_realm().display_name, "凡人")
	assert_eq(config.realms.size(), 8)
	assert_false(config.realms[7].has_next())


func test_first_three_realms_break_through_quickly() -> void:
	var config := IdleConfig.from_resource("res://resources/config/idle_rules.json")
	assert_not_null(config)
	var total := 0.0
	for realm_id in ["mortal", "qi_early", "qi_mid"]:
		var realm := config.realm_by_id(realm_id)
		assert_not_null(realm)
		var seconds := realm.breakthrough_cost / realm.gain_per_second
		assert_lte(seconds, 30.0)
		total += seconds
	assert_lte(total, 90.0)


func test_display_path_shows_current_and_next_realms() -> void:
	var config := IdleConfig.from_resource("res://resources/config/idle_rules.json")
	assert_eq(
		config.display_path(config.starting_realm()),
		"凡人  →  炼气初期  →  炼气中期"
	)
	assert_eq(config.display_path(config.realm_by_id("foundation_late")), "筑基后期")
