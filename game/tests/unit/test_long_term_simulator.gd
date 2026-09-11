extends GutTest


func test_day_1_7_30_90_180_progression_has_no_dead_end() -> void:
	var result := LongTermSimulator.simulate(180)
	assert_false(result.is_empty())
	var checkpoints: Dictionary = result.checkpoints
	for day in [1, 7, 30, 90, 180]:
		assert_true(checkpoints.has(day), "missing day %d" % day)
		assert_gt(float(checkpoints[day].resource_total), 0.0)
	assert_gte(int(checkpoints[7].recipes), 4)
	assert_gte(int(checkpoints[30].ascensions), 1)
	assert_gte(int(checkpoints[90].ascensions), 3)
	assert_gte(int(checkpoints[180].ascensions), 6)
	assert_gte(int(checkpoints[90].endings), 1)
	assert_gte(int(checkpoints[180].endings), 2)


func test_first_ascension_window_and_replay_acceleration() -> void:
	var first := LongTermSimulator.simulate(35)
	assert_gte(int(first.first_ascension_day), 21)
	assert_lte(int(first.first_ascension_day), 35)
	assert_gte(float(first.replay_factor), 1.15)
