class_name LongTermRules
extends RefCounted

const EPSILON := 0.000001


static func initialize(
	config: LongTermConfig,
	economy: EconomyState,
	cave: CaveState,
	craft: CraftState
) -> bool:
	if config == null or economy == null or cave == null or craft == null:
		return false
	for resource_id: String in config.resource_names:
		if not economy.resources.has(resource_id):
			economy.resources[resource_id] = 0.0
	for resource_id: String in config.cave_rates:
		if not cave.labor.has(resource_id):
			cave.labor[resource_id] = 0
	for building: LongTermConfig.BuildingDef in config.buildings:
		if not cave.building_levels.has(building.id):
			cave.building_levels[building.id] = 0
	if craft.unlocked_recipe_ids.is_empty():
		for recipe: LongTermConfig.RecipeDef in config.recipes:
			if recipe.unlock_npc_id.is_empty() and recipe.research_pity <= 0:
				craft.unlocked_recipe_ids.append(recipe.id)
	return true


static func available_labor(
	cave: CaveState,
	config: LongTermConfig,
	sect: SectState,
	ascension: AscensionState
) -> int:
	if cave == null or config == null:
		return 0
	var total := maxi(cave.labor_total, 0)
	for building: LongTermConfig.BuildingDef in config.buildings:
		total += cave.building_level(building.id) * maxi(building.labor_bonus, 0)
	if sect != null:
		for npc_id: String in sect.joined_npc_ids:
			var npc := config.npc_by_id(npc_id)
			if npc != null:
				total += maxi(npc.labor_bonus, 0)
	if ascension != null:
		total += maxi(ascension.inherited_labor, 0)
		for outpost in config.outposts:
			total += (
				maxi(int(ascension.outpost_levels.get(outpost.id, 0)), 0)
				* maxi(outpost.labor_bonus_per_level, 0)
			)
	return total


static func assign_labor(
	cave: CaveState,
	config: LongTermConfig,
	sect: SectState,
	ascension: AscensionState,
	resource_id: String,
	amount: int
) -> bool:
	if cave == null or config == null or not config.cave_rates.has(resource_id) or amount < 0:
		return false
	var previous := maxi(cave.labor.get(resource_id, 0), 0)
	var next_total := cave.assigned_labor() - previous + amount
	if next_total > available_labor(cave, config, sect, ascension):
		return false
	cave.labor[resource_id] = amount
	return true


static func apply_cave_elapsed(
	economy: EconomyState,
	cave: CaveState,
	sect: SectState,
	beast: BeastState,
	expedition: ExpeditionState,
	config: LongTermConfig,
	elapsed_seconds: float
) -> Dictionary[String, float]:
	var gained: Dictionary[String, float] = {}
	if (
		economy == null
		or cave == null
		or expedition == null
		or config == null
		or elapsed_seconds <= 0.0
	):
		return gained
	var shared_multiplier := 1.0 + _sect_production_bonus(sect, config)
	shared_multiplier += _active_beast_cave_bonus(beast, config)
	for resource_id: String in config.cave_rates:
		var workers := maxi(cave.labor.get(resource_id, 0), 0)
		if workers <= 0:
			continue
		var multiplier := shared_multiplier + _building_production_bonus(cave, config, resource_id)
		var value := config.cave_rates[resource_id] * float(workers) * elapsed_seconds * multiplier
		economy.add(resource_id, value)
		gained[resource_id] = value
	_accrue_keys(cave, expedition, config, elapsed_seconds)
	return gained


static func building_upgrade_cost(
	building: LongTermConfig.BuildingDef,
	next_level: int
) -> Dictionary[String, float]:
	var result: Dictionary[String, float] = {}
	if building == null or next_level <= 0:
		return result
	for resource_id: String in building.costs:
		result[resource_id] = building.costs[resource_id] * float(next_level)
	return result


