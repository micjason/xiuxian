class_name LongTermConfig
extends RefCounted

const CURRENT_SCHEMA_VERSION := 1
const DEFAULT_PATH := "res://resources/config/longterm.json"


class BuildingDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var max_level: int = 0
	var labor_bonus: int = 0
	var key_id: String = ""
	var key_seconds: float = 0.0
	var cultivate_bonus_per_level: float = 0.0
	var costs: Dictionary[String, float] = {}
	var production_bonus: Dictionary[String, float] = {}


class SectDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var join_building_id: String = ""
	var join_building_level: int = 0


class NpcDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var contribution_required: int = 0
	var labor_bonus: int = 0
	var craft_speed_bonus: float = 0.0
	var expedition_power: int = 0


class PositionDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var contribution_required: int = 0
	var production_bonus: float = 0.0
	var cultivate_bonus: float = 0.0
	var expedition_power: int = 0


class RecipeDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var category: String = ""
	var unlock_npc_id: String = ""
	var research_chance: float = 0.0
	var research_pity: int = 0
	var research_costs: Dictionary[String, float] = {}
	var duration_seconds: float = 0.0
	var inputs: Dictionary[String, float] = {}
	var outputs: Dictionary[String, float] = {}
	var salvage: Dictionary[String, float] = {}


class EncounterDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var weight: int = 0
	var rewards: Dictionary[String, float] = {}
	var contribution: int = 0


class ExpeditionDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var key_id: String = ""
	var required_power: int = 0
	var commission_seconds: float = 0.0
	var rewards: Dictionary[String, float] = {}
	var contribution: int = 0
	var encounters: Array[EncounterDef] = []


class BeastDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var claim_expedition_id: String = ""
	var claim_clear_count: int = 0
	var feed_resource_id: String = ""
	var feed_amount: float = 0.0
	var feed_experience: int = 0
	var base_level_cost: int = 0
	var cave_bonus_per_level: float = 0.0
	var expedition_power_per_level: int = 0
	var attack_per_level: float = 0.0
	var defense_per_level: float = 0.0
	var hp_per_level: float = 0.0
	var speed_per_level: float = 0.0


class AscensionDef:
	extends RefCounted
	var min_realm_order: int = 0
	var min_run_seconds: int = 0
	var building_id: String = ""
	var building_level: int = 0
	var contribution: int = 0
	var completed_jobs: int = 0
	var expedition_clears: int = 0
	var beast_level: int = 0
	var costs: Dictionary[String, float] = {}
	var legacy_points: int = 0
	var labor_reward: int = 0
	var key_reward: int = 0
	var cultivate_bonus_per_legacy: float = 0.0


class OutpostDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var max_level: int = 0
	var costs: Dictionary[String, float] = {}
	var cultivate_bonus_per_level: float = 0.0
	var labor_bonus_per_level: int = 0


class EndingDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var ascension_count: int = 0
	var legacy_points: int = 0
	var outpost_levels: int = 0


var schema_version: int = 0
var queue_limit: int = 0
var resource_names: Dictionary[String, String] = {}
var cave_rates: Dictionary[String, float] = {}
var buildings: Array[BuildingDef] = []
var sects: Array[SectDef] = []
var npcs: Array[NpcDef] = []
var positions: Array[PositionDef] = []
var recipes: Array[RecipeDef] = []
var expeditions: Array[ExpeditionDef] = []
var beasts: Array[BeastDef] = []
var ascension: AscensionDef = null
var outposts: Array[OutpostDef] = []
var endings: Array[EndingDef] = []


static func from_resource(path: String = DEFAULT_PATH) -> LongTermConfig:
	if not FileAccess.file_exists(path):
		return null
	return from_json(FileAccess.get_file_as_string(path))


static func from_json(text: String) -> LongTermConfig:
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = parser.data
	var config := LongTermConfig.new()
	config.schema_version = int(data.get("schema_version", 0))
	config.queue_limit = int(data.get("queue_limit", 0))
	config.resource_names = _string_map(data.get("resources", {}))
	config.cave_rates = _float_map(data.get("cave_rates", {}))
	if (
		not _load_buildings(config, data.get("buildings", []))
		or not _load_sects(config, data.get("sects", []))
		or not _load_npcs(config, data.get("npcs", []))
		or not _load_positions(config, data.get("positions", []))
		or not _load_recipes(config, data.get("recipes", []))
		or not _load_expeditions(config, data.get("expeditions", []))
		or not _load_beasts(config, data.get("beasts", []))
		or not _load_outposts(config, data.get("outposts", []))
		or not _load_endings(config, data.get("endings", []))
	):
		return null
	var ascension_data: Variant = data.get("ascension", {})
	if typeof(ascension_data) != TYPE_DICTIONARY:
		return null
	config.ascension = _parse_ascension(ascension_data)
	return config if config.is_valid() else null


