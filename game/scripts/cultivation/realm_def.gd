class_name RealmDef
extends RefCounted

var id: String
var display_name: String
var order: int
var gain_per_second: float
var breakthrough_cost: float
var next_id: String


func has_next() -> bool:
	return not next_id.is_empty()
