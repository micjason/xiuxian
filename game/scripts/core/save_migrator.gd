class_name SaveMigrator
extends RefCounted

const CURRENT_SCHEMA_VERSION := 5


static func migrate(payload: Dictionary, from_schema: int) -> Dictionary:
	if from_schema < 1 or from_schema > CURRENT_SCHEMA_VERSION:
		return {}
	var migrated := payload.duplicate(true)
	var schema := from_schema
	while schema < CURRENT_SCHEMA_VERSION:
		match schema:
			1:
				migrated = _v1_to_v2(migrated)
			2:
				migrated = _v2_to_v3(migrated)
			3:
				migrated = _v3_to_v4(migrated)
			4:
				migrated = _v4_to_v5(migrated)
			_:
				return {}
		schema += 1
	return migrated


static func _v1_to_v2(payload: Dictionary) -> Dictionary:
	var result := payload.duplicate(true)
	result["inventory"] = []
	result["inventory_capacity"] = CultivationState.DEFAULT_CAPACITY
	result["next_item_uid"] = 0
	result["equipped"] = EquipmentLoadout.new().to_dictionary()
	result["learned_skill_ids"] = []
	result["current_stage_id"] = CultivationState.DEFAULT_STAGE
	result["unlocked_stage_ids"] = [CultivationState.DEFAULT_STAGE]
	result["battle_log"] = []
	result["loot_seed"] = 1
	result["combat_remainder"] = 0.0
	result["settings"] = GameSettings.new().to_dictionary()
	return result


static func _v2_to_v3(payload: Dictionary) -> Dictionary:
	var result := payload.duplicate(true)
	var ranks: Dictionary = {}
	for skill_id in result.get("learned_skill_ids", []):
		ranks[str(skill_id)] = 1
	result["skill_ranks"] = ranks
	result["stage_layers"] = {}
	result["layer_kills"] = {}
	result["qi_pill_until"] = 0
	result["body_pill_until"] = 0
	var inventory: Array = result.get("inventory", [])
	for entry in inventory:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		entry["merge_level"] = 0
		entry["tempered"] = false
	return result


static func _v3_to_v4(payload: Dictionary) -> Dictionary:
	var result := payload.duplicate(true)
	result["running_heart_id"] = ""
	result["running_art_ids"] = []
	return result


static func _v4_to_v5(payload: Dictionary) -> Dictionary:
	var result := payload.duplicate(true)
	result["long_term"] = {}
	return result
