class_name PublishedConfig
extends RefCounted

const PATH := "/content/published"


static func fetch() -> Dictionary:
	var data: Dictionary = await ApiClient.request_json(HTTPClient.METHOD_GET, PATH)
	if int(data.get("code", 0)) != 200 or data.get("idle") == null:
		return {}
	return data