static func upgrade_building(
	economy: EconomyState,
	cave: CaveState,
	config: LongTermConfig,
	building_id: String
) -> bool:
	if economy == null or cave == null or config == null:
		return false
	var building := config.building_by_id(building_id)
	if building == null:
		return false
	var next_level := cave.building_level(building_id) + 1
	if next_level > building.max_level:
		return false
	var costs := building_upgrade_cost(building, next_level)
	if not economy.spend(costs):
		return false
	cave.building_levels[building_id] = next_level
	return true


static func join_sect(
	sect: SectState,
	cave: CaveState,
	config: LongTermConfig,
	sect_id: String
) -> bool:
	if sect == null or cave == null or config == null or sect.has_joined():
		return false
	var definition := config.sect_by_id(sect_id)
	if (
		definition == null
		or cave.building_level(definition.join_building_id) < definition.join_building_level
	):
		return false
	sect.sect_id = sect_id
	sect.position_id = config.positions[0].id if not config.positions.is_empty() else ""
	return true


static func add_contribution(sect: SectState, amount: int) -> int:
	if sect == null or not sect.has_joined() or amount <= 0:
		return 0
	sect.contribution += amount
	return amount


static func recruit_npc(sect: SectState, config: LongTermConfig, npc_id: String) -> bool:
	if sect == null or config == null or not sect.has_joined() or sect.has_npc(npc_id):
		return false
	var npc := config.npc_by_id(npc_id)
	if npc == null or sect.contribution < npc.contribution_required:
		return false
	sect.joined_npc_ids.append(npc_id)
	return true


static func unlock_sect_recipes(
	sect: SectState,
	craft: CraftState,
	config: LongTermConfig
) -> PackedStringArray:
	var unlocked := PackedStringArray()
	if sect == null or craft == null or config == null:
		return unlocked
	for recipe in config.recipes:
		if (
			not recipe.unlock_npc_id.is_empty()
			and sect.has_npc(recipe.unlock_npc_id)
			and not craft.has_recipe(recipe.id)
		):
			craft.unlocked_recipe_ids.append(recipe.id)
			unlocked.append(recipe.id)
	return unlocked


static func claim_position(sect: SectState, config: LongTermConfig, position_id: String) -> bool:
	if sect == null or config == null or not sect.has_joined():
		return false
	var position := config.position_by_id(position_id)
	if position == null or sect.contribution < position.contribution_required:
		return false
	sect.position_id = position_id
	return true


static func research_recipe(
	economy: EconomyState,
	craft: CraftState,
	config: LongTermConfig,
	recipe_id: String,
	seed: int
) -> Dictionary:
	var result := {"attempted": false, "unlocked": false, "attempts": 0}
	if economy == null or craft == null or config == null or craft.has_recipe(recipe_id):
		return result
	var recipe := config.recipe_by_id(recipe_id)
	if (
		recipe == null
		or recipe.research_pity <= 0
		or recipe.research_costs.is_empty()
		or not economy.spend(recipe.research_costs)
	):
		return result
	var attempts := maxi(int(craft.research_attempts.get(recipe_id, 0)), 0) + 1
	craft.research_attempts[recipe_id] = attempts
	var roll := float(_stable_hash("%s|%d|%d" % [recipe_id, seed, attempts]) % 10_000) / 10_000.0
	var unlocked := attempts >= recipe.research_pity or roll < recipe.research_chance
	if unlocked:
		craft.unlocked_recipe_ids.append(recipe_id)
	result.attempted = true
	result.unlocked = unlocked
	result.attempts = attempts
	return result


static func queue_recipe(
	economy: EconomyState,
	craft: CraftState,
	sect: SectState,
	config: LongTermConfig,
	recipe_id: String,
	amount: int = 1
) -> bool:
	if (
		economy == null
		or craft == null
		or config == null
		or amount <= 0
		or craft.queue.size() >= config.queue_limit
		or not craft.has_recipe(recipe_id)
	):
		return false
	var recipe := config.recipe_by_id(recipe_id)
	if recipe == null:
		return false
	var inputs := _scaled_values(recipe.inputs, amount)
	if not economy.spend(inputs):
		return false
	var speed := 1.0 + _sect_craft_speed_bonus(sect, config)
	craft.queue.append(CraftJob.create(recipe_id, recipe.duration_seconds * float(amount) / speed, amount))
	return true


