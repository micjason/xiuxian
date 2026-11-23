extends RefCounted
## 读取后台已保存的战斗预览。空动作表示游戏继续用原来的演法。
## 某一动作的帧读失败时记在 failed 里，调用方不能改去播旧图。

static func load_current() -> Dictionary:
	var data: Dictionary = await ApiClient.request_json(HTTPClient.METHOD_GET, "/api/v1/battle-preview/playback")
	if int(data.get("code", 0)) != 200 or not data.has("actions"):
		push_error("没有读到后台保存的战斗画面")
		return {}
	var actions: Dictionary = data.get("actions", {})
	var loaded := {
		"projectileFrame": int(data.get("projectileFrame", 1)),
		"actions": {},
		"failed": {},
	}
	for action_name in ["idle", "attack", "hit", "projectile", "impact"]:
		var frames: Array = actions.get(action_name, [])
		var ready: Array = []
		var broken := false
		for frame in frames:
			if typeof(frame) != TYPE_DICTIONARY:
				broken = true
				break
			var texture := await _texture(str(frame.get("clipId", "")), str(frame.get("name", "")))
			if texture == null:
				broken = true
				break
			ready.append({"texture": texture, "duration_ms": int(frame.get("durationMs", 83))})
		if broken:
			loaded["failed"][action_name] = true
			loaded["actions"][action_name] = []
			push_error("战斗画面「%s」的帧没有载入，这一下不会改用旧图" % action_name)
		else:
			loaded["actions"][action_name] = ready
	return loaded


static func _texture(clip_id: String, file_name: String) -> Texture2D:
	var client := Engine.get_main_loop().root.get_node_or_null("ApiClient")
	if client == null or not client.has_method("request_bytes"):
		return null
	var response: Dictionary = await client.request_bytes("/api/v1/battle-preview/frames/%s/%s" % [clip_id, file_name])
	if int(response.get("code", 0)) != 200:
		return null
	var image := Image.new()
	if image.load_png_from_buffer(response.get("bytes", PackedByteArray())) != OK:
		return null
	return ImageTexture.create_from_image(image)
