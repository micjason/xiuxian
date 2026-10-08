extends GutTest


func test_published_idle_replaces_offline_cap_and_breakthrough_cost() -> void:
	var service := ConfigService.new()
	assert_true(service.load_all())
	var remote := {
		"idle": {
			"schema_version": 1,
			"offline_cap_seconds": 14400,
			"realms": [
				{
					"id": "mortal",
					"display_name": "凡人",
					"order": 0,
					"gain_per_second": 9.0,
					"breakthrough_cost": 123.0,
					"next_id": "",
				},
			],
		},
	}
	assert_true(service.apply_published(remote))
	assert_eq(service.idle.offline_cap_seconds, 14400)
	assert_eq(service.idle.realms[0].breakthrough_cost, 123.0)
	assert_eq(service.idle.realms[0].gain_per_second, 9.0)
