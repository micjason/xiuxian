extends GutTest


func _realm(id: String, gain: float, cost: float, next_id: String = "next") -> RealmDef:
	var realm := RealmDef.new()
	realm.id = id
	realm.display_name = id
	realm.order = 0
	realm.gain_per_second = gain
	realm.breakthrough_cost = cost
	realm.next_id = next_id
	return realm


func _state(cultivation: float = 0.0, realm_id: String = "mortal") -> CultivationState:
	var state := CultivationState.new()
	state.cultivation = cultivation
	state.realm_id = realm_id
	state.last_settled_unix = 1000
	return state


func test_elapsed_gain_uses_rate_times_seconds() -> void:
	var state := _state(10.0)
	var result := CultivationRules.apply_elapsed(state, 2.5, 4, 0)
	assert_eq(result.applied_seconds, 4)
	assert_almost_eq(result.gained, 10.0, 0.0001)
	assert_almost_eq(state.cultivation, 20.0, 0.0001)
	assert_false(result.hit_cap)
	assert_false(result.clock_rewound)


func test_negative_elapsed_does_not_reduce_cultivation() -> void:
	var state := _state(30.0)
	var result := CultivationRules.apply_elapsed(state, 2.0, -15, 28800)
	assert_true(result.clock_rewound)
	assert_eq(result.applied_seconds, 0)
	assert_almost_eq(result.gained, 0.0, 0.0001)
	assert_almost_eq(state.cultivation, 30.0, 0.0001)


func test_offline_cap_limits_gain() -> void:
	var state := _state()
	var result := CultivationRules.apply_elapsed(state, 1.0, 40_000, 28_800)
	assert_true(result.hit_cap)
	assert_eq(result.applied_seconds, 28_800)
	assert_almost_eq(result.gained, 28_800.0, 0.0001)


func test_zero_elapsed_does_not_grant_again() -> void:
	var state := _state(8.0)
	var first := CultivationRules.apply_elapsed(state, 1.0, 5, 0)
	var second := CultivationRules.apply_elapsed(state, 1.0, 0, 0)
	assert_almost_eq(first.gained, 5.0, 0.0001)
	assert_almost_eq(second.gained, 0.0, 0.0001)
	assert_almost_eq(state.cultivation, 13.0, 0.0001)


func test_breakthrough_spends_cost_and_keeps_remainder() -> void:
	var current := _realm("mortal", 1.0, 40.0, "qi_early")
	var next_realm := _realm("qi_early", 2.2, 200.0, "qi_mid")
	var state := _state(55.0, "mortal")
	assert_true(CultivationRules.breakthrough(state, current, next_realm))
	assert_eq(state.realm_id, "qi_early")
	assert_almost_eq(state.cultivation, 15.0, 0.0001)


func test_breakthrough_fails_when_below_cost() -> void:
	var current := _realm("mortal", 1.0, 40.0)
	var next_realm := _realm("qi_early", 2.2, 200.0, "")
	var state := _state(39.0)
	assert_false(CultivationRules.can_breakthrough(state, current))
	assert_false(CultivationRules.breakthrough(state, current, next_realm))
	assert_eq(state.realm_id, "mortal")
	assert_almost_eq(state.cultivation, 39.0, 0.0001)


func test_final_realm_cannot_breakthrough() -> void:
	var current := _realm("foundation_late", 249.0, 3_125_000.0, "")
	var state := _state(9_999_999.0, "foundation_late")
	assert_false(CultivationRules.can_breakthrough(state, current))
	assert_almost_eq(CultivationRules.progress_to_next(state, current), 1.0, 0.0001)
