class_name AdventureConfig
extends RefCounted

const CURRENT_SCHEMA_VERSION := 1
const DEFAULT_PATH := "res://resources/config/adventure.json"

var schema_version: int
var inventory_capacity: int
var respawn_seconds: float
var loot_chance_scale: float = 1.0
var realm_bases: Dictionary = {}
var items: Array[ItemDef] = []
var skills: Array[SkillDef] = []
var stages: Array[StageDef] = []


static func from_resource(path: String = DEFAULT_PATH) -> AdventureConfig:
	if not FileAccess.file_exists(path):
		return null
	return from_json(FileAccess.get_file_as_string(path))


static func from_json(text: String) -> AdventureConfig:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	if typeof(parser.data) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = parser.data
	var config := AdventureConfig.new()
	config.schema_version = int(data.get("schema_version", 0))
	config.inventory_capacity = int(data.get("inventory_capacity", 0))
	config.respawn_seconds = float(data.get("respawn_seconds", 0.5))
	config.loot_chance_scale = float(data.get("loot_chance_scale", 1.0))
	var bases: Variant = data.get("realm_bases", {})
	if typeof(bases) != TYPE_DICTIONARY:
		return null
	for realm_id in bases.keys():
		var raw: Variant = bases[realm_id]
		if typeof(raw) != TYPE_DICTIONARY:
			return null
		var stats := _stats_from_dictionary(raw)
		if stats == null:
			return null
		config.realm_bases[str(realm_id)] = stats
	if not _load_items(config, data.get("items", [])):
		return null
	if not _load_skills(config, data.get("skills", [])):
		return null
	if not _load_stages(config, data.get("stages", [])):
		return null
	return config if config.is_valid() else null


func is_valid() -> bool:
	if schema_version != CURRENT_SCHEMA_VERSION:
		return false
	if inventory_capacity < 8 or respawn_seconds <= 0.0:
		return false
	if loot_chance_scale <= 0.0 or loot_chance_scale > 1.0:
		return false
	if items.is_empty() or skills.is_empty() or stages.is_empty() or realm_bases.is_empty():
		return false
	var item_ids: Dictionary = {}
	for item in items:
		if item_ids.has(item.id):
			return false
		item_ids[item.id] = true
	var skill_ids: Dictionary = {}
	for skill in skills:
		if skill_ids.has(skill.id) or not item_ids.has(skill.book_id):
			return false
		skill_ids[skill.id] = true
	var stage_ids: Dictionary = {}
	for index in range(stages.size()):
		var stage: StageDef = stages[index]
		if stage_ids.has(stage.id) or stage.order != index or stage.monsters.is_empty():
			return false
		stage_ids[stage.id] = true
		var is_last := index == stages.size() - 1
		if is_last:
			if stage.has_next():
				return false
		elif stage.next_id != stages[index + 1].id:
			return false
		for monster in stage.monsters:
			for drop in monster.drops:
				if not item_ids.has(str(drop.get("item_id", ""))):
					return false
	return true


func starting_stage() -> StageDef:
	return stages[0] if not stages.is_empty() else null


func stage_by_id(stage_id: String) -> StageDef:
	for stage in stages:
		if stage.id == stage_id:
			return stage
	return null


func next_stage(stage: StageDef) -> StageDef:
	if stage == null or not stage.has_next():
		return null
	return stage_by_id(stage.next_id)


func item_by_id(item_id: String) -> ItemDef:
	for item in items:
		if item.id == item_id:
			return item
	return null


func skill_by_id(skill_id: String) -> SkillDef:
	for skill in skills:
		if skill.id == skill_id:
			return skill
	return null


func realm_stats(realm_id: String) -> CombatStats:
	return realm_bases.get(realm_id, null)


static func _stats_from_dictionary(data: Dictionary) -> CombatStats:
	var stats := CombatStats.new()
	stats.attack = float(data.get("attack", 0.0))
	stats.defense = float(data.get("defense", 0.0))
	stats.hp = float(data.get("hp", 0.0))
	stats.interval = float(data.get("interval", 0.0))
	if stats.attack <= 0.0 or stats.defense < 0.0 or stats.hp <= 0.0 or stats.interval <= 0.0:
		return null
	return stats


