class_name SkillDef
extends RefCounted

var id: String
var display_name: String
var rank: String
var attack: float
var defense: float
var hp: float
var min_realm_order: int
var book_id: String


func to_stats() -> CombatStats:
	var stats := CombatStats.new()
	stats.attack = attack
	stats.defense = defense
	stats.hp = hp
	return stats
