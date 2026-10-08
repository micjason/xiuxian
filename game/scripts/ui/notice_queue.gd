class_name NoticeQueue
extends RefCounted

var current: Dictionary = {}
var _waiting: Array[Dictionary] = []
var _session_hidden: Array[String] = []


func sync(notices: Array) -> void:
	var incoming: Array[Dictionary] = []
	for item in notices:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var notice: Dictionary = item
		var template := str(notice.get("template", ""))
		if template != "confirm" and template != "acknowledge" and template != "reward":
			continue
		var id := str(notice.get("id", ""))
		if id.is_empty() or _session_hidden.has(id):
			continue
		incoming.append(notice)
	var incoming_ids: Array[String] = []
	for notice in incoming:
		incoming_ids.append(str(notice.get("id", "")))
	var kept: Array[Dictionary] = []
	for notice in _waiting:
		if incoming_ids.has(str(notice.get("id", ""))):
			kept.append(notice)
	_waiting = kept
	for notice in incoming:
		var id := str(notice.get("id", ""))
		if id == str(current.get("id", "")) or _contains(id):
			continue
		_waiting.append(notice)
	if current.is_empty():
		_present()


func close_current(hide_for_session: bool) -> void:
	var id := str(current.get("id", ""))
	if hide_for_session and not id.is_empty():
		_session_hidden.append(id)
	current = {}
	_present()


func _present() -> void:
	if _waiting.is_empty():
		return
	_waiting.sort_custom(_before)
	current = _waiting.pop_front()


func _contains(id: String) -> bool:
	for notice in _waiting:
		if str(notice.get("id", "")) == id:
			return true
	return false


func _before(left: Dictionary, right: Dictionary) -> bool:
	var left_priority := int(left.get("priority", 0))
	var right_priority := int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority < right_priority
	var left_time := str(left.get("triggeredAt", ""))
	var right_time := str(right.get("triggeredAt", ""))
	if left_time != right_time:
		return left_time < right_time
	return str(left.get("id", "")) < str(right.get("id", ""))
