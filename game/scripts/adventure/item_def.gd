class_name ItemDef
extends RefCounted

const KIND_EQUIPMENT := "equipment"
const KIND_SKILL_BOOK := "skill_book"

var id: String
var display_name: String
var kind: String
var quality: String
var slot: String
var skill_id: String
var attack: float
var defense: float
var hp: float
var min_realm_order: int
var stackable: bool


func is_equipment() -> bool:
	return kind == KIND_EQUIPMENT


func is_skill_book() -> bool:
	return kind == KIND_SKILL_BOOK


func to_stats() -> CombatStats:
	var stats := CombatStats.new()
	stats.attack = attack
	stats.defense = defense
	stats.hp = hp
	return stats
