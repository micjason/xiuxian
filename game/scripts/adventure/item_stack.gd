class_name ItemStack
extends RefCounted

const MAX_MERGE := 5

var uid: int = 0
var item_id: String = ""
var count: int = 1
var locked: bool = false
var merge_level: int = 0
var tempered: bool = false


func to_dictionary() -> Dictionary:
	return {
		"uid": uid,
		"item_id": item_id,
		"count": count,
		"locked": locked,
		"merge_level": merge_level,
		"tempered": tempered,
	}


static func from_dictionary(data: Dictionary) -> ItemStack:
	var stack := ItemStack.new()
	stack.uid = int(data.get("uid", 0))
	stack.item_id = str(data.get("item_id", "")).strip_edges()
	stack.count = int(data.get("count", 0))
	stack.locked = bool(data.get("locked", false))
	stack.merge_level = clampi(int(data.get("merge_level", 0)), 0, MAX_MERGE)
	stack.tempered = bool(data.get("tempered", false))
	if stack.uid <= 0 or stack.item_id.is_empty() or stack.count <= 0:
		return null
	return stack
