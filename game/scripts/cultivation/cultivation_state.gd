class_name CultivationState
extends RefCounted

const DEFAULT_CAPACITY := 36
const DEFAULT_STAGE := "grove"

var cultivation: float = 0.0
var realm_id: String = ""
var last_settled_unix: int = 0
var inventory: Array[ItemStack] = []
var inventory_capacity: int = DEFAULT_CAPACITY
var next_item_uid: int = 0
var equipped: EquipmentLoadout = EquipmentLoadout.new()
var learned_skill_ids: PackedStringArray = []
var current_stage_id: String = DEFAULT_STAGE
var unlocked_stage_ids: PackedStringArray = PackedStringArray([DEFAULT_STAGE])
var battle_log: PackedStringArray = []
var loot_seed: int = 1
var combat_remainder: float = 0.0
var settings: GameSettings = GameSettings.new()


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
	copy.unlocked_stage_ids = unlocked_stage_ids.duplicate()
	copy.battle_log = battle_log.duplicate()
	copy.equipped = EquipmentLoadout.from_dictionary(equipped.to_dictionary())
	copy.settings = GameSettings.from_dictionary(settings.to_dictionary())
	for stack in inventory:
		copy.inventory.append(ItemStack.from_dictionary(stack.to_dictionary()))
	return copy


func apply_adventure_defaults(adventure: AdventureConfig) -> void:
	if adventure != null:
		if inventory_capacity <= 0:
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
