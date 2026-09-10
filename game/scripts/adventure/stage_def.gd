class_name StageDef
extends RefCounted

var id: String
var display_name: String
var order: int
var min_realm_order: int
var min_power: float
var next_id: String
var monsters: Array[MonsterDef] = []


func has_next() -> bool:
	return not next_id.is_empty()
