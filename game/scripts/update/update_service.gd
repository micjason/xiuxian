class_name UpdateService
extends Node

signal status_changed(message: String)
signal update_available(info: Dictionary)
signal no_update(version: String)
signal download_progress_changed(progress: float)
signal download_ready(path: String)
signal failed(message: String)

const MANIFEST_URL := "https://cdn.jsdelivr.net/gh/micjason/xiuxian-releases@main/update.json"
const SIGNATURE_URL := "https://cdn.jsdelivr.net/gh/micjason/xiuxian-releases@main/update.sig"
const PUBLIC_KEY_PATH := "res://assets/security/update_public.pem"
const DOWNLOAD_DIRECTORY := "user://updates"
const DOWNLOAD_TEMP_PATH := DOWNLOAD_DIRECTORY + "/xiuxian.apk.part"
const DOWNLOAD_PATH := DOWNLOAD_DIRECTORY + "/xiuxian.apk"
const CHECK_TIMEOUT_MSEC := 90_000

var current_manifest: UpdateManifest
var _manifest_bytes := PackedByteArray()
var _installer := AndroidInstaller.new()
var _is_checking := false
var _check_started_at_msec := 0
var _is_downloading := false
var _manifest_request: HTTPRequest
var _signature_request: HTTPRequest
var _apk_request: HTTPRequest


func _ready() -> void:
	_manifest_request = _create_request(60.0)
	_signature_request = _create_request(60.0)
	_apk_request = _create_request(1800.0)
	_manifest_request.request_completed.connect(_on_manifest_received)
	_signature_request.request_completed.connect(_on_signature_received)
	_apk_request.request_completed.connect(_on_apk_received)


func _process(_delta: float) -> void:
	if _is_checking and Time.get_ticks_msec() - _check_started_at_msec > CHECK_TIMEOUT_MSEC:
		_manifest_request.cancel_request()
		_signature_request.cancel_request()
		_fail("检查更新超时，请确认网络后重试。")
	if not _is_downloading:
		return
	var total_bytes := _apk_request.get_body_size()
	if total_bytes <= 0 and current_manifest != null:
		total_bytes = current_manifest.apk_size
	var downloaded_bytes := _apk_request.get_downloaded_bytes()
	if total_bytes > 0:
		download_progress_changed.emit(clampf(float(downloaded_bytes) / float(total_bytes), 0.0, 1.0))


func get_current_version() -> String:
	return _installer.get_version_name()


func check_for_update() -> void:
	if _manifest_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_is_checking = true
	_check_started_at_msec = Time.get_ticks_msec()
	status_changed.emit("正在检查更新…")
	var error := _manifest_request.request(MANIFEST_URL, _request_headers())
	if error != OK:
		_fail("无法开始检查更新，请稍后重试。")


func download_update() -> void:
	if current_manifest == null or _is_downloading:
		return

	var absolute_directory := ProjectSettings.globalize_path(DOWNLOAD_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		_fail("无法创建更新文件夹。")
		return

	_remove_if_exists(DOWNLOAD_TEMP_PATH)
	_apk_request.download_file = DOWNLOAD_TEMP_PATH
	_is_downloading = true
	status_changed.emit("正在下载安装包…")
	download_progress_changed.emit(0.0)
	var error := _apk_request.request(
		current_manifest.apk_url,
		_request_headers(["Accept: application/octet-stream"])
	)
	if error != OK:
		_is_downloading = false
		_fail("无法开始下载，请稍后重试。")


func install_downloaded_update() -> void:
	if not FileAccess.file_exists(DOWNLOAD_PATH):
		_fail("安装包不存在，请重新下载。")
		return
	if not _installer.is_supported():
		_fail("覆盖安装只支持 Android 手机。")
		return
	if not _installer.can_request_package_installs():
		status_changed.emit("请在系统页面允许“修仙”安装应用，返回后再次点击安装。")
		_installer.request_install_permission()
		return
	if not _installer.install_apk(DOWNLOAD_PATH):
		_fail("无法打开系统安装页面。")


func _create_request(timeout_seconds: float) -> HTTPRequest:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = timeout_seconds
	add_child(request)
	return request


func _request_headers(extra: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var headers := PackedStringArray([
		"User-Agent: XiuxianUpdater/0.1",
		"Cache-Control: no-cache",
	])
	headers.append_array(extra)
	return headers


func _on_manifest_received(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.is_empty():
		_fail("获取更新信息失败（%d/%d），请检查网络。" % [result, response_code])
		return
	_manifest_bytes = body
	status_changed.emit("正在验证更新信息…")
	var error := _signature_request.request(SIGNATURE_URL, _request_headers())
	if error != OK:
		_fail("无法获取更新签名。")


func _on_signature_received(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	signature: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or signature.is_empty():
		_fail("更新签名下载失败。")
		return
	_is_checking = false
	if not _verify_manifest_signature(_manifest_bytes, signature):
		_fail("更新信息安全校验失败。")
		return

	current_manifest = UpdateManifest.from_json(_manifest_bytes.get_string_from_utf8())
	if current_manifest == null:
		_fail("更新信息格式不正确。")
		return

	var current_version := get_current_version()
	if not AppVersion.is_newer(current_manifest.version, current_version):
		status_changed.emit("当前已是最新版本。")
		no_update.emit(current_version)
		return

	status_changed.emit("发现新版本 %s" % current_manifest.version)
	update_available.emit(current_manifest.as_dictionary())


func _on_apk_received(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	_is_downloading = false
	_apk_request.download_file = ""
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_remove_if_exists(DOWNLOAD_TEMP_PATH)
		_fail("安装包下载失败，请稍后重试。")
		return
	if not _verify_download():
		_remove_if_exists(DOWNLOAD_TEMP_PATH)
		_fail("安装包校验失败，请重新下载。")
		return

	_remove_if_exists(DOWNLOAD_PATH)
	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(DOWNLOAD_TEMP_PATH),
		ProjectSettings.globalize_path(DOWNLOAD_PATH)
	)
	if rename_error != OK:
		_fail("无法保存已验证的安装包。")
		return

	download_progress_changed.emit(1.0)
	status_changed.emit("下载完成，准备打开系统安装页面。")
	download_ready.emit(DOWNLOAD_PATH)


func _verify_manifest_signature(data: PackedByteArray, signature: PackedByteArray) -> bool:
	var public_key := CryptoKey.new()
	if public_key.load(PUBLIC_KEY_PATH, true) != OK:
		push_error("Unable to load update public key.")
		return false
	var crypto := Crypto.new()
	return crypto.verify(
		HashingContext.HASH_SHA256,
		_sha256_bytes(data),
		signature,
		public_key
	)


func _verify_download() -> bool:
	if current_manifest == null or not FileAccess.file_exists(DOWNLOAD_TEMP_PATH):
		return false
	var file := FileAccess.open(DOWNLOAD_TEMP_PATH, FileAccess.READ)
	if file == null or file.get_length() != current_manifest.apk_size:
		return false
	var actual_hash := _sha256_file(file)
	return actual_hash == current_manifest.apk_sha256


func _sha256_file(file: FileAccess) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	while file.get_position() < file.get_length():
		var remaining := file.get_length() - file.get_position()
		context.update(file.get_buffer(mini(remaining, 64 * 1024)))
	return context.finish().hex_encode()


func _sha256_bytes(data: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	context.update(data)
	return context.finish()


func _remove_if_exists(project_path: String) -> void:
	if FileAccess.file_exists(project_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(project_path))


func _fail(message: String) -> void:
	_is_checking = false
	status_changed.emit(message)
	failed.emit(message)
