class_name SectState
extends RefCounted

var sect_id: String = ""
var contribution: int = 0
var position_id: String = ""
var joined_npc_ids: PackedStringArray = []


func has_joined() -> bool:
	return not sect_id.is_empty()


func has_npc(npc_id: String) -> bool:
	return joined_npc_ids.has(npc_id)
