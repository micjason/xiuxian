class_name EconomyState
extends RefCounted

var resources: Dictionary[String, float] = {}


func amount(resource_id: String) -> float:
	return maxf(resources.get(resource_id, 0.0), 0.0)


func add(resource_id: String, value: float) -> void:
	if resource_id.is_empty() or value <= 0.0:
		return
	resources[resource_id] = amount(resource_id) + value


func can_spend(costs: Dictionary[String, float]) -> bool:
	for resource_id: String in costs:
		if amount(resource_id) + 0.000001 < costs[resource_id]:
			return false
	return true


func spend(costs: Dictionary[String, float]) -> bool:
	if not can_spend(costs):
		return false
	for resource_id: String in costs:
		resources[resource_id] = amount(resource_id) - costs[resource_id]
	return true
