class_name LongTermState
extends RefCounted

var economy := EconomyState.new()
var cave := CaveState.new()
var sect := SectState.new()
var craft := CraftState.new()
var beast := BeastState.new()
var expedition := ExpeditionState.new()
var ascension := AscensionState.new()
var lifetime_seconds: int = 0
var run_seconds: int = 0
var last_summary: PackedStringArray = PackedStringArray()


func duplicate_state() -> LongTermState:
	return from_dictionary(to_dictionary())


func to_dictionary() -> Dictionary:
	var jobs: Array = []
	for job in craft.queue:
		jobs.append({
			"recipe_id": job.recipe_id,
			"remaining_seconds": job.remaining_seconds,
			"amount": job.amount,
		})
	return {
		"economy": {"resources": economy.resources.duplicate()},
		"cave": {
			"labor_total": cave.labor_total,
			"labor": cave.labor.duplicate(),
			"building_levels": cave.building_levels.duplicate(),
			"production_remainder": cave.production_remainder.duplicate(),
		},
		"sect": {
			"sect_id": sect.sect_id,
			"contribution": sect.contribution,
			"position_id": sect.position_id,
			"joined_npc_ids": Array(sect.joined_npc_ids),
		},
		"craft": {
			"queue": jobs,
			"completed_jobs": craft.completed_jobs,
			"unlocked_recipe_ids": Array(craft.unlocked_recipe_ids),
			"research_attempts": craft.research_attempts.duplicate(),
		},
		"beast": {
			"owned_ids": Array(beast.owned_ids),
			"active_id": beast.active_id,
			"levels": beast.levels.duplicate(),
			"experience": beast.experience.duplicate(),
		},
		"expedition": {
			"keys": expedition.keys.duplicate(),
			"key_remainders": expedition.key_remainders.duplicate(),
			"clear_counts": expedition.clear_counts.duplicate(),
			"encounter_index": expedition.encounter_index,
			"auto_expedition_id": expedition.auto_expedition_id,
			"commission_remainder": expedition.commission_remainder,
		},
		"ascension": {
			"ascension_count": ascension.ascension_count,
			"legacy_points": ascension.legacy_points,
			"inherited_labor": ascension.inherited_labor,
			"inherited_key_charges": ascension.inherited_key_charges,
			"unlocked_legacy_ids": Array(ascension.unlocked_legacy_ids),
			"outpost_levels": ascension.outpost_levels.duplicate(),
			"completed_ending_ids": Array(ascension.completed_ending_ids),
		},
		"lifetime_seconds": lifetime_seconds,
		"run_seconds": run_seconds,
		"last_summary": Array(last_summary),
	}


static func from_dictionary(raw: Variant) -> LongTermState:
	var state := LongTermState.new()
	if typeof(raw) != TYPE_DICTIONARY:
		return state
	var data: Dictionary = raw
	var economy_data := _dictionary(data.get("economy", {}))
	state.economy.resources = _float_dictionary(economy_data.get("resources", {}))
	var cave_data := _dictionary(data.get("cave", {}))
	state.cave.labor_total = maxi(int(cave_data.get("labor_total", 4)), 1)
	state.cave.labor = _int_dictionary(cave_data.get("labor", {}))
	state.cave.building_levels = _int_dictionary(cave_data.get("building_levels", {}))
	state.cave.production_remainder = _float_dictionary(cave_data.get("production_remainder", {}))
	var sect_data := _dictionary(data.get("sect", {}))
	state.sect.sect_id = str(sect_data.get("sect_id", "")).strip_edges()
	state.sect.contribution = maxi(int(sect_data.get("contribution", 0)), 0)
	state.sect.position_id = str(sect_data.get("position_id", "")).strip_edges()
	state.sect.joined_npc_ids = _string_array(sect_data.get("joined_npc_ids", []))
	var craft_data := _dictionary(data.get("craft", {}))
	state.craft.completed_jobs = maxi(int(craft_data.get("completed_jobs", 0)), 0)
	state.craft.unlocked_recipe_ids = _string_array(craft_data.get("unlocked_recipe_ids", []))
	state.craft.research_attempts = _int_dictionary(
		craft_data.get("research_attempts", {})
	)
	var raw_jobs: Variant = craft_data.get("queue", [])
	if typeof(raw_jobs) == TYPE_ARRAY:
		for raw_job in raw_jobs:
			if typeof(raw_job) != TYPE_DICTIONARY:
				continue
			var recipe_id := str(raw_job.get("recipe_id", "")).strip_edges()
			if recipe_id.is_empty():
				continue
			state.craft.queue.append(CraftJob.create(
				recipe_id,
				maxf(float(raw_job.get("remaining_seconds", 0.0)), 0.0),
				maxi(int(raw_job.get("amount", 1)), 1)
			))
	var beast_data := _dictionary(data.get("beast", {}))
	state.beast.owned_ids = _string_array(beast_data.get("owned_ids", []))
	state.beast.active_id = str(beast_data.get("active_id", "")).strip_edges()
	state.beast.levels = _int_dictionary(beast_data.get("levels", {}))
	state.beast.experience = _int_dictionary(beast_data.get("experience", {}))
	var expedition_data := _dictionary(data.get("expedition", {}))
	state.expedition.keys = _int_dictionary(expedition_data.get("keys", {}))
	state.expedition.key_remainders = _float_dictionary(expedition_data.get("key_remainders", {}))
	state.expedition.clear_counts = _int_dictionary(expedition_data.get("clear_counts", {}))
	state.expedition.encounter_index = maxi(int(expedition_data.get("encounter_index", 0)), 0)
	state.expedition.auto_expedition_id = str(
		expedition_data.get("auto_expedition_id", "")
	).strip_edges()
	state.expedition.commission_remainder = maxf(
		float(expedition_data.get("commission_remainder", 0.0)),
		0.0
	)
	var ascension_data := _dictionary(data.get("ascension", {}))
	state.ascension.ascension_count = maxi(int(ascension_data.get("ascension_count", 0)), 0)
	state.ascension.legacy_points = maxi(int(ascension_data.get("legacy_points", 0)), 0)
	state.ascension.inherited_labor = maxi(int(ascension_data.get("inherited_labor", 0)), 0)
	state.ascension.inherited_key_charges = maxi(
		int(ascension_data.get("inherited_key_charges", 0)),
		0
	)
	state.ascension.unlocked_legacy_ids = _string_array(
		ascension_data.get("unlocked_legacy_ids", [])
	)
	state.ascension.outpost_levels = _int_dictionary(
		ascension_data.get("outpost_levels", {})
	)
	state.ascension.completed_ending_ids = _string_array(
		ascension_data.get("completed_ending_ids", [])
	)
	state.lifetime_seconds = maxi(int(data.get("lifetime_seconds", 0)), 0)
	state.run_seconds = maxi(int(data.get("run_seconds", 0)), 0)
	state.last_summary = _string_array(data.get("last_summary", []))
	return state


static func _dictionary(raw: Variant) -> Dictionary:
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


static func _int_dictionary(raw: Variant) -> Dictionary[String, int]:
	var result: Dictionary[String, int] = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	for key in raw.keys():
		result[str(key)] = maxi(int(raw[key]), 0)
	return result


static func _float_dictionary(raw: Variant) -> Dictionary[String, float]:
	var result: Dictionary[String, float] = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	for key in raw.keys():
		result[str(key)] = maxf(float(raw[key]), 0.0)
	return result


static func _string_array(raw: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if typeof(raw) != TYPE_ARRAY:
		return result
	for value in raw:
		var text := str(value).strip_edges()
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result
