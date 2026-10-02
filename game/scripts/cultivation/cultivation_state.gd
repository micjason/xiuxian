class_name CultivationState
extends RefCounted

const DEFAULT_CAPACITY := 100
const DEFAULT_STAGE := "grove"

var cultivation: float = 0.0
var realm_id: String = ""
var last_settled_unix: int = 0
var inventory: Array[ItemStack] = []
var inventory_capacity: int = DEFAULT_CAPACITY
var next_item_uid: int = 0
var equipped: EquipmentLoadout = EquipmentLoadout.new()
var learned_skill_ids: PackedStringArray = []
var skill_ranks: Dictionary = {}
var current_stage_id: String = DEFAULT_STAGE
var unlocked_stage_ids: PackedStringArray = PackedStringArray([DEFAULT_STAGE])
var battle_log: PackedStringArray = []
var loot_seed: int = 1
var combat_remainder: float = 0.0
var settings: GameSettings = GameSettings.new()
var stage_layers: Dictionary = {}
var layer_kills: Dictionary = {}
var qi_pill_until: int = 0
var body_pill_until: int = 0
var running_heart_id: String = ""
var running_art_ids: PackedStringArray = PackedStringArray()
var long_term: LongTermState = LongTermState.new()


func duplicate_state() -> CultivationState:
	var copy := CultivationState.new()
	copy.cultivation = cultivation
	copy.realm_id = realm_id
	copy.last_settled_unix = last_settled_unix
	copy.inventory_capacity = inventory_capacity
	copy.next_item_uid = next_item_uid
	copy.current_stage_id = current_stage_id
	copy.loot_seed = loot_seed
	copy.combat_remainder = combat_remainder
	copy.learned_skill_ids = learned_skill_ids.duplicate()
	copy.skill_ranks = skill_ranks.duplicate()
	copy.unlocked_stage_ids = unlocked_stage_ids.duplicate()
	copy.battle_log = battle_log.duplicate()
	copy.equipped = EquipmentLoadout.from_dictionary(equipped.to_dictionary())
	copy.settings = GameSettings.from_dictionary(settings.to_dictionary())
	copy.stage_layers = stage_layers.duplicate()
	copy.layer_kills = layer_kills.duplicate()
	copy.qi_pill_until = qi_pill_until
	copy.body_pill_until = body_pill_until
	copy.running_heart_id = running_heart_id
	copy.running_art_ids = running_art_ids.duplicate()
	copy.long_term = long_term.duplicate_state() if long_term != null else LongTermState.new()
	for stack in inventory:
		copy.inventory.append(ItemStack.from_dictionary(stack.to_dictionary()))
	return copy


func apply_adventure_defaults(
	adventure: AdventureConfig,
	long_term_config: LongTermConfig = null
) -> void:
	if adventure != null:
		if inventory_capacity < adventure.inventory_capacity:
			inventory_capacity = adventure.inventory_capacity
		var start := adventure.starting_stage()
		if start != null:
			if current_stage_id.is_empty() or adventure.stage_by_id(current_stage_id) == null:
				current_stage_id = start.id
			if unlocked_stage_ids.is_empty():
				unlocked_stage_ids = PackedStringArray([start.id])
	if loot_seed <= 0:
		loot_seed = 1
	if settings == null:
		settings = GameSettings.new()
	if equipped == null:
		equipped = EquipmentLoadout.new()
	if long_term == null:
		long_term = LongTermState.new()
	for skill_id in learned_skill_ids:
		if int(skill_ranks.get(skill_id, 0)) <= 0:
			skill_ranks[skill_id] = 1
	if adventure != null:
		fill_empty_running(adventure)
	if long_term_config != null:
		LongTermRules.initialize(
			long_term_config,
			long_term.economy,
			long_term.cave,
			long_term.craft
		)
		LongTermRules.unlock_sect_recipes(
			long_term.sect,
			long_term.craft,
			long_term_config
		)


func current_layer() -> int:
	return layer_of(current_stage_id)


func layer_of(stage_id: String) -> int:
	return clampi(int(stage_layers.get(stage_id, StageLayer.OUTER)), StageLayer.OUTER, StageLayer.BOSS)


func set_layer(stage_id: String, layer: int) -> void:
	stage_layers[stage_id] = clampi(layer, StageLayer.OUTER, StageLayer.BOSS)


func kills_of(stage_id: String, layer: int) -> int:
	return maxi(int(layer_kills.get("%s|%d" % [stage_id, layer], 0)), 0)


func add_kills(stage_id: String, layer: int, amount: int) -> void:
	if amount <= 0:
		return
	var key := "%s|%d" % [stage_id, layer]
	layer_kills[key] = kills_of(stage_id, layer) + amount


func skill_rank_of(skill_id: String) -> int:
	var stored := int(skill_ranks.get(skill_id, 0))
	if stored > 0:
		return stored
	return 1 if learned_skill_ids.has(skill_id) else 0


func set_skill_rank(skill_id: String, rank: int) -> void:
	skill_ranks[skill_id] = rank
	if rank > 0 and not learned_skill_ids.has(skill_id):
		learned_skill_ids.append(skill_id)


func running_skill_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	if not running_heart_id.is_empty():
		ids.append(running_heart_id)
	for skill_id in running_art_ids:
		if not skill_id.is_empty() and not ids.has(skill_id):
			ids.append(skill_id)
	return ids


func is_running(skill_id: String) -> bool:
	return not skill_id.is_empty() and running_skill_ids().has(skill_id)


func fill_empty_running(adventure: AdventureConfig) -> void:
	if adventure == null:
		return
	if running_heart_id.is_empty():
		for skill_id in learned_skill_ids:
			var skill := adventure.skill_by_id(skill_id)
			if skill != null and skill.is_heart():
				running_heart_id = skill.id
				break
	if running_art_ids.is_empty():
		for skill_id in learned_skill_ids:
			var skill := adventure.skill_by_id(skill_id)
			if skill != null and skill.is_art():
				running_art_ids = PackedStringArray([skill.id])
				break


func sanitize_running(adventure: AdventureConfig, realm_order: int) -> void:
	var heart := adventure.skill_by_id(running_heart_id) if adventure != null else null
	if heart == null or not heart.is_heart() or skill_rank_of(running_heart_id) <= 0:
		running_heart_id = ""
	var kept := PackedStringArray()
	var limit := SkillRole.art_slot_count(realm_order)
	for skill_id in running_art_ids:
		if kept.size() >= limit:
			break
		var skill := adventure.skill_by_id(skill_id) if adventure != null else null
		if skill == null or not skill.is_art() or skill_rank_of(skill_id) <= 0:
			continue
		if kept.has(skill_id):
			continue
		kept.append(skill_id)
	running_art_ids = kept
