class_name PlayerApi
extends RefCounted

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
	return await ApiClient.request_json(HTTPClient.METHOD_POST, "/api/v1/auth/register", {"username": username, "password": password})


static func login(username: String, password: String) -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_POST, "/api/v1/auth/login", {"username": username, "password": password})


static func me(session_token: String, version_code: int) -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_GET, "/api/v1/me?versionCode=%d" % version_code, {}, session_token)


static func dismiss_notice(session_token: String, notice_id: String) -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_POST, "/api/v1/me/notices/%s/dismiss" % notice_id.uri_encode(), {}, session_token)


static func breakthrough(session_token: String) -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_POST, "/api/v1/me/breakthrough", {}, session_token)
