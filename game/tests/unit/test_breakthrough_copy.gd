extends GutTest


func test_banner_shows_realm_change_and_new_rate() -> void:
	assert_eq(
		BreakthroughCopy.banner("凡人", "炼气初期", 3.5),
		"突破成功  凡人 → 炼气初期\n修炼效率提升至 3.50/秒"
	)