static func apply_craft_elapsed(
	economy: EconomyState,
	craft: CraftState,
	sect: SectState,
	config: LongTermConfig,
	elapsed_seconds: float
) -> Array[String]:
	var completed: Array[String] = []
	if economy == null or craft == null or config == null or elapsed_seconds <= 0.0:
		return completed
	var remaining := elapsed_seconds
	while remaining > EPSILON and not craft.queue.is_empty():
		var job: CraftJob = craft.queue[0]
		var applied := minf(remaining, job.remaining_seconds)
		job.remaining_seconds -= applied
		remaining -= applied
		if job.remaining_seconds > EPSILON:
			break
		var recipe := config.recipe_by_id(job.recipe_id)
		if recipe != null:
			_add_values(economy, recipe.outputs, job.amount)
			craft.completed_jobs += job.amount
			add_contribution(sect, job.amount)
			completed.append(job.recipe_id)
		craft.queue.remove_at(0)
	return completed


static func decompose(
	economy: EconomyState,
	config: LongTermConfig,
	recipe_id: String,
	amount: int = 1
) -> bool:
	if economy == null or config == null or amount <= 0:
		return false
	var recipe := config.recipe_by_id(recipe_id)
	if recipe == null or recipe.salvage.is_empty():
		return false
	if not economy.spend(_scaled_values(recipe.outputs, amount)):
		return false
	_add_values(economy, recipe.salvage, amount)
	return true


static func expedition_power(
	base_power: int,
	sect: SectState,
	beast: BeastState,
	config: LongTermConfig
) -> int:
	var total := maxi(base_power, 0)
	if config == null:
		return total
	if sect != null:
		var position := config.position_by_id(sect.position_id)
		if position != null:
			total += position.expedition_power
		for npc_id: String in sect.joined_npc_ids:
			var npc := config.npc_by_id(npc_id)
			if npc != null:
				total += npc.expedition_power
	if beast != null and not beast.active_id.is_empty():
		var beast_def := config.beast_by_id(beast.active_id)
		if beast_def != null:
			total += beast.level_of(beast.active_id) * beast_def.expedition_power_per_level
	return total


static func cultivate_factor(progress: LongTermState, config: LongTermConfig) -> float:
	if progress == null or config == null:
		return 1.0
	var bonus := 0.0
	for building in config.buildings:
		bonus += (
			building.cultivate_bonus_per_level
			* float(progress.cave.building_level(building.id))
		)
	var position := config.position_by_id(progress.sect.position_id)
	if position != null:
		bonus += position.cultivate_bonus
	if config.ascension != null:
		bonus += (
			config.ascension.cultivate_bonus_per_legacy
			* float(progress.ascension.legacy_points)
		)
	for outpost in config.outposts:
		bonus += (
			outpost.cultivate_bonus_per_level
			* float(progress.ascension.outpost_levels.get(outpost.id, 0))
		)
	return 1.0 + maxf(bonus, 0.0)


static func apply_combat_bonus(
	stats: CombatStats,
	progress: LongTermState,
	config: LongTermConfig
) -> void:
	if stats == null or progress == null or config == null:
		return
	var beast_id := progress.beast.active_id
	var definition := config.beast_by_id(beast_id)
	if definition != null:
		var level := float(progress.beast.level_of(beast_id))
		stats.attack += definition.attack_per_level * level
		stats.defense += definition.defense_per_level * level
		stats.hp += definition.hp_per_level * level
		stats.speed += definition.speed_per_level * level
	if config.ascension != null and progress.ascension.legacy_points > 0:
		var scale := (
			1.0
			+ config.ascension.cultivate_bonus_per_legacy
			* float(progress.ascension.legacy_points)
		)
		stats.attack *= scale
		stats.defense *= scale
		stats.hp *= scale


