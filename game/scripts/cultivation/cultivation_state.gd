class_name CultivationState
extends RefCounted

var cultivation: float = 0.0
var realm_id: String = ""
var last_settled_unix: int = 0


func duplicate_state() -> CultivationState:
	var copy := CultivationState.new()
	copy.cultivation = cultivation
	copy.realm_id = realm_id
	copy.last_settled_unix = last_settled_unix
	return copy
