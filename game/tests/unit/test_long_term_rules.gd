extends GutTest

var config: LongTermConfig


func before_each() -> void:
	config = LongTermConfig.from_resource()
	assert_not_null(config)


func _economy() -> EconomyState:
	var economy := EconomyState.new()
	for resource_id: String in config.resource_names:
		economy.resources[resource_id] = 0.0
	return economy


func test_config_supplies_a_connected_vertical_slice() -> void:
	assert_eq(config.cave_rates.size(), 4)
	assert_true(config.buildings.size() >= 3)
	assert_true(config.npcs.size() >= 3)
	assert_true(config.recipes.size() >= 6)
	assert_true(config.expeditions.size() >= 2)
	assert_true(config.beasts.size() >= 2)
	assert_true(config.outposts.size() >= 3)
	assert_true(config.endings.size() >= 2)
	assert_not_null(config.ascension)
	assert_not_null(config.recipe_by_id("beast_treat"))
	assert_not_null(config.recipe_by_id("sky_chart"))


func test_cave_produces_four_resources_by_seconds_and_labor() -> void:
	var economy := _economy()
	var cave := CaveState.new()
	var craft := CraftState.new()
	var expedition := ExpeditionState.new()
	assert_true(LongTermRules.initialize(config, economy, cave, craft))
	for resource_id: String in config.cave_rates:
		assert_true(LongTermRules.assign_labor(
			cave, config, null, null, resource_id, 1
		))
	var gained := LongTermRules.apply_cave_elapsed(
		economy, cave, null, null, expedition, config, 10.0
	)
	assert_eq(gained.size(), 4)
	assert_almost_eq(economy.amount("lumen_moss"), 1.5, 0.0001)
	assert_almost_eq(economy.amount("clear_dew"), 1.1, 0.0001)
	assert_almost_eq(economy.amount("vein_sand"), 0.8, 0.0001)
	assert_almost_eq(economy.amount("hollow_wood"), 0.6, 0.0001)
	assert_false(LongTermRules.assign_labor(
		cave, config, null, null, "lumen_moss", 2
	))


func test_building_upgrade_adds_labor_and_accumulates_keys() -> void:
	var economy := _economy()
	var cave := CaveState.new()
	var craft := CraftState.new()
	var expedition := ExpeditionState.new()
	LongTermRules.initialize(config, economy, cave, craft)
	economy.add("hollow_wood", 100.0)
	economy.add("vein_sand", 100.0)
	assert_true(LongTermRules.upgrade_building(economy, cave, config, "echo_court"))
	assert_eq(cave.building_level("echo_court"), 1)
	assert_eq(LongTermRules.available_labor(cave, config, null, null), 5)
	cave.building_levels["waymark_tower"] = 1
	LongTermRules.apply_cave_elapsed(
		economy, cave, null, null, expedition, config, 900.0
	)
	assert_eq(expedition.key_count("archive_key"), 0)
	LongTermRules.apply_cave_elapsed(
		economy, cave, null, null, expedition, config, 900.0
	)
	assert_eq(expedition.key_count("archive_key"), 1)


func test_sect_join_contribution_position_and_npc_bonuses() -> void:
	var cave := CaveState.new()
	var sect := SectState.new()
	var craft := CraftState.new()
	var ascension := AscensionState.new()
	var economy := _economy()
	LongTermRules.initialize(config, economy, cave, craft)
	cave.building_levels["echo_court"] = 1
	assert_true(LongTermRules.join_sect(sect, cave, config, "ink_river_lodge"))
	assert_eq(sect.position_id, "guest")
	assert_eq(LongTermRules.add_contribution(sect, 45), 45)
	assert_true(LongTermRules.recruit_npc(sect, config, "npc_lantern_keeper"))
	var unlocked := LongTermRules.unlock_sect_recipes(sect, craft, config)
	assert_true(unlocked.has("beast_treat"))
	assert_true(craft.has_recipe("beast_treat"))
	assert_true(LongTermRules.claim_position(sect, config, "steward"))
	assert_eq(LongTermRules.available_labor(cave, config, sect, ascension), 6)
	assert_gt(LongTermRules.expedition_power(0, sect, null, config), 0)


