class_name CombatStats
extends RefCounted

var attack: float = 0.0
var defense: float = 0.0
var hp: float = 0.0
var speed: float = 0.0
var interval: float = 1.5
var damage_dealt_scale: float = 1.0
var damage_taken_scale: float = 1.0


func power() -> float:
	return piece_power(attack, defense, speed, hp)


static func piece_power(attack_value: float, defense_value: float, speed_value: float, hp_value: float) -> float:
	return attack_value + defense_value * 0.8 + speed_value * 1.5 + hp_value * 0.04


func add(other: CombatStats) -> void:
	if other == null:
		return
	attack += other.attack
	defense += other.defense
	hp += other.hp
	speed += other.speed


func apply_speed_to_interval() -> void:
	interval = maxf(0.7, interval * 100.0 / (100.0 + maxf(speed, 0.0)))
