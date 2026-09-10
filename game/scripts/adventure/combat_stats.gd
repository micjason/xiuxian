class_name CombatStats
extends RefCounted

var attack: float = 0.0
var defense: float = 0.0
var hp: float = 0.0
var interval: float = 1.5


func power() -> float:
	return attack + defense * 0.8 + hp * 0.04


func add(other: CombatStats) -> void:
	if other == null:
		return
	attack += other.attack
	defense += other.defense
	hp += other.hp