func test_recipe_queue_completion_and_decomposition_recover_materials() -> void:
	var economy := _economy()
	var craft := CraftState.new()
	var cave := CaveState.new()
	var sect := SectState.new()
	LongTermRules.initialize(config, economy, cave, craft)
	cave.building_levels["echo_court"] = 1
	LongTermRules.join_sect(sect, cave, config, "ink_river_lodge")
	economy.add("lumen_moss", 20.0)
	economy.add("clear_dew", 20.0)
	assert_true(LongTermRules.queue_recipe(
		economy, craft, sect, config, "warm_pellet", 2
	))
	var completed := LongTermRules.apply_craft_elapsed(
		economy, craft, sect, config, 48.0
	)
	assert_eq(completed, ["warm_pellet"])
	assert_almost_eq(economy.amount("warm_pellet"), 2.0, 0.0001)
	assert_eq(craft.completed_jobs, 2)
	assert_eq(sect.contribution, 2)
	var moss_before := economy.amount("lumen_moss")
	assert_true(LongTermRules.decompose(economy, config, "warm_pellet", 1))
	assert_almost_eq(economy.amount("warm_pellet"), 1.0, 0.0001)
	assert_almost_eq(economy.amount("lumen_moss"), moss_before + 2.0, 0.0001)


func test_recipe_research_unlocks_no_later_than_pity() -> void:
	var economy := _economy()
	var craft := CraftState.new()
	var cave := CaveState.new()
	LongTermRules.initialize(config, economy, cave, craft)
	var recipe := config.recipe_by_id("dew_tonic")
	assert_not_null(recipe)
	assert_false(craft.has_recipe(recipe.id))
	for resource_id in recipe.research_costs:
		economy.add(resource_id, recipe.research_costs[resource_id] * recipe.research_pity)
	var final_result: Dictionary = {}
	for attempt in range(recipe.research_pity):
		final_result = LongTermRules.research_recipe(economy, craft, config, recipe.id, 888)
		if craft.has_recipe(recipe.id):
			break
	assert_true(bool(final_result.get("attempted", false)))
	assert_true(craft.has_recipe(recipe.id))
	assert_lte(int(final_result.get("attempts", 0)), recipe.research_pity)


func test_expedition_encounters_are_deterministic_and_reward_other_systems() -> void:
	var definition := config.expedition_by_id("moss_archive")
	var first := LongTermRules.deterministic_encounter(definition, 731, 4)
	var second := LongTermRules.deterministic_encounter(definition, 731, 4)
	assert_not_null(first)
	assert_eq(first.id, second.id)
	var economy := _economy()
	var expedition := ExpeditionState.new()
	var sect := SectState.new()
	var cave := CaveState.new()
	cave.building_levels["echo_court"] = 1
	LongTermRules.join_sect(sect, cave, config, "ink_river_lodge")
	expedition.keys["archive_key"] = 1
	var result := LongTermRules.run_expedition(
		economy, expedition, sect, null, config, "moss_archive", 3, 731
	)
	assert_true(bool(result.success))
	assert_eq(str(result.encounter_id), LongTermRules.deterministic_encounter(
		definition, 731, 0
	).id)
	assert_eq(expedition.clear_count("moss_archive"), 1)
	assert_eq(expedition.key_count("archive_key"), 0)
	assert_gt(sect.contribution, 0)
	assert_gt(economy.amount("lumen_moss"), 0.0)


func test_auto_commission_consumes_key_and_runs_during_elapsed_time() -> void:
	var economy := _economy()
	var expedition := ExpeditionState.new()
	var cave := CaveState.new()
	var craft := CraftState.new()
	LongTermRules.initialize(config, economy, cave, craft)
	cave.building_levels["waymark_tower"] = 1
	LongTermRules.apply_cave_elapsed(
		economy, cave, null, null, expedition, config, 3600.0
	)
	assert_eq(expedition.key_count("archive_key"), 2)
	assert_true(LongTermRules.set_auto_expedition(expedition, config, "moss_archive"))
	var results := LongTermRules.apply_auto_expeditions(
		economy, expedition, null, null, config, 3600.0, 3, 91
	)
	assert_eq(results.size(), 1)
	assert_eq(expedition.clear_count("moss_archive"), 1)
	assert_eq(expedition.key_count("archive_key"), 1)
	assert_true(LongTermRules.set_auto_expedition(expedition, config, ""))