func is_valid() -> bool:
	if (
		schema_version != CURRENT_SCHEMA_VERSION
		or queue_limit <= 0
		or resource_names.size() < 4
		or cave_rates.size() != 4
		or buildings.is_empty()
		or sects.is_empty()
		or npcs.is_empty()
		or positions.is_empty()
		or recipes.is_empty()
		or expeditions.is_empty()
		or beasts.is_empty()
		or ascension == null
		or outposts.is_empty()
		or endings.is_empty()
	):
		return false
	for resource_id: String in cave_rates:
		if not resource_names.has(resource_id) or cave_rates[resource_id] <= 0.0:
			return false
	for building: BuildingDef in buildings:
		if building.id.is_empty() or building.max_level <= 0 or not _known_costs(building.costs):
			return false
	for recipe: RecipeDef in recipes:
		if (
			recipe.id.is_empty()
			or recipe.duration_seconds <= 0.0
			or recipe.inputs.is_empty()
			or recipe.outputs.is_empty()
			or not _known_costs(recipe.inputs)
			or not _known_costs(recipe.outputs)
			or not _known_costs(recipe.salvage)
			or not _known_costs(recipe.research_costs)
			or recipe.research_chance < 0.0
			or recipe.research_chance > 1.0
			or recipe.research_pity < 0
			or (
				not recipe.unlock_npc_id.is_empty()
				and npc_by_id(recipe.unlock_npc_id) == null
			)
		):
			return false
	for expedition: ExpeditionDef in expeditions:
		if (
			expedition.id.is_empty()
			or expedition.key_id.is_empty()
			or expedition.commission_seconds <= 0.0
			or expedition.encounters.is_empty()
		):
			return false
		for encounter: EncounterDef in expedition.encounters:
			if encounter.id.is_empty() or encounter.weight <= 0 or not _known_costs(encounter.rewards):
				return false
	for beast: BeastDef in beasts:
		if (
			beast.id.is_empty()
			or expedition_by_id(beast.claim_expedition_id) == null
			or not resource_names.has(beast.feed_resource_id)
			or beast.feed_amount <= 0.0
			or beast.feed_experience <= 0
		):
			return false
	for outpost in outposts:
		if outpost.id.is_empty() or outpost.max_level <= 0 or not _known_costs(outpost.costs):
			return false
	for ending in endings:
		if (
			ending.id.is_empty()
			or ending.ascension_count <= 0
			or ending.legacy_points <= 0
			or ending.outpost_levels <= 0
		):
			return false
	return (
		building_by_id(ascension.building_id) != null
		and ascension.building_level > 0
		and ascension.min_run_seconds > 0
		and ascension.legacy_points > 0
		and _known_costs(ascension.costs)
	)


func building_by_id(id: String) -> BuildingDef:
	for definition: BuildingDef in buildings:
		if definition.id == id:
			return definition
	return null


func sect_by_id(id: String) -> SectDef:
	for definition: SectDef in sects:
		if definition.id == id:
			return definition
	return null


func npc_by_id(id: String) -> NpcDef:
	for definition: NpcDef in npcs:
		if definition.id == id:
			return definition
	return null


func position_by_id(id: String) -> PositionDef:
	for definition: PositionDef in positions:
		if definition.id == id:
			return definition
	return null


func recipe_by_id(id: String) -> RecipeDef:
	for definition: RecipeDef in recipes:
		if definition.id == id:
			return definition
	return null


func expedition_by_id(id: String) -> ExpeditionDef:
	for definition: ExpeditionDef in expeditions:
		if definition.id == id:
			return definition
	return null


func beast_by_id(id: String) -> BeastDef:
	for definition: BeastDef in beasts:
		if definition.id == id:
			return definition
	return null


