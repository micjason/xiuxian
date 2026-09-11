class_name LongTermSimulator
extends RefCounted

const DAILY_SETTLEMENT_SECONDS := 8 * 60 * 60
const CHECKPOINT_DAYS := [1, 7, 30, 90, 180]


static func simulate(days: int) -> Dictionary:
	var idle := IdleConfig.from_resource("res://resources/config/idle_rules.json")
	var config := LongTermConfig.from_resource()
	if idle == null or config == null or days <= 0:
		return {}
	var state := CultivationState.new()
	state.realm_id = idle.starting_realm().id
	state.long_term = LongTermState.new()
	LongTermRules.initialize(
		config,
		state.long_term.economy,
		state.long_term.cave,
		state.long_term.craft
	)
	var realm_order := 0
	var first_ascension_day := 0
	var replay_factor := 1.0
	var checkpoints: Dictionary = {}
	for day in range(1, days + 1):
		_assign_default_labor(state.long_term, config)
		_advance_cultivation(state, idle, config, realm_order)
		realm_order = _realm_order(idle, state.realm_id)
		SettlementEngine.settle_long_term(
			state,
			config,
			DAILY_SETTLEMENT_SECONDS,
			realm_order * 2 + 4
		)
		_upgrade_cave(state.long_term, config)
		_join_and_recruit(state.long_term, config)
		_run_available_expeditions(state.long_term, config, realm_order, day)
		_join_and_recruit(state.long_term, config)
		_claim_and_feed_beast(state.long_term, config)
		_queue_progress_recipes(state.long_term, config)
		_upgrade_outposts(state.long_term, config)
		_claim_endings(state.long_term, config)
		if LongTermRules.soft_ascend(
			state.long_term.economy,
			state.long_term.cave,
			state.long_term.sect,
			state.long_term.craft,
			state.long_term.beast,
			state.long_term.expedition,
			state.long_term.ascension,
			config,
			realm_order,
			state.long_term.run_seconds
		):
			if first_ascension_day == 0:
				first_ascension_day = day
				replay_factor = LongTermRules.cultivate_factor(state.long_term, config)
			state.realm_id = idle.starting_realm().id
			state.cultivation = 0.0
			state.long_term.run_seconds = 0
			realm_order = 0
		if CHECKPOINT_DAYS.has(day):
			checkpoints[day] = _snapshot(state, idle, config)
	return {
		"days": days,
		"first_ascension_day": first_ascension_day,
		"replay_factor": replay_factor,
		"checkpoints": checkpoints,
		"completed_endings": Array(state.long_term.ascension.completed_ending_ids),
		"final": _snapshot(state, idle, config),
	}


static func _advance_cultivation(
	state: CultivationState,
	idle: IdleConfig,
	config: LongTermConfig,
	_realm_order_before: int
) -> void:
	var realm := idle.realm_by_id(state.realm_id)
	if realm == null:
		return
	state.cultivation += (
		realm.gain_per_second
		* DAILY_SETTLEMENT_SECONDS
		* LongTermRules.cultivate_factor(state.long_term, config)
	)
	while realm.has_next() and state.cultivation >= realm.breakthrough_cost:
		state.cultivation -= realm.breakthrough_cost
		realm = idle.next_realm(realm)
		state.realm_id = realm.id


static func _assign_default_labor(progress: LongTermState, config: LongTermConfig) -> void:
	for resource_id in config.cave_rates:
		LongTermRules.assign_labor(
			progress.cave,
			config,
			progress.sect,
			progress.ascension,
			resource_id,
			1
		)


static func _upgrade_cave(progress: LongTermState, config: LongTermConfig) -> void:
	var targets := {"echo_court": 3, "waymark_tower": 2, "rain_workshop": 2}
	for building_id in targets:
		while (
			progress.cave.building_level(building_id) < int(targets[building_id])
			and LongTermRules.upgrade_building(
				progress.economy,
				progress.cave,
				config,
				building_id
			)
		):
			pass


static func _join_and_recruit(progress: LongTermState, config: LongTermConfig) -> void:
	if not progress.sect.has_joined():
		LongTermRules.join_sect(
			progress.sect,
			progress.cave,
			config,
			"ink_river_lodge"
		)
	for npc in config.npcs:
		LongTermRules.recruit_npc(progress.sect, config, npc.id)
	LongTermRules.unlock_sect_recipes(progress.sect, progress.craft, config)
	for position in config.positions:
		LongTermRules.claim_position(progress.sect, config, position.id)


static func _run_available_expeditions(
	progress: LongTermState,
	config: LongTermConfig,
	realm_order: int,
	day: int
) -> void:
	var runs := 0
	for definition in config.expeditions:
		while (
			runs < 10
			and progress.expedition.key_count(definition.key_id) > 0
			and LongTermRules.expedition_power(
				realm_order * 2 + 4,
				progress.sect,
				progress.beast,
				config
			) >= definition.required_power
		):
			var result := LongTermRules.run_expedition(
				progress.economy,
				progress.expedition,
				progress.sect,
				progress.beast,
				config,
				definition.id,
				realm_order * 2 + 4,
				day * 10_000 + runs
			)
			if not bool(result.get("success", false)):
				break
			runs += 1


static func _claim_and_feed_beast(progress: LongTermState, config: LongTermConfig) -> void:
	for beast in config.beasts:
		LongTermRules.claim_beast(progress.beast, progress.expedition, config, beast.id)
	if not progress.beast.active_id.is_empty():
		LongTermRules.feed_beast(
			progress.economy,
			progress.beast,
			config,
			progress.beast.active_id,
			12
		)


static func _queue_progress_recipes(progress: LongTermState, config: LongTermConfig) -> void:
	var plans := [
		["warm_pellet", 4],
		["resonance_pin", 4],
		["beast_treat", 6],
		["sky_chart", 1],
	]
	for plan in plans:
		if progress.craft.queue.size() >= config.queue_limit:
			break
		LongTermRules.queue_recipe(
			progress.economy,
			progress.craft,
			progress.sect,
			config,
			plan[0],
			plan[1]
		)


static func _upgrade_outposts(progress: LongTermState, config: LongTermConfig) -> void:
	for outpost in config.outposts:
		LongTermRules.upgrade_outpost(
			progress.economy,
			progress.ascension,
			config,
			outpost.id
		)


static func _claim_endings(progress: LongTermState, config: LongTermConfig) -> void:
	for ending in config.endings:
		LongTermRules.claim_ending(progress.ascension, config, ending.id)


static func _snapshot(
	state: CultivationState,
	idle: IdleConfig,
	config: LongTermConfig
) -> Dictionary:
	var resource_total := 0.0
	for value in state.long_term.economy.resources.values():
		resource_total += float(value)
	return {
		"realm_order": _realm_order(idle, state.realm_id),
		"realm_id": state.realm_id,
		"resource_total": resource_total,
		"recipes": state.long_term.craft.unlocked_recipe_ids.size(),
		"expedition_clears": state.long_term.expedition.total_clears(),
		"beasts": state.long_term.beast.owned_ids.size(),
		"ascensions": state.long_term.ascension.ascension_count,
		"legacy_points": state.long_term.ascension.legacy_points,
		"outpost_levels": LongTermRules.total_outpost_levels(state.long_term.ascension),
		"endings": state.long_term.ascension.completed_ending_ids.size(),
		"cultivate_factor": LongTermRules.cultivate_factor(state.long_term, config),
	}


static func _realm_order(idle: IdleConfig, realm_id: String) -> int:
	var realm := idle.realm_by_id(realm_id)
	return realm.order if realm != null else 0
