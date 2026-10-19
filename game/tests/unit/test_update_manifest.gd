extends GutTest


func test_valid_manifest_is_parsed() -> void:
	var json := JSON.stringify({
		"version": "0.1.1",
		"version_code": 2,
		"minimum_version": "0.1.0",
		"apk_url": "https://example.com/xiuxian.apk",
		"apk_size": 1024,
		"apk_sha256": "a".repeat(64),
		"release_notes": "更新测试",
	})
	var manifest := UpdateManifest.from_json(json)

	assert_not_null(manifest)
	assert_eq(manifest.version, "0.1.1")
	assert_eq(manifest.version_code, 2)
	assert_eq(manifest.apk_size, 1024)


func test_self_hosted_http_url_is_accepted() -> void:
	var json := JSON.stringify({
		"version": "0.6.4",
		"version_code": 21,
		"minimum_version": "0.6.4",
		"apk_url": "http://127.0.0.1:8080/apk/xiuxian.apk",
		"apk_size": 1024,
		"apk_sha256": "a".repeat(64),
	})
	var manifest := UpdateManifest.from_json(json)
	assert_not_null(manifest)
	assert_true(manifest.as_dictionary()["force_update"])


func test_invalid_url_is_rejected() -> void:
	var json := JSON.stringify({
		"version": "0.1.1",
		"version_code": 2,
		"minimum_version": "0.1.0",
		"apk_url": "http://unsafe.example/xiuxian.apk",
		"apk_size": 1024,
		"apk_sha256": "a".repeat(64),
	})
	assert_null(UpdateManifest.from_json(json))


func test_invalid_hash_is_rejected() -> void:
	var json := JSON.stringify({
		"version": "0.1.1",
		"version_code": 2,
		"minimum_version": "0.1.0",
		"apk_url": "https://example.com/xiuxian.apk",
		"apk_size": 1024,
		"apk_sha256": "not-a-sha256",
	})
	assert_null(UpdateManifest.from_json(json))


func test_malformed_json_is_rejected() -> void:
	assert_null(UpdateManifest.from_json("{broken"))


func test_new_latest_json_format_with_relative_url() -> void:
	var json := JSON.stringify({
		"versionCode": 31, "versionName": "0.11.0", "url": "/download/a.apk",
		"sha256": "c".repeat(64), "size": 10, "notes": "说明", "force": true,
	})
	var manifest := UpdateManifest.from_json(json, "http://101.132.74.32:8090")
	assert_not_null(manifest)
	assert_eq(manifest.apk_url, "http://101.132.74.32:8090/download/a.apk")
	assert_eq(manifest.version_code, 31)
	assert_eq(manifest.release_notes, "说明")
	assert_true(manifest.as_dictionary()["force_update"])


func test_http_apk_only_from_the_same_server() -> void:
	var base := "http://101.132.74.32:8090"
	var same := {"versionCode": 2, "versionName": "0.1.1", "url": "http://101.132.74.32:8090/download/a.apk", "sha256": "a".repeat(64)}
	assert_not_null(UpdateManifest.from_json(JSON.stringify(same), base))
	var other := same.duplicate()
	other.url = "http://evil.example/x/a.apk"
	assert_null(UpdateManifest.from_json(JSON.stringify(other), base))
	var other_port := same.duplicate()
	other_port.url = "http://101.132.74.32:9999/x/a.apk"
	assert_null(UpdateManifest.from_json(JSON.stringify(other_port), base))


func test_download_url_follows_the_connected_server() -> void:
	var json := JSON.stringify({"versionCode": 2, "versionName": "0.1.1", "url": "http://101.132.74.32:8090/download/a.apk", "sha256": "a".repeat(64)})
	var manifest := UpdateManifest.from_json(json, "http://127.0.0.1:18090")
	assert_not_null(manifest)
	assert_eq(manifest.apk_url, "http://127.0.0.1:18090/download/a.apk")