func test_first_beast_is_claimed_deployed_fed_and_boosts_power() -> void:
	var economy := _economy()
	var expedition := ExpeditionState.new()
	var beast := BeastState.new()
	expedition.clear_counts["moss_archive"] = 1
	assert_true(LongTermRules.claim_beast(beast, expedition, config, "ember_marten"))
	assert_eq(beast.active_id, "ember_marten")
	assert_eq(beast.level_of("ember_marten"), 1)
	economy.add("beast_treat", 2.0)
	assert_eq(LongTermRules.feed_beast(
		economy, beast, config, "ember_marten", 2
	), 12)
	assert_eq(beast.level_of("ember_marten"), 2)
	assert_gt(LongTermRules.expedition_power(0, null, beast, config), 0)
	assert_true(LongTermRules.deploy_beast(beast, "ember_marten"))


func test_soft_ascension_checks_all_axes_and_keeps_inheritance() -> void:
	var economy := _economy()
	var cave := CaveState.new()
	var sect := SectState.new()
	var craft := CraftState.new()
	var beast := BeastState.new()
	var expedition := ExpeditionState.new()
	var ascension := AscensionState.new()
	LongTermRules.initialize(config, economy, cave, craft)
	cave.building_levels[config.ascension.building_id] = config.ascension.building_level
	sect.sect_id = "ink_river_lodge"
	sect.contribution = config.ascension.contribution
	sect.position_id = "path_warden"
	craft.completed_jobs = config.ascension.completed_jobs
	expedition.clear_counts["moss_archive"] = config.ascension.expedition_clears
	beast.owned_ids.append("ember_marten")
	beast.active_id = "ember_marten"
	beast.levels["ember_marten"] = config.ascension.beast_level
	for resource_id: String in config.ascension.costs:
		economy.add(resource_id, config.ascension.costs[resource_id])
	assert_true(LongTermRules.can_soft_ascend(
		economy, cave, sect, craft, beast, expedition, config,
		config.ascension.min_realm_order,
		config.ascension.min_run_seconds
	))
	assert_true(LongTermRules.soft_ascend(
		economy, cave, sect, craft, beast, expedition, ascension, config,
		config.ascension.min_realm_order,
		config.ascension.min_run_seconds
	))
	assert_eq(ascension.ascension_count, 1)
	assert_eq(ascension.legacy_points, config.ascension.legacy_points)
	assert_eq(ascension.inherited_labor, config.ascension.labor_reward)
	assert_eq(expedition.key_count("archive_key"), config.ascension.key_reward)
	assert_false(sect.has_joined())
	assert_eq(craft.completed_jobs, 0)
	assert_true(beast.owned_ids.is_empty())
	assert_eq(
		LongTermRules.available_labor(cave, config, sect, ascension),
		cave.labor_total + ascension.inherited_labor
	)


func test_outposts_accelerate_replays_and_unlock_finite_endings() -> void:
	var economy := _economy()
	var ascension := AscensionState.new()
	ascension.ascension_count = 3
	ascension.legacy_points = 9
	var outpost := config.outpost_by_id("mortal_anchor")
	assert_not_null(outpost)
	for level in range(1, outpost.max_level + 1):
		for resource_id in outpost.costs:
			economy.add(resource_id, outpost.costs[resource_id] * float(level))
		assert_true(LongTermRules.upgrade_outpost(
			economy, ascension, config, outpost.id
		))
	assert_eq(LongTermRules.total_outpost_levels(ascension), 5)
	var progress := LongTermState.new()
	progress.ascension = ascension
	assert_gt(LongTermRules.cultivate_factor(progress, config), 1.0)
	assert_true(LongTermRules.claim_ending(
		ascension, config, "hundred_day_covenant"
	))
	assert_false(LongTermRules.claim_ending(
		ascension, config, "hundred_day_covenant"
	))
