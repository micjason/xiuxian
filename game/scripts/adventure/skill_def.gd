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


func to_stats(rank: int = 1) -> CombatStats:
	var scale := 1.4 if rank >= 2 else 1.0
	var stats := CombatStats.new()
	stats.attack = attack * scale
	stats.defense = defense * scale
	stats.hp = hp * scale
	return stats