static func _load_items(config: AdventureConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var item := ItemDef.new()
		item.id = str(entry.get("id", "")).strip_edges()
		item.display_name = str(entry.get("display_name", "")).strip_edges()
		item.kind = str(entry.get("kind", "")).strip_edges()
		item.quality = str(entry.get("quality", "")).strip_edges()
		item.slot = str(entry.get("slot", "")).strip_edges()
		item.skill_id = str(entry.get("skill_id", "")).strip_edges()
		item.attack = float(entry.get("attack", 0.0))
		item.defense = float(entry.get("defense", 0.0))
		item.hp = float(entry.get("hp", 0.0))
		item.min_realm_order = int(entry.get("min_realm_order", 0))
		item.stackable = bool(entry.get("stackable", item.kind != ItemDef.KIND_EQUIPMENT))
		item.description = str(entry.get("description", "")).strip_edges()
		item.speed = float(entry.get("speed", -1.0))
		if item.speed < 0.0:
			item.speed = ItemDef.default_speed(item.slot, item.min_realm_order) if item.kind == ItemDef.KIND_EQUIPMENT else 0.0
		var raw_affixes: Variant = entry.get("affixes", [])
		if typeof(raw_affixes) == TYPE_ARRAY:
			for affix in raw_affixes:
				var line := str(affix).strip_edges()
				if not line.is_empty():
					item.affixes.append(line)
		if item.affixes.is_empty() and item.kind == ItemDef.KIND_EQUIPMENT:
			item.affixes = ItemDef.default_affixes(item.quality, item.slot)
		if item.id.is_empty() or item.display_name.is_empty():
			return false
		if item.kind == ItemDef.KIND_EQUIPMENT:
			if not EquipSlot.is_valid(item.slot) or not QualityId.is_valid(item.quality):
				return false
		elif item.kind == ItemDef.KIND_SKILL_BOOK:
			if item.skill_id.is_empty() or not QualityId.is_valid(item.quality):
				return false
		elif item.kind == ItemDef.KIND_PILL or item.kind == ItemDef.KIND_MATERIAL:
			if not QualityId.is_valid(item.quality):
				return false
		else:
			return false
		config.items.append(item)
	return true


static func _load_skills(config: AdventureConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var skill := SkillDef.new()
		skill.id = str(entry.get("id", "")).strip_edges()
		skill.display_name = str(entry.get("display_name", "")).strip_edges()
		skill.rank = str(entry.get("rank", "")).strip_edges()
		skill.attack = float(entry.get("attack", 0.0))
		skill.defense = float(entry.get("defense", 0.0))
		skill.hp = float(entry.get("hp", 0.0))
		skill.min_realm_order = int(entry.get("min_realm_order", 0))
		skill.book_id = str(entry.get("book_id", "")).strip_edges()
		if (
			skill.id.is_empty()
			or skill.display_name.is_empty()
			or not SkillRank.is_valid(skill.rank)
			or skill.book_id.is_empty()
		):
			return false
		config.skills.append(skill)
	return true


static func _load_stages(config: AdventureConfig, raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var stage := StageDef.new()
		stage.id = str(entry.get("id", "")).strip_edges()
		stage.display_name = str(entry.get("display_name", "")).strip_edges()
		stage.order = int(entry.get("order", -1))
		stage.min_realm_order = int(entry.get("min_realm_order", 0))
		stage.min_power = float(entry.get("min_power", 0.0))
		stage.min_attack = float(entry.get("min_attack", 0.0))
		stage.min_defense = float(entry.get("min_defense", 0.0))
		stage.min_speed = float(entry.get("min_speed", 0.0))
		stage.next_id = str(entry.get("next_id", "")).strip_edges()
		var monsters: Variant = entry.get("monsters", [])
		if typeof(monsters) != TYPE_ARRAY or stage.id.is_empty() or stage.display_name.is_empty():
			return false
		for monster_data in monsters:
			if typeof(monster_data) != TYPE_DICTIONARY:
				return false
			var monster := MonsterDef.new()
			monster.id = str(monster_data.get("id", "")).strip_edges()
			monster.display_name = str(monster_data.get("display_name", "")).strip_edges()
			monster.attack = float(monster_data.get("attack", 0.0))
			monster.defense = float(monster_data.get("defense", 0.0))
			monster.hp = float(monster_data.get("hp", 0.0))
			monster.interval = float(monster_data.get("interval", 0.0))
			var drops: Variant = monster_data.get("drops", [])
			if (
				monster.id.is_empty()
				or monster.display_name.is_empty()
				or monster.attack <= 0.0
				or monster.hp <= 0.0
				or monster.interval <= 0.0
				or typeof(drops) != TYPE_ARRAY
			):
				return false
			for drop in drops:
				if typeof(drop) != TYPE_DICTIONARY:
					return false
				monster.drops.append(drop)
			stage.monsters.append(monster)
		config.stages.append(stage)
	return true
