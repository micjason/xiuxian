class_name IdleConfig
extends RefCounted

const CURRENT_SCHEMA_VERSION := 1

var schema_version: int
var offline_cap_seconds: int
var realms: Array[RealmDef] = []


static func from_json(text: String) -> IdleConfig:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	if typeof(parser.data) != TYPE_DICTIONARY:
		return null

	var data: Dictionary = parser.data
	var config := IdleConfig.new()
	config.schema_version = int(data.get("schema_version", 0))
	config.offline_cap_seconds = int(data.get("offline_cap_seconds", 0))
	var raw_realms: Variant = data.get("realms", [])
	if typeof(raw_realms) != TYPE_ARRAY:
		return null

	for item in raw_realms:
		if typeof(item) != TYPE_DICTIONARY:
			return null
		var realm := _realm_from_dictionary(item)
		if realm == null:
			return null
		config.realms.append(realm)

	config.realms.sort_custom(func(left: RealmDef, right: RealmDef) -> bool:
		return left.order < right.order
	)
	return config if config.is_valid() else null


static func from_resource(path: String) -> IdleConfig:
	if not FileAccess.file_exists(path):
		return null
	return from_json(FileAccess.get_file_as_string(path))


static func _realm_from_dictionary(data: Dictionary) -> RealmDef:
	var realm := RealmDef.new()
	realm.id = str(data.get("id", "")).strip_edges()
	realm.display_name = str(data.get("display_name", "")).strip_edges()
	realm.order = int(data.get("order", -1))
	realm.gain_per_second = float(data.get("gain_per_second", 0.0))
	realm.breakthrough_cost = float(data.get("breakthrough_cost", 0.0))
	realm.next_id = str(data.get("next_id", "")).strip_edges()
	if (
		realm.id.is_empty()
		or realm.display_name.is_empty()
		or realm.order < 0
		or realm.gain_per_second <= 0.0
		or realm.breakthrough_cost <= 0.0
	):
		return null
	return realm


func is_valid() -> bool:
	if schema_version != CURRENT_SCHEMA_VERSION:
		return false
	if offline_cap_seconds <= 0 or realms.is_empty():
		return false

	var seen_ids: Dictionary = {}
	var seen_orders: Dictionary = {}
	for index in range(realms.size()):
		var realm: RealmDef = realms[index]
		if seen_ids.has(realm.id) or seen_orders.has(realm.order):
			return false
		if realm.order != index:
			return false
		seen_ids[realm.id] = true
		seen_orders[realm.order] = true

	for index in range(realms.size()):
		var realm: RealmDef = realms[index]
		var is_last := index == realms.size() - 1
		if is_last:
			if realm.has_next():
				return false
		elif realm.next_id != realms[index + 1].id:
			return false
	return true


func starting_realm() -> RealmDef:
	return realms[0] if not realms.is_empty() else null


func realm_by_id(realm_id: String) -> RealmDef:
	for realm in realms:
		if realm.id == realm_id:
			return realm
	return null


func next_realm(realm: RealmDef) -> RealmDef:
	if realm == null or not realm.has_next():
		return null
	return realm_by_id(realm.next_id)


func display_path(realm: RealmDef, limit: int = 3) -> String:
	var names: PackedStringArray = []
	var current := realm
	while current != null and names.size() < limit:
		names.append(current.display_name)
		current = next_realm(current)
	return "  →  ".join(names)
