class_name ConfigService
extends RefCounted

const IDLE_PATH := "res://resources/config/idle_rules.json"
const ADVENTURE_PATH := "res://resources/config/adventure.json"
const LONG_TERM_PATH := "res://resources/config/longterm.json"

var idle: IdleConfig
var adventure: AdventureConfig
var long_term: LongTermConfig


func load_all() -> bool:
	idle = IdleConfig.from_resource(IDLE_PATH)
	adventure = AdventureConfig.from_resource(ADVENTURE_PATH)
	long_term = LongTermConfig.from_resource(LONG_TERM_PATH)
	return idle != null and adventure != null and long_term != null


func apply_published(data: Dictionary) -> bool:
	var idle_data: Variant = data.get("idle", {})
	if typeof(idle_data) == TYPE_DICTIONARY and not (idle_data as Dictionary).is_empty():
		var parsed_idle := IdleConfig.from_json(JSON.stringify(idle_data))
		if parsed_idle == null:
			return false
		idle = parsed_idle
	var adventure_data: Variant = data.get("adventure", {})
	if typeof(adventure_data) == TYPE_DICTIONARY and (adventure_data as Dictionary).has("stages"):
		var parsed_adventure := AdventureConfig.from_json(JSON.stringify(adventure_data))
		if parsed_adventure == null:
			return false
		adventure = parsed_adventure
	var longterm_data: Variant = data.get("longterm", {})
	if typeof(longterm_data) == TYPE_DICTIONARY and (longterm_data as Dictionary).has("buildings"):
		var parsed_longterm := LongTermConfig.from_json(JSON.stringify(longterm_data))
		if parsed_longterm == null:
			return false
		long_term = parsed_longterm
	return idle != null and adventure != null and long_term != null


func content_fingerprint() -> String:
	if idle == null or adventure == null or long_term == null:
		return ""
	return "%d:%d:%d:%d:%d:%d" % [
		idle.realms.size(),
		adventure.stages.size(),
		adventure.items.size(),
		adventure.skills.size(),
		long_term.buildings.size(),
		long_term.expeditions.size(),
	]
