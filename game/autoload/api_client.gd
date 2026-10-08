extends Node

func request_json(method: int, path: String, body: Dictionary = {}, session_token: String = "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	var headers := PackedStringArray(["User-Agent: xiuxian", "Content-Type: application/json"])
	if not session_token.is_empty():
		headers.append("Authorization: Bearer %s" % session_token)
	var payload := "" if body.is_empty() else JSON.stringify(body)
	var url := "%s%s" % [AppEnv.api_base_url(), path]
	if http.request(url, headers, method, payload) != OK:
		http.queue_free()
		return {}
	var completed: Array = await http.request_completed
	var code := int(completed[1])
	var raw := PackedByteArray(completed[3])
	http.queue_free()
	var parser := JSON.new()
	if parser.parse(raw.get_string_from_utf8()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "code": code}
	var data: Dictionary = parser.data
	data["code"] = code
	return data
