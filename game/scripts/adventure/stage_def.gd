class_name StageDef
extends RefCounted

var id: String
var display_name: String
var order: int
var min_realm_order: int
var min_power: float
var min_attack: float
var min_defense: float
var min_speed: float
var require_skill_mastery: bool
var next_id: String
var monsters: Array[MonsterDef] = []


func preferred_role() -> String:
	var best := 0.0
	var role := ""
	if min_attack > best:
		best = min_attack
		role = SkillRole.ATTACK
	if min_defense > best:
		best = min_defense
		role = SkillRole.BODY
	if min_speed > best:
		role = SkillRole.STEP
	return role


func has_next() -> bool:
	return not next_id.is_empty()
