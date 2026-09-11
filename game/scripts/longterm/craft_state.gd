class_name CraftState
extends RefCounted

var queue: Array[CraftJob] = []
var completed_jobs: int = 0
var unlocked_recipe_ids: PackedStringArray = []
var research_attempts: Dictionary[String, int] = {}


func has_recipe(recipe_id: String) -> bool:
	return unlocked_recipe_ids.has(recipe_id)