func outpost_by_id(id: String) -> OutpostDef:
	for definition in outposts:
		if definition.id == id:
			return definition
	return null


func ending_by_id(id: String) -> EndingDef:
	for definition in endings:
		if definition.id == id:
			return definition
	return null


func _known_costs(values: Dictionary[String, float]) -> bool:
	for resource_id: String in values:
		if not resource_names.has(resource_id) or values[resource_id] < 0.0:
			return false
	return true


static func _load_buildings(config: LongTermConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var definition := BuildingDef.new()
		definition.id = str(entry.get("id", "")).strip_edges()
		definition.display_name = str(entry.get("display_name", "")).strip_edges()
		definition.max_level = int(entry.get("max_level", 0))
		definition.labor_bonus = int(entry.get("labor_bonus", 0))
		definition.key_id = str(entry.get("key_id", "")).strip_edges()
		definition.key_seconds = float(entry.get("key_seconds", 0.0))
		definition.cultivate_bonus_per_level = float(
			entry.get("cultivate_bonus_per_level", 0.0)
		)
		definition.costs = _float_map(entry.get("costs", {}))
		definition.production_bonus = _float_map(entry.get("production_bonus", {}))
		config.buildings.append(definition)
	return true


static func _load_sects(config: LongTermConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var definition := SectDef.new()
		definition.id = str(entry.get("id", "")).strip_edges()
		definition.display_name = str(entry.get("display_name", "")).strip_edges()
		definition.join_building_id = str(entry.get("join_building_id", "")).strip_edges()
		definition.join_building_level = int(entry.get("join_building_level", 0))
		config.sects.append(definition)
	return true


static func _load_npcs(config: LongTermConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var definition := NpcDef.new()
		definition.id = str(entry.get("id", "")).strip_edges()
		definition.display_name = str(entry.get("display_name", "")).strip_edges()
		definition.contribution_required = int(entry.get("contribution_required", 0))
		definition.labor_bonus = int(entry.get("labor_bonus", 0))
		definition.craft_speed_bonus = float(entry.get("craft_speed_bonus", 0.0))
		definition.expedition_power = int(entry.get("expedition_power", 0))
		config.npcs.append(definition)
	return true


static func _load_positions(config: LongTermConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var definition := PositionDef.new()
		definition.id = str(entry.get("id", "")).strip_edges()
		definition.display_name = str(entry.get("display_name", "")).strip_edges()
		definition.contribution_required = int(entry.get("contribution_required", 0))
		definition.production_bonus = float(entry.get("production_bonus", 0.0))
		definition.cultivate_bonus = float(entry.get("cultivate_bonus", 0.0))
		definition.expedition_power = int(entry.get("expedition_power", 0))
		config.positions.append(definition)
	return true


static func _load_recipes(config: LongTermConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var definition := RecipeDef.new()
		definition.id = str(entry.get("id", "")).strip_edges()
		definition.display_name = str(entry.get("display_name", "")).strip_edges()
		definition.category = str(entry.get("category", "")).strip_edges()
		definition.unlock_npc_id = str(entry.get("unlock_npc_id", "")).strip_edges()
		definition.research_chance = float(entry.get("research_chance", 0.0))
		definition.research_pity = int(entry.get("research_pity", 0))
		definition.research_costs = _float_map(entry.get("research_costs", {}))
		definition.duration_seconds = float(entry.get("duration_seconds", 0.0))
		definition.inputs = _float_map(entry.get("inputs", {}))
		definition.outputs = _float_map(entry.get("outputs", {}))
		definition.salvage = _float_map(entry.get("salvage", {}))
		config.recipes.append(definition)
	return true


static func _load_expeditions(config: LongTermConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var definition := ExpeditionDef.new()
		definition.id = str(entry.get("id", "")).strip_edges()
		definition.display_name = str(entry.get("display_name", "")).strip_edges()
		definition.key_id = str(entry.get("key_id", "")).strip_edges()
		definition.required_power = int(entry.get("required_power", 0))
		definition.commission_seconds = float(entry.get("commission_seconds", 0.0))
		definition.rewards = _float_map(entry.get("rewards", {}))
		definition.contribution = int(entry.get("contribution", 0))
		var encounters: Variant = entry.get("encounters", [])
		if typeof(encounters) != TYPE_ARRAY:
			return false
		for encounter_data: Variant in encounters:
			if typeof(encounter_data) != TYPE_DICTIONARY:
				return false
			var encounter := EncounterDef.new()
			encounter.id = str(encounter_data.get("id", "")).strip_edges()
			encounter.display_name = str(encounter_data.get("display_name", "")).strip_edges()
			encounter.weight = int(encounter_data.get("weight", 0))
			encounter.rewards = _float_map(encounter_data.get("rewards", {}))
			encounter.contribution = int(encounter_data.get("contribution", 0))
			definition.encounters.append(encounter)
		config.expeditions.append(definition)
	return true


static func _load_beasts(config: LongTermConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var definition := BeastDef.new()
		definition.id = str(entry.get("id", "")).strip_edges()
		definition.display_name = str(entry.get("display_name", "")).strip_edges()
		definition.claim_expedition_id = str(entry.get("claim_expedition_id", "")).strip_edges()
		definition.claim_clear_count = int(entry.get("claim_clear_count", 0))
		definition.feed_resource_id = str(entry.get("feed_resource_id", "")).strip_edges()
		definition.feed_amount = float(entry.get("feed_amount", 0.0))
		definition.feed_experience = int(entry.get("feed_experience", 0))
		definition.base_level_cost = int(entry.get("base_level_cost", 0))
		definition.cave_bonus_per_level = float(entry.get("cave_bonus_per_level", 0.0))
		definition.expedition_power_per_level = int(entry.get("expedition_power_per_level", 0))
		definition.attack_per_level = float(entry.get("attack_per_level", 0.0))
		definition.defense_per_level = float(entry.get("defense_per_level", 0.0))
		definition.hp_per_level = float(entry.get("hp_per_level", 0.0))
		definition.speed_per_level = float(entry.get("speed_per_level", 0.0))
		config.beasts.append(definition)
	return true


static func _parse_ascension(entry: Dictionary) -> AscensionDef:
	var definition := AscensionDef.new()
	definition.min_realm_order = int(entry.get("min_realm_order", 0))
	definition.min_run_seconds = int(entry.get("min_run_seconds", 0))
	definition.building_id = str(entry.get("building_id", "")).strip_edges()
	definition.building_level = int(entry.get("building_level", 0))
	definition.contribution = int(entry.get("contribution", 0))
	definition.completed_jobs = int(entry.get("completed_jobs", 0))
	definition.expedition_clears = int(entry.get("expedition_clears", 0))
	definition.beast_level = int(entry.get("beast_level", 0))
	definition.costs = _float_map(entry.get("costs", {}))
	definition.legacy_points = int(entry.get("legacy_points", 0))
	definition.labor_reward = int(entry.get("labor_reward", 0))
	definition.key_reward = int(entry.get("key_reward", 0))
	definition.cultivate_bonus_per_legacy = float(
		entry.get("cultivate_bonus_per_legacy", 0.0)
	)
	return definition


static func _load_outposts(config: LongTermConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var definition := OutpostDef.new()
		definition.id = str(entry.get("id", "")).strip_edges()
		definition.display_name = str(entry.get("display_name", "")).strip_edges()
		definition.max_level = int(entry.get("max_level", 0))
		definition.costs = _float_map(entry.get("costs", {}))
		definition.cultivate_bonus_per_level = float(
			entry.get("cultivate_bonus_per_level", 0.0)
		)
		definition.labor_bonus_per_level = int(entry.get("labor_bonus_per_level", 0))
		config.outposts.append(definition)
	return true


static func _load_endings(config: LongTermConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var definition := EndingDef.new()
		definition.id = str(entry.get("id", "")).strip_edges()
		definition.display_name = str(entry.get("display_name", "")).strip_edges()
		definition.ascension_count = int(entry.get("ascension_count", 0))
		definition.legacy_points = int(entry.get("legacy_points", 0))
		definition.outpost_levels = int(entry.get("outpost_levels", 0))
		config.endings.append(definition)
	return true


static func _float_map(raw: Variant) -> Dictionary[String, float]:
	var result: Dictionary[String, float] = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	for key: Variant in raw:
		result[str(key)] = float(raw[key])
	return result


static func _string_map(raw: Variant) -> Dictionary[String, String]:
	var result: Dictionary[String, String] = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	for key: Variant in raw:
		result[str(key)] = str(raw[key]).strip_edges()
	return result
