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