static func deterministic_encounter(
	expedition: LongTermConfig.ExpeditionDef,
	seed: int,
	index: int
) -> LongTermConfig.EncounterDef:
	if expedition == null or expedition.encounters.is_empty():
		return null
	var total_weight := 0
	for encounter: LongTermConfig.EncounterDef in expedition.encounters:
		total_weight += maxi(encounter.weight, 0)
	if total_weight <= 0:
		return null
	var roll := _stable_hash("%d|%d|%s" % [seed, index, expedition.id]) % total_weight
	for encounter: LongTermConfig.EncounterDef in expedition.encounters:
		roll -= encounter.weight
		if roll < 0:
			return encounter
	return expedition.encounters.back()


static func run_expedition(
	economy: EconomyState,
	expedition_state: ExpeditionState,
	sect: SectState,
	beast: BeastState,
	config: LongTermConfig,
	expedition_id: String,
	base_power: int,
	seed: int
) -> Dictionary:
	var result := {"success": false, "encounter_id": "", "rewards": {}}
	if economy == null or expedition_state == null or config == null:
		return result
	var definition := config.expedition_by_id(expedition_id)
	if (
		definition == null
		or expedition_state.key_count(definition.key_id) <= 0
		or expedition_power(base_power, sect, beast, config) < definition.required_power
	):
		return result
	var encounter := deterministic_encounter(definition, seed, expedition_state.encounter_index)
	if encounter == null:
		return result
	expedition_state.keys[definition.key_id] = expedition_state.key_count(definition.key_id) - 1
	expedition_state.clear_counts[expedition_id] = expedition_state.clear_count(expedition_id) + 1
	expedition_state.encounter_index += 1
	var rewards: Dictionary[String, float] = definition.rewards.duplicate()
	for resource_id: String in encounter.rewards:
		rewards[resource_id] = rewards.get(resource_id, 0.0) + encounter.rewards[resource_id]
	_add_values(economy, rewards, 1)
	add_contribution(sect, definition.contribution + encounter.contribution)
	result.success = true
	result.encounter_id = encounter.id
	result.rewards = rewards
	return result


static func set_auto_expedition(
	expedition_state: ExpeditionState,
	config: LongTermConfig,
	expedition_id: String
) -> bool:
	if expedition_state == null or config == null:
		return false
	if not expedition_id.is_empty() and config.expedition_by_id(expedition_id) == null:
		return false
	expedition_state.auto_expedition_id = expedition_id
	expedition_state.commission_remainder = 0.0
	return true


