class_name MonsterDef
extends RefCounted

var id: String
var display_name: String
var attack: float
var defense: float
var hp: float
var interval: float
var drops: Array[Dictionary] = []


func to_stats() -> CombatStats:
	var stats := CombatStats.new()
	stats.attack = attack
	stats.defense = defense
	stats.hp = hp
	stats.interval = interval
	return stats
