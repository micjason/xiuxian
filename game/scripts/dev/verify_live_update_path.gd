extends SceneTree

# Fetch the live channel with the same Godot HTTPRequest stack the phone uses.
# Does not rebuild, upload, or clobber a Release.

const OUT := "/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4/client_http_path.json"
const PUBLIC_KEY_PATH := "res://assets/security/update_public.pem"
const WANT_VERSION := "0.1.4"
const WANT_SHA := "a68b9b5b2831ac867b40b92cd6243fc2937b69f36ffc2e5a0a75b389fd1d2667"
const MAIN_BASE := "https://cdn.jsdelivr.net/gh/micjason/xiuxian-releases@main"
const LATEST_BASE := "https://cdn.jsdelivr.net/gh/micjason/xiuxian-releases@latest"
const APK_PATH := "/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4/client_http_xiuxian.apk"

var _ok := true
var _report: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var main_info: Dictionary = await _fetch_channel("main", MAIN_BASE)
	var latest_info: Dictionary = await _fetch_channel("latest", LATEST_BASE)
	_report["main"] = main_info
	_report["latest"] = latest_info

	if not bool(main_info.get("ok", false)) or not bool(latest_info.get("ok", false)):
		_fail("manifest or signature request failed")
	elif str(main_info.get("apk_sha256", "")) != str(latest_info.get("apk_sha256", "")):
		_fail("main and latest manifests disagree")
	elif str(main_info.get("apk_sha256", "")) != WANT_SHA:
		_fail("live sha is not the published 0.1.4 package")
	else:
		var apk_info: Dictionary = await _download_apk(str(main_info.get("apk_url", "")), int(main_info.get("apk_size", 0)))
		_report["apk"] = apk_info
		if not bool(apk_info.get("ok", false)):
			_fail("apk download or hash failed")

	_report["ok"] = _ok
	_write_report()
	print("client_http_path ok=%s report=%s" % [_ok, OUT])
	quit(0 if _ok else 1)


func _fetch_channel(name: String, base: String) -> Dictionary:
	var info := {
		"name": name,
		"ok": false,
		"version": "",
		"apk_sha256": "",
		"apk_url": "",
		"apk_size": 0,
		"error": "",
	}
	var json_body: PackedByteArray = await _get_bytes("%s/update.json" % base, PackedStringArray())
	if json_body.is_empty():
		info["error"] = "empty manifest"
		return info
	var sig_body: PackedByteArray = await _get_bytes("%s/update.sig" % base, PackedStringArray())
	if sig_body.is_empty():
		info["error"] = "empty signature"
		return info
	if not _verify_signature(json_body, sig_body):
		info["error"] = "signature mismatch"
		return info
	var manifest := UpdateManifest.from_json(json_body.get_string_from_utf8())
	if manifest == null:
		info["error"] = "invalid manifest"
		return info
	if manifest.version != WANT_VERSION:
		info["error"] = "unexpected version %s" % manifest.version
		return info
	info["ok"] = true
	info["version"] = manifest.version
	info["apk_sha256"] = manifest.apk_sha256
	info["apk_url"] = manifest.apk_url
	info["apk_size"] = manifest.apk_size
	print(
		"channel=%s version=%s sha=%s asset=%s"
		% [name, manifest.version, manifest.apk_sha256.substr(0, 16), manifest.apk_url.get_file()]
	)
	return info


func _download_apk(url: String, expected_size: int) -> Dictionary:
	var info := {"ok": false, "sha256": "", "size": 0, "error": "", "http": 0}
	if url.is_empty():
		info["error"] = "missing apk url"
		return info
	_remove_if_exists(APK_PATH)
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = 1800.0
	http.download_file = APK_PATH
	root.add_child(http)
	var error := http.request(url, _headers(PackedStringArray(["Accept: application/octet-stream"])))
	if error != OK:
		info["error"] = "apk request start failed %d" % error
		http.queue_free()
		return info
	var completed: Array = await http.request_completed
	http.queue_free()
	var result: int = completed[0]
	var response_code: int = completed[1]
	info["http"] = response_code
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		info["error"] = "apk http failed result=%d code=%d" % [result, response_code]
		_remove_if_exists(APK_PATH)
		return info
	var file := FileAccess.open(APK_PATH, FileAccess.READ)
	if file == null:
		info["error"] = "apk missing after download"
		return info
	info["size"] = file.get_length()
	info["sha256"] = _sha256_file(file)
	if info["size"] != expected_size or info["sha256"] != WANT_SHA:
		info["error"] = "apk hash or size mismatch"
		return info
	info["ok"] = true
	print("apk downloaded size=%s sha=%s" % [info["size"], str(info["sha256"]).substr(0, 16)])
	return info


func _get_bytes(url: String, extra: PackedStringArray) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = 60.0
	root.add_child(http)
	var error := http.request(url, _headers(extra))
	if error != OK:
		print("request start failed %s error=%s" % [url, error])
		http.queue_free()
		return PackedByteArray()
	var completed: Array = await http.request_completed
	http.queue_free()
	var result: int = completed[0]
	var response_code: int = completed[1]
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.is_empty():
		print("request failed %s result=%s code=%s" % [url, result, response_code])
		return PackedByteArray()
	return body


func _headers(extra: PackedStringArray) -> PackedStringArray:
	var headers := PackedStringArray([
		"User-Agent: XiuxianUpdater/0.1",
		"Cache-Control: no-cache",
	])
	headers.append_array(extra)
	return headers


func _verify_signature(data: PackedByteArray, signature: PackedByteArray) -> bool:
	var public_key := CryptoKey.new()
	if public_key.load(PUBLIC_KEY_PATH, true) != OK:
		print("unable to load update public key")
		return false
	var crypto := Crypto.new()
	return crypto.verify(
		HashingContext.HASH_SHA256,
		_sha256_bytes(data),
		signature,
		public_key
	)


func _sha256_bytes(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	context.update(data)
	return context.finish()


func _sha256_file(file: FileAccess) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	while file.get_position() < file.get_length():
		var remaining := file.get_length() - file.get_position()
		context.update(file.get_buffer(mini(remaining, 64 * 1024)))
	return context.finish().hex_encode()


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _fail(message: String) -> void:
	_ok = false
	_report["error"] = message
	print("client_http_path FAIL %s" % message)


func _write_report() -> void:
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	if file == null:
		print("unable to write %s" % OUT)
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
