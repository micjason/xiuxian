class_name PlayerApi
extends RefCounted

const TOKEN_PATH := "user://player_token.txt"
## 登录时记下的账号名 / 玩家 id（设置页显示用；服务器 /me/account 拿到后会覆盖）。
const ACCOUNT_PATH := "user://player_account.json"


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


static func save_account(username: String, player_id: String) -> void:
	var file := FileAccess.open(ACCOUNT_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"username": username, "playerId": player_id}))


static func account() -> Dictionary:
	if not FileAccess.file_exists(ACCOUNT_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ACCOUNT_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## 退出登录的本机部分：删掉令牌和账号记录（之后启动会停在登录页，可以登录别的账号）。
static func forget_session() -> void:
	clear_token()
	if FileAccess.file_exists(ACCOUNT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ACCOUNT_PATH))


## 退出登录的服务器部分：作废这个令牌（本机先 forget_session，网络失败也不拦着退出）。
static func revoke(session_token: String) -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_POST, "/api/v1/auth/logout", {}, session_token)


static func fetch_account() -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_GET, "/api/v1/me/account", {}, token())


static func register(username: String, password: String) -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_POST, "/api/v1/auth/register", {"username": username, "password": password})


static func login(username: String, password: String) -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_POST, "/api/v1/auth/login", {"username": username, "password": password})


static func dismiss_notice(session_token: String, notice_id: String) -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_POST, "/api/v1/me/notices/%s/dismiss" % notice_id.uri_encode(), {}, session_token)


static func fetch_state() -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_GET, "/api/v1/me/state", {}, token())


static func fetch_content() -> Dictionary:
	return await ApiClient.request_json(HTTPClient.METHOD_GET, "/api/v1/content/current")


static func post_action(path: String, body: Dictionary = {}) -> Dictionary:
	var key := "play-%d-%06d" % [Time.get_ticks_msec(), randi() % 1000000]
	return await ApiClient.request_json(HTTPClient.METHOD_POST, path, body, token(), key)


static func error_message(data: Dictionary) -> String:
	var err: Variant = data.get("error", {})
	if typeof(err) == TYPE_DICTIONARY:
		return str((err as Dictionary).get("message", "请求失败"))
	if data.is_empty():
		return "网络失败，请确认本机服务器已打开"
	return "请求失败"
