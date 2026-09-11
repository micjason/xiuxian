class_name SkillDef
extends RefCounted

var id: String
var display_name: String
var rank: String
var role: String
var attack: float
var defense: float
var hp: float
var speed: float
var cultivate_bonus: float
var min_realm_order: int
var book_id: String


func is_heart() -> bool:
	return SkillRole.is_heart(role)


func is_art() -> bool:
	return SkillRole.is_art(role)


func to_stats(mastery: int = 1) -> CombatStats:
	var scale := 1.4 if mastery >= 2 else 1.0
	var stats := CombatStats.new()
	stats.attack = attack * scale
	stats.defense = defense * scale
	stats.hp = hp * scale
	stats.speed = speed * scale
	return stats


func cultivate_factor(mastery: int = 1) -> float:
	if cultivate_bonus <= 0.0:
		return 1.0
	var addend := cultivate_bonus * (1.5 if mastery >= 2 else 1.0)
	return 1.0 + addend
