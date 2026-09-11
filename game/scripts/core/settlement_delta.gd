class_name SettlementDelta
extends RefCounted

var applied_seconds: int = 0
var cultivation_gain: float = 0.0
var combat_kills: int = 0
var combat_retreated: bool = false
var combat_loot: PackedStringArray = PackedStringArray()
var bag_skipped: int = 0
var resources: Dictionary = {}
var completed_jobs: PackedStringArray = PackedStringArray()
var messages: PackedStringArray = PackedStringArray()


func add_resource(resource_id: String, amount: float) -> void:
	if resource_id.is_empty() or amount <= 0.0:
		return
	resources[resource_id] = float(resources.get(resource_id, 0.0)) + amount


func merge(other: SettlementDelta) -> void:
	if other == null:
		return
	applied_seconds = maxi(applied_seconds, other.applied_seconds)
	cultivation_gain += other.cultivation_gain
	combat_kills += other.combat_kills
	combat_retreated = combat_retreated or other.combat_retreated
	for loot in other.combat_loot:
		combat_loot.append(loot)
	bag_skipped += other.bag_skipped
	for resource_id in other.resources.keys():
		add_resource(str(resource_id), float(other.resources[resource_id]))
	for job_id in other.completed_jobs:
		completed_jobs.append(job_id)
	for message in other.messages:
		messages.append(message)
