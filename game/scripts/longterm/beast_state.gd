class_name BeastState
extends RefCounted

var owned_ids: PackedStringArray = []
var active_id: String = ""
var levels: Dictionary[String, int] = {}
var experience: Dictionary[String, int] = {}


func owns(beast_id: String) -> bool:
	return owned_ids.has(beast_id)


func level_of(beast_id: String) -> int:
	return maxi(levels.get(beast_id, 0), 0)


func experience_of(beast_id: String) -> int:
	return maxi(experience.get(beast_id, 0), 0)