static func apply_auto_expeditions(
	economy: EconomyState,
	expedition_state: ExpeditionState,
	sect: SectState,
	beast: BeastState,
	config: LongTermConfig,
	elapsed_seconds: float,
	base_power: int,
	seed: int
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if (
		expedition_state == null
		or config == null
		or expedition_state.auto_expedition_id.is_empty()
		or elapsed_seconds <= 0.0
	):
		return results
	var definition := config.expedition_by_id(expedition_state.auto_expedition_id)
	if definition == null or definition.commission_seconds <= 0.0:
		return results
	expedition_state.commission_remainder += elapsed_seconds
	var due := floori(
		expedition_state.commission_remainder / definition.commission_seconds
	)
	for index in range(due):
		var result := run_expedition(
			economy,
			expedition_state,
			sect,
			beast,
			config,
			definition.id,
			base_power,
			seed + index
		)
		if not bool(result.get("success", false)):
			break
		expedition_state.commission_remainder -= definition.commission_seconds
		results.append(result)
	expedition_state.commission_remainder = minf(
		expedition_state.commission_remainder,
		definition.commission_seconds * 3.0
	)
	return results


static func claim_beast(
	beast: BeastState,
	expedition: ExpeditionState,
	config: LongTermConfig,
	beast_id: String
) -> bool:
	if beast == null or expedition == null or config == null or beast.owns(beast_id):
		return false
	var definition := config.beast_by_id(beast_id)
	if (
		definition == null
		or expedition.clear_count(definition.claim_expedition_id) < definition.claim_clear_count
	):
		return false
	beast.owned_ids.append(beast_id)
	beast.levels[beast_id] = 1
	beast.experience[beast_id] = 0
	if beast.active_id.is_empty():
		beast.active_id = beast_id
	return true


static func deploy_beast(beast: BeastState, beast_id: String) -> bool:
	if beast == null or not beast.owns(beast_id):
		return false
	beast.active_id = beast_id
	return true


static func feed_beast(
	economy: EconomyState,
	beast: BeastState,
	config: LongTermConfig,
	beast_id: String,
	servings: int = 1
) -> int:
	if economy == null or beast == null or config == null or servings <= 0 or not beast.owns(beast_id):
		return 0
	var definition := config.beast_by_id(beast_id)
	if definition == null:
		return 0
	var costs: Dictionary[String, float] = {
		definition.feed_resource_id: definition.feed_amount * float(servings)
	}
	if not economy.spend(costs):
		return 0
	var level := maxi(beast.level_of(beast_id), 1)
	var experience := beast.experience_of(beast_id) + definition.feed_experience * servings
	while experience >= definition.base_level_cost * level:
		experience -= definition.base_level_cost * level
		level += 1
	beast.levels[beast_id] = level
	beast.experience[beast_id] = experience
	return definition.feed_experience * servings


static func can_soft_ascend(
	economy: EconomyState,
	cave: CaveState,
	sect: SectState,
	craft: CraftState,
	beast: BeastState,
	expedition: ExpeditionState,
	config: LongTermConfig,
	realm_order: int,
	run_seconds: int
) -> bool:
	if (
		economy == null
		or cave == null
		or sect == null
		or craft == null
		or beast == null
		or expedition == null
		or config == null
		or config.ascension == null
	):
		return false
	var requirement := config.ascension
	var active_level := beast.level_of(beast.active_id)
	return (
		realm_order >= requirement.min_realm_order
		and run_seconds >= requirement.min_run_seconds
		and cave.building_level(requirement.building_id) >= requirement.building_level
		and sect.contribution >= requirement.contribution
		and craft.completed_jobs >= requirement.completed_jobs
		and expedition.total_clears() >= requirement.expedition_clears
		and active_level >= requirement.beast_level
		and economy.can_spend(requirement.costs)
	)


static func upgrade_outpost(
	economy: EconomyState,
	ascension: AscensionState,
	config: LongTermConfig,
	outpost_id: String
) -> bool:
	if economy == null or ascension == null or config == null:
		return false
	var definition := config.outpost_by_id(outpost_id)
	if definition == null or ascension.ascension_count <= 0:
		return false
	var current := maxi(int(ascension.outpost_levels.get(outpost_id, 0)), 0)
	var next_level := current + 1
	if next_level > definition.max_level:
		return false
	var costs := _scaled_values(definition.costs, next_level)
	if not economy.spend(costs):
		return false
	ascension.outpost_levels[outpost_id] = next_level
	return true


static func total_outpost_levels(ascension: AscensionState) -> int:
	if ascension == null:
		return 0
	var total := 0
	for level in ascension.outpost_levels.values():
		total += maxi(int(level), 0)
	return total


static func claim_ending(
	ascension: AscensionState,
	config: LongTermConfig,
	ending_id: String
) -> bool:
	if ascension == null or config == null or ascension.completed_ending_ids.has(ending_id):
		return false
	var definition := config.ending_by_id(ending_id)
	if (
		definition == null
		or ascension.ascension_count < definition.ascension_count
		or ascension.legacy_points < definition.legacy_points
		or total_outpost_levels(ascension) < definition.outpost_levels
	):
		return false
	ascension.completed_ending_ids.append(ending_id)
	return true


static func soft_ascend(
	economy: EconomyState,
	cave: CaveState,
	sect: SectState,
	craft: CraftState,
	beast: BeastState,
	expedition: ExpeditionState,
	ascension: AscensionState,
	config: LongTermConfig,
	realm_order: int,
	run_seconds: int
) -> bool:
	if ascension == null or not can_soft_ascend(
		economy, cave, sect, craft, beast, expedition, config, realm_order, run_seconds
	):
		return false
	if not economy.spend(config.ascension.costs):
		return false
	ascension.ascension_count += 1
	ascension.legacy_points += config.ascension.legacy_points
	ascension.inherited_labor += config.ascension.labor_reward
	ascension.inherited_key_charges += config.ascension.key_reward
	for resource_id: String in economy.resources:
		economy.resources[resource_id] = 0.0
	for building_id: String in cave.building_levels:
		cave.building_levels[building_id] = 0
	for resource_id: String in cave.labor:
		cave.labor[resource_id] = 0
	cave.production_remainder.clear()
	sect.sect_id = ""
	sect.contribution = 0
	sect.position_id = ""
	sect.joined_npc_ids.clear()
	craft.queue.clear()
	craft.completed_jobs = 0
	beast.owned_ids.clear()
	beast.active_id = ""
	beast.levels.clear()
	beast.experience.clear()
	expedition.keys.clear()
	expedition.key_remainders.clear()
	expedition.clear_counts.clear()
	expedition.encounter_index = 0
	expedition.auto_expedition_id = ""
	expedition.commission_remainder = 0.0
	if not config.expeditions.is_empty():
		var key_id := config.expeditions[0].key_id
		expedition.keys[key_id] = config.ascension.key_reward
	return true


static func _scaled_values(
	values: Dictionary[String, float],
	amount: int
) -> Dictionary[String, float]:
	var result: Dictionary[String, float] = {}
	for resource_id: String in values:
		result[resource_id] = values[resource_id] * float(amount)
	return result


static func _add_values(
	economy: EconomyState,
	values: Dictionary[String, float],
	amount: int
) -> void:
	for resource_id: String in values:
		economy.add(resource_id, values[resource_id] * float(amount))


static func _building_production_bonus(
	cave: CaveState,
	config: LongTermConfig,
	resource_id: String
) -> float:
	var bonus := 0.0
	for building: LongTermConfig.BuildingDef in config.buildings:
		bonus += building.production_bonus.get(resource_id, 0.0) * cave.building_level(building.id)
	return bonus


static func _sect_production_bonus(sect: SectState, config: LongTermConfig) -> float:
	if sect == null:
		return 0.0
	var position := config.position_by_id(sect.position_id)
	return position.production_bonus if position != null else 0.0


static func _sect_craft_speed_bonus(sect: SectState, config: LongTermConfig) -> float:
	var bonus := 0.0
	if sect == null:
		return bonus
	for npc_id: String in sect.joined_npc_ids:
		var npc := config.npc_by_id(npc_id)
		if npc != null:
			bonus += npc.craft_speed_bonus
	return bonus


static func _active_beast_cave_bonus(beast: BeastState, config: LongTermConfig) -> float:
	if beast == null or beast.active_id.is_empty():
		return 0.0
	var definition := config.beast_by_id(beast.active_id)
	if definition == null:
		return 0.0
	return beast.level_of(beast.active_id) * definition.cave_bonus_per_level


static func _accrue_keys(
	cave: CaveState,
	expedition: ExpeditionState,
	config: LongTermConfig,
	elapsed_seconds: float
) -> void:
	for building: LongTermConfig.BuildingDef in config.buildings:
		var level := cave.building_level(building.id)
		if level <= 0 or building.key_id.is_empty() or building.key_seconds <= 0.0:
			continue
		var progress: float = expedition.key_remainders.get(building.key_id, 0.0)
		progress += elapsed_seconds * float(level) / building.key_seconds
		var whole := floori(progress)
		if whole > 0:
			expedition.keys[building.key_id] = expedition.key_count(building.key_id) + whole
			progress -= float(whole)
		expedition.key_remainders[building.key_id] = progress


static func _stable_hash(text: String) -> int:
	var value := 2166136261
	for byte: int in text.to_utf8_buffer():
		value = int((value ^ byte) * 16777619) & 0x7fffffff
	return value
