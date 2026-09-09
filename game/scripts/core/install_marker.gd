class_name InstallMarker
extends RefCounted

const KEPT_SUFFIX := "（已保留）"


static func display_text(saved_marker: String) -> String:
	var cleaned := saved_marker.strip_edges()
	if cleaned.is_empty():
		return ""
	if cleaned.ends_with(KEPT_SUFFIX):
		return cleaned
	return cleaned + KEPT_SUFFIX
