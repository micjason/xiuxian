extends GutTest


func test_newer_version_is_detected() -> void:
	assert_true(AppVersion.is_newer("0.1.1", "0.1.0"))
	assert_true(AppVersion.is_newer("1.0.0", "0.9.99"))
	assert_true(AppVersion.is_newer("0.2", "0.1.99"))


func test_same_or_older_version_is_not_newer() -> void:
	assert_false(AppVersion.is_newer("0.1.0", "0.1.0"))
	assert_false(AppVersion.is_newer("0.0.9", "0.1.0"))
	assert_false(AppVersion.is_newer("1.2", "1.2.0"))


func test_invalid_versions_are_rejected() -> void:
	assert_false(AppVersion.is_valid(""))
	assert_false(AppVersion.is_valid("one.two"))
	assert_false(AppVersion.is_newer("next", "0.1.0"))
	assert_true(AppVersion.is_valid("v0.1.1"))


func test_installable_release_requires_higher_version_code() -> void:
	assert_true(AppVersion.is_installable("0.1.4", 5, "0.1.3", 4))
	assert_false(AppVersion.is_installable("0.1.4", 5, "0.1.4", 5))
	assert_false(AppVersion.is_installable("0.1.5", 5, "0.1.4", 5))
	assert_true(AppVersion.is_installable("0.1.5", 6, "0.1.4", 5))
	assert_true(AppVersion.is_installable("0.1.5", 6, "0.1.4", 0))
	assert_false(AppVersion.is_installable("0.1.4", 6, "0.1.4", 0))
