class_name UpdateManifest
extends RefCounted

var version: String
var version_code: int
var minimum_version: String
var apk_url: String
var apk_size: int
var apk_sha256: String
var release_notes: String


static func from_json(text: String) -> UpdateManifest:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return null

	var data: Dictionary = parsed
	var manifest := UpdateManifest.new()
	manifest.version = str(data.get("version", "")).strip_edges()
	manifest.version_code = int(data.get("version_code", 0))
	manifest.minimum_version = str(data.get("minimum_version", "0.1.0")).strip_edges()
	manifest.apk_url = str(data.get("apk_url", "")).strip_edges()
	manifest.apk_size = int(data.get("apk_size", 0))
	manifest.apk_sha256 = str(data.get("apk_sha256", "")).to_lower().strip_edges()
	manifest.release_notes = str(data.get("release_notes", "")).strip_edges()
	return manifest if manifest.is_valid() else null


func is_valid() -> bool:
	return (
		AppVersion.is_valid(version)
		and version_code > 0
		and AppVersion.is_valid(minimum_version)
		and _apk_url_allowed(apk_url)
		and apk_size > 0
		and apk_sha256.length() == 64
		and apk_sha256.is_valid_hex_number(false)
	)


static func _apk_url_allowed(url: String) -> bool:
	return url.begins_with("https://") or url.begins_with("http://127.0.0.1") or url.begins_with("http://localhost")


func as_dictionary() -> Dictionary:
	return {
		"version": version,
		"version_code": version_code,
		"minimum_version": minimum_version,
		"apk_url": apk_url,
		"apk_size": apk_size,
		"apk_sha256": apk_sha256,
		"release_notes": release_notes,
		"force_update": minimum_version == version and version != "0.1.0",
	}
