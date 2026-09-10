extends GutTest


func test_client_reads_purgeable_latest_channel() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/update/update_service.gd")
	assert_false(source.is_empty())
	assert_true(source.contains("@latest/update.json"))
	assert_true(source.contains("@latest/update.sig"))
	assert_false(source.contains("@main/update.json"))
	assert_true(source.contains("is_installable"))
	assert_true(source.contains("version_code"))
