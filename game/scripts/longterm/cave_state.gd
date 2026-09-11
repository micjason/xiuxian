class_name CaveState
extends RefCounted

var labor_total: int = 4
var labor: Dictionary[String, int] = {}
var building_levels: Dictionary[String, int] = {}
var production_remainder: Dictionary[String, float] = {}


func assigned_labor() -> int:
	var total := 0
	for resource_id: String in labor:
		total += maxi(labor[resource_id], 0)
	return total


func building_level(building_id: String) -> int:
	return maxi(building_levels.get(building_id, 0), 0)
