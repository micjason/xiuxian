class_name ExpeditionState
extends RefCounted

var keys: Dictionary[String, int] = {}
var key_remainders: Dictionary[String, float] = {}
var clear_counts: Dictionary[String, int] = {}
var encounter_index: int = 0
var auto_expedition_id: String = ""
var commission_remainder: float = 0.0


func key_count(key_id: String) -> int:
	return maxi(keys.get(key_id, 0), 0)


func clear_count(expedition_id: String) -> int:
	return maxi(clear_counts.get(expedition_id, 0), 0)


func total_clears() -> int:
	var total := 0
	for expedition_id: String in clear_counts:
		total += maxi(clear_counts[expedition_id], 0)
	return total
