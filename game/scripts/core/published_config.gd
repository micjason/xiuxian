class_name PublishedConfig
extends RefCounted

const HOST := "101.132.74.32"
const PORT := 80
const PATH := "/content/published"
const TIMEOUT_MSEC := 3000


static func fetch() -> Dictionary:
	var client := HTTPClient.new()
	if client.connect_to_host(HOST, PORT) != OK:
		return {}
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		if Time.get_ticks_msec() > deadline:
			return {}
		client.poll()
		OS.delay_msec(10)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return {}
	if client.request(HTTPClient.METHOD_GET, PATH, PackedStringArray(["User-Agent: xiuxian"])) != OK:
		return {}
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		if Time.get_ticks_msec() > deadline:
			return {}
		client.poll()
		OS.delay_msec(10)
	if client.get_response_code() != 200:
		return {}
	var body := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		if Time.get_ticks_msec() > deadline:
			break
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.is_empty():
			OS.delay_msec(10)
		else:
			body.append_array(chunk)
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = parser.data
	if data.get("idle") == null:
		return {}
	return data
