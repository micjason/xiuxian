class_name AppVersion
extends RefCounted


static func is_newer(candidate: String, current: String) -> bool:
	var candidate_parts := _parse(candidate)
	var current_parts := _parse(current)
	if candidate_parts.is_empty() or current_parts.is_empty():
		return false

	var part_count: int = maxi(candidate_parts.size(), current_parts.size())
	for index in range(part_count):
		var candidate_part: int = candidate_parts[index] if index < candidate_parts.size() else 0
		var current_part: int = current_parts[index] if index < current_parts.size() else 0
		if candidate_part != current_part:
			return candidate_part > current_part
	return false


# Android only installs an APK when versionCode is strictly higher. A newer
# version name with the same code still opens the system page as “打开”.
static func is_installable(candidate: String, candidate_code: int, current: String, current_code: int) -> bool:
	if candidate_code > 0 and current_code > 0:
		return candidate_code > current_code
	return is_newer(candidate, current)


static func is_valid(value: String) -> bool:
	return not _parse(value).is_empty()


static func _parse(value: String) -> Array[int]:
	var normalized := value.strip_edges()
	if normalized.begins_with("v"):
		normalized = normalized.substr(1)
	if normalized.is_empty():
		return []

	var result: Array[int] = []
	for part in normalized.split("."):
		if part.is_empty() or not part.is_valid_int():
			return []
		var number := part.to_int()
		if number < 0:
			return []
		result.append(number)
	return result
