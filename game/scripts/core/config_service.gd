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
