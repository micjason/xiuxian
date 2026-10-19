extends GutTest
## 客户端更新走 dev2 自建服务器：<服务器地址>/download/latest.json（不再用 jsDelivr / 签名文件）。


func test_client_reads_latest_json_from_server_address() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/update/update_service.gd")
	assert_false(source.is_empty())
	assert_true(source.contains("ServerAddress.current()"))
	assert_true(source.contains("\"/download/latest.json\""))
	assert_false(source.contains("101.132.74.32"), "地址不写死在代码里，由打包时的工程设置决定")
	assert_false(source.contains("jsdelivr"))
	assert_true(source.contains("is_installable"))
	assert_true(source.contains("get_apk_version_code"))
	assert_true(source.contains("open_in_browser"))


func test_manifest_url_follows_server_address() -> void:
	var service := UpdateService.new()
	add_child_autofree(service)
	OS.set_environment("XIUXIAN_API_BASE", "http://101.132.74.32:8090")
	assert_eq(service.manifest_url(), "http://101.132.74.32:8090/download/latest.json")
	OS.set_environment("XIUXIAN_API_BASE", "")


func _latest(code: int, force: bool = false) -> PackedByteArray:
	return JSON.stringify({
		"versionCode": code, "versionName": "0.11.%d" % code, "url": "/download/xiuxian-dev2-0.11.%d-%d.apk" % [code, code],
		"sha256": "b".repeat(64), "size": 2048, "notes": "测试说明", "force": force,
	}).to_utf8_buffer()


func test_higher_version_code_emits_update_available() -> void:
	var service := UpdateService.new()
	add_child_autofree(service)
	OS.set_environment("XIUXIAN_API_BASE", "http://101.132.74.32:8090")
	ProjectSettings.set_setting("xiuxian/build/version_code", 30)
	watch_signals(service)
	service._manifest_bytes = _latest(31)
	service._accept_manifest()
	assert_signal_emitted(service, "update_available")
	var info: Dictionary = get_signal_parameters(service, "update_available")[0]
	assert_eq(info.version_code, 31)
	assert_eq(info.apk_url, "http://101.132.74.32:8090/download/xiuxian-dev2-0.11.31-31.apk")
	assert_false(info.force_update)
	OS.set_environment("XIUXIAN_API_BASE", "")


func test_same_or_lower_version_code_is_quiet() -> void:
	var service := UpdateService.new()
	add_child_autofree(service)
	OS.set_environment("XIUXIAN_API_BASE", "http://101.132.74.32:8090")
	ProjectSettings.set_setting("xiuxian/build/version_code", 31)
	var old_name: Variant = ProjectSettings.get_setting("application/config/version")
	ProjectSettings.set_setting("application/config/version", "0.11.31")
	watch_signals(service)
	service._manifest_bytes = _latest(31)
	service._accept_manifest()
	assert_signal_not_emitted(service, "update_available")
	assert_signal_emitted(service, "no_update")
	ProjectSettings.set_setting("application/config/version", old_name)
	OS.set_environment("XIUXIAN_API_BASE", "")
