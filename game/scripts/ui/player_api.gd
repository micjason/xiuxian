class_name PlayerApi
extends RefCounted

const HOST := "101.132.74.32"
const PORT := 80
const TOKEN_PATH := "user://player_token.txt"


static func token() -> String:
	if not FileAccess.file_exists(TOKEN_PATH):
		return ""
	return FileAccess.get_file_as_string(TOKEN_PATH).strip_edges()


static func save_token(value: String) -> void:
	var file := FileAccess.open(TOKEN_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(value)


static func clear_token() -> void:
	if FileAccess.file_exists(TOKEN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TOKEN_PATH))


static func register(username: String, password: String) -> Dictionary:
	return _request(HTTPClient.METHOD_POST, "/auth/register", {"username": username, "password": password}, "")


static func login(username: String, password: String) -> Dictionary:
	return _request(HTTPClient.METHOD_POST, "/auth/login", {"username": username, "password": password}, "")


static func me(session_token: String, version_code: int) -> Dictionary:
	return _request(HTTPClient.METHOD_GET, "/me?versionCode=%d" % version_code, {}, session_token)


static func dismiss_notice(session_token: String, notice_id: String) -> Dictionary:
	return _request(HTTPClient.METHOD_POST, "/me/notices/%s/dismiss" % notice_id.uri_encode(), {}, session_token)


static func breakthrough(session_token: String) -> Dictionary:
	return _request(HTTPClient.METHOD_POST, "/me/breakthrough", {}, session_token)


static func _request(method: int, path: String, body: Dictionary, session_token: String) -> Dictionary:
	var client := HTTPClient.new()
	if client.connect_to_host(HOST, PORT) != OK:
		return {}
	var deadline := Time.get_ticks_msec() + 8000
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		if Time.get_ticks_msec() > deadline:
			return {}
		client.poll()
		OS.delay_msec(10)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return {}
	var headers := PackedStringArray(["User-Agent: xiuxian", "Content-Type: application/json"])
	if not session_token.is_empty():
		headers.append("Authorization: Bearer %s" % session_token)
	var payload := JSON.stringify(body) if not body.is_empty() else ""
	if client.request(method, path, headers, payload) != OK:
		return {}
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() > deadline:
			return {}
		client.poll()
		OS.delay_msec(10)
	var bytes := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		if Time.get_ticks_msec() > deadline:
			break
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.is_empty():
			OS.delay_msec(10)
		else:
			bytes.append_array(chunk)
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "code": client.get_response_code()}
	var data: Dictionary = parser.data
	data["code"] = client.get_response_code()
	return data
