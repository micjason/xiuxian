class_name TimeService
extends RefCounted

var _override_unix: int = -1


func now_unix() -> int:
	if _override_unix >= 0:
		return _override_unix
	return int(Time.get_unix_time_from_system())


func set_unix(value: int) -> void:
	_override_unix = value


func clear_override() -> void:
	_override_unix = -1


func elapsed_seconds(since_unix: int) -> int:
	return now_unix() - since_unix
