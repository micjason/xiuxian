extends GutTest


func test_blank_marker_stays_blank() -> void:
	assert_eq(InstallMarker.display_text("  "), "")


func test_first_return_adds_kept_once() -> void:
	assert_eq(InstallMarker.display_text("首次安装 0.1.0"), "首次安装 0.1.0（已保留）")


func test_already_kept_marker_is_not_stacked() -> void:
	assert_eq(
		InstallMarker.display_text("首次安装 0.1.0（已保留）"),
		"首次安装 0.1.0（已保留）"
	)
