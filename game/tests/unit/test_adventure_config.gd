extends GutTest


func test_project_adventure_table_is_complete() -> void:
	var config := AdventureConfig.from_resource()
	assert_not_null(config)
	assert_eq(config.stages.size(), 8)
	assert_eq(config.skills.size(), 16)
	assert_true(config.items.size() >= 50)
	var qualities: Dictionary = {}
	var slots: Dictionary = {}
	var ranks: Dictionary = {}
	for item in config.items:
		if item.is_equipment():
			qualities[item.quality] = true
			slots[item.slot] = true
	for skill in config.skills:
		ranks[skill.rank] = true
	for quality in QualityId.ORDER:
		assert_true(qualities.has(quality), "missing quality %s" % quality)
	for slot in EquipSlot.ORDER:
		assert_true(slots.has(slot), "missing slot %s" % slot)
	for rank in SkillRank.ORDER:
		assert_true(ranks.has(rank), "missing skill rank %s" % rank)
	assert_eq(config.starting_stage().id, "grove")
	assert_eq(config.stages[7].id, "stele_terrace")
	assert_true(config.stages[0].monsters.size() >= 5)
	assert_almost_eq(config.loot_chance_scale, 0.2, 0.0001)
	assert_almost_eq(config.stages[1].min_power, 36.0, 0.0001)
	assert_almost_eq(config.stages[1].min_attack, 18.0, 0.0001)
	assert_almost_eq(config.stages[2].min_speed, 3.2, 0.0001)
	assert_almost_eq(config.stages[4].min_defense, 28.0, 0.0001)
	assert_almost_eq(config.stages[7].min_power, 540.0, 0.0001)
	assert_almost_eq(config.stages[7].min_attack, 95.0, 0.0001)
	var gold_late := config.realm_stats("gold_core_late")
	assert_not_null(gold_late)
	assert_gt(gold_late.attack, 0.0)


func test_invalid_schema_is_rejected() -> void:
	assert_null(AdventureConfig.from_json('{"schema_version": 2}'))
