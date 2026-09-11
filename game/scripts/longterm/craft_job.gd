class_name CraftJob
extends RefCounted

var recipe_id: String = ""
var remaining_seconds: float = 0.0
var amount: int = 1


static func create(id: String, seconds: float, count: int = 1) -> CraftJob:
	var job := CraftJob.new()
	job.recipe_id = id
	job.remaining_seconds = maxf(seconds, 0.0)
	job.amount = maxi(count, 1)
	return job
